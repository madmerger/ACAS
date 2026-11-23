import Foundation

/// pl100.cbl: 支払転記 (Cash Posting)
enum PLB100 {
    static let progName = "PL100 (3.01.14)"

    final class State {
        let s: Session
        var purch = Record(PLB.purch)
        var oi = Record(PLB.oi)
        var batch = Record(PLB.batch)
        var post = Record(PLB.posting)
        let batchFile: IndexedFile
        let postFile: RelativeFile
        var rrn = 0
        var uDate = Cobol.x("", 10)
        var j = 0, lineCnt = 0
        var nDeduct: Int64 = 0
        var tPaid: Int64 = 0, tApprop: Int64 = 0, tDeduct: Int64 = 0
        var jPaid: Int64 = 0, jApprop: Int64 = 0, jDeduct: Int64 = 0
        let prt: PLBPrint
        var l2Date = ""
        init(_ s: Session) {
            self.s = s
            batchFile = PLB.batchFile(s)
            postFile = RelativeFile(s.store, path: s.ledgers + "posting.dat", recordSize: 96)
            prt = PLBPrint(s)
        }
        var gl: Bool { s.sys.int("level-1") == 1 }
        var irsUsed: Bool { s.sys.str("irs-instead") == "Y" }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State(s)
        st.l2Date = PLB.wsDate(s)
        if s.sys.int("p-flag-p") != 2 {
            try PLB.maps99(s, 23)
            try PLB.maps99(s, 15)
            return
        }
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("pl100.title"), at: 136, color: 2)
        c.display(PLB.wsDate(s), at: 171, color: 2)
        while true {
            c.display(s.t("pl100.ok_to_post"), at: 1212, color: 2)
            let r = Cobol.x(try c.accept(at: 1256, size: 3, initial: "   ", options: [.update], color: 6).uppercased(), 3)
            if r == "NO " { return }
            if r == "YES" { break }
        }
        let oiFile = PLB.oi5File(s), pf = PLB.purchFile(s)
        let oiOpen = oiFile.open() == "00"
        pf.open()
        if st.gl { blOpen(st) }
        st.prt.openOutput()
        headings(st)
        c.display(s.t("pl100.posting_wait"), at: 1601, color: 2)
        // 開けていない open-item-file-5 の READ NEXT は AT END にならず戻らない
        if !oiOpen { try PLB.hang(s) }
        while let rec = oiFile.readNext() {
            st.oi = rec
            let type = st.oi.int("oi-type")
            if type != 2 && type != 5 && type != 6 { continue }
            if type == 2 && st.oi.int("oi-b-nos") != 0 && st.oi.int("oi-b-item") != 0 {
                computePurchPay(st)
                st.oi.setInt("oi-b-nos", 0); st.oi.setInt("oi-b-item", 0); st.oi.setInt("oi-cr", 0)
                oiFile.rewrite(st.oi)
                continue
            }
            if st.oi.int("oi-status") == 1 || type == 2 { continue }
            if st.oi.int("oi-b-nos") == 0 && st.oi.int("oi-b-item") == 0 { continue }
            try custUpdate(st, oiFile, pf)
        }
        pf.close(); oiFile.close()
        var l5 = Line5()
        l5.name = s.l10n.raw("report.pl100.payment_totals")
        l5.approp = st.tApprop; l5.deduct = st.tDeduct; l5.paid = st.tPaid
        st.prt.after(l5.totals(), 3)
        l5.name = s.l10n.raw("report.pl100.journal_totals")
        l5.approp = st.jApprop; l5.deduct = st.jDeduct; l5.paid = st.jPaid
        st.prt.after(l5.totals(), 2)
        st.prt.close()
        st.prt.spool()
        st.tDeduct = Cobol.truncate(st.tDeduct + st.jDeduct, digits: 9)
        if st.tDeduct != 0 { analiseDeductions(st) }
        if st.gl { try blClose(st) }
        s.sys.set("oi-5-flag", "Y")
        s.sys.setInt("p-flag-p", 0)
    }

    /// line-5
    struct Line5 {
        var batch = "", sl = " ", item = "", date = "", cust = "", name = "", type = ""
        var oldBal: Int64 = 0, newBal: Int64 = 0, paid: Int64 = 0, deduct: Int64 = 0, approp: Int64 = 0
        func detail() -> String {
            Cobol.x(batch, 5) + sl + Cobol.x(item, 4) + Cobol.x(date, 11) + Cobol.x(cust, 8) + Cobol.x(name, 25)
                + "    " + Cobol.x(type, 10)
                + Pic.edit("z(6)9.99cr", value: oldBal, scale: 2) + "  " + Pic.edit("z(6)9.99cr", value: newBal, scale: 2)
                + " " + Pic.edit("z(6)9.99b", value: paid, scale: 2) + " " + Pic.edit("z(6)9.99b", value: deduct, scale: 2)
                + "   " + Pic.edit("z(6)9.99b", value: approp, scale: 2)
        }
        /// move spaces to line-5 の後、名称と 3 金額だけを設定した行
        func totals() -> String {
            Cobol.x("", 29) + Cobol.x(name, 25) + Cobol.x("", 41)
                + Pic.edit("z(6)9.99b", value: paid, scale: 2) + " " + Pic.edit("z(6)9.99b", value: deduct, scale: 2)
                + "   " + Pic.edit("z(6)9.99b", value: approp, scale: 2)
        }
    }

    static func custUpdate(_ st: State, _ oiFile: IndexedFile, _ pf: IndexedFile) throws {
        let s = st.s
        var l5 = Line5()
        let key = st.oi.raw("oi-supplier")
        st.purch.setRaw("purch-key", key)
        l5.cust = st.oi.str("oi-supplier")
        if let r = pf.read(key: key) {
            st.purch = r
            l5.name = st.purch.str("purch-name")
        } else {
            l5.name = s.l10n.raw("report.pl100.supplier_unknown")
        }
        l5.batch = Pic.edit("z9(4)", value: st.oi.int("oi-b-nos"), scale: 0)
        l5.sl = "/"
        l5.item = Cobol.z(st.oi.int("oi-b-item"), 3) + " "
        st.uDate = Maps04.toDate(Int(st.oi.int("oi-date")))
        l5.date = st.uDate          // move u-date to l5-date (UK 形式のまま)
        _ = PLB.binDate(s, st.oi.int("oi-date"))
        let approp = st.oi.int("oi-net"), paid = st.oi.int("oi-paid"), deductAmt = st.oi.int("oi-deduct-amt")
        l5.approp = approp; l5.paid = paid; l5.deduct = deductAmt
        if deductAmt != 0 { st.nDeduct += 1 }
        var current = st.purch.int("purch-current"), unapplied = st.purch.int("purch-unapplied")
        l5.oldBal = current - unapplied
        current = Cobol.truncate(current - approp, digits: 10)
        current = Cobol.truncate(current - deductAmt, digits: 10)
        if paid != approp {
            let work1 = Cobol.truncate(paid - approp, digits: 9)
            unapplied = Cobol.truncate(unapplied + work1, digits: 10)
        }
        if current < 0 {
            let work1 = Cobol.truncate(-current, digits: 9)
            unapplied = Cobol.truncate(unapplied + work1, digits: 10)
            current = 0
        }
        l5.newBal = current - unapplied
        st.purch.setInt("purch-current", current); st.purch.setInt("purch-unapplied", unapplied)
        st.purch.setInt("purch-last-pay", st.oi.int("oi-date"))
        let type = st.oi.int("oi-type")
        if type == 5 {
            st.tApprop = Cobol.truncate(st.tApprop + approp, digits: 9)
            st.tPaid = Cobol.truncate(st.tPaid + paid, digits: 9)
            PLB.addSys4(s, "pl-payments", paid)
            st.tDeduct = Cobol.truncate(st.tDeduct + deductAmt, digits: 9)
        } else if type == 6 {
            st.jApprop = Cobol.truncate(st.jApprop + approp, digits: 9)
            st.jPaid = Cobol.truncate(st.jPaid + paid, digits: 9)
            st.jDeduct = Cobol.truncate(st.jDeduct + deductAmt, digits: 9)
        }
        st.oi.setInt("oi-paid", approp)
        pf.rewrite(st.purch)
        if st.gl { try blWrite(st) }
        st.oi.setInt("oi-status", 1)
        oiFile.rewrite(st.oi)
        if type == 6 { l5.type = s.l10n.raw("report.pl100.cr_journal") }
        else if type == 5 { l5.type = s.l10n.raw("report.pl100.payment") }
        st.prt.after(l5.detail(), 1)
        st.lineCnt = PLB.addChar(st.lineCnt, 1)
        if st.lineCnt > Int(s.sys.int("page-lines")) { headings(st) }
    }

    static func headings(_ st: State) {
        let s = st.s
        st.j = (st.j + 1) % 100
        let line1 = Cobol.x(progName, 56) + Cobol.x(s.l10n.raw("report.pl100.title"), 68)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.j), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 56) + Cobol.x("", 66) + Cobol.x(st.l2Date, 10)
        if st.j != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line2, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line2, 1)
        }
        st.prt.after(Cobol.x(s.l10n.raw("report.pl100.line4a"), 67) + Cobol.x(s.l10n.raw("report.pl100.line4b"), 65), 1)
        st.prt.after("", 1)
        st.lineCnt = 5
    }

    /// compute-purch-pay: 直前に読んだ purch-record (作業域) の支払実績を更新する
    static func computePurchPay(_ st: State) {
        let cleared = st.oi.int("oi-date-cleared")
        if cleared == 0 { return }
        let workA = PLB.wrap32(cleared - st.oi.int("oi-date"))
        var workB: Int64 = 0
        var activety = st.purch.int("purch-pay-activety")
        if activety != 0 { workB = PLB.wrap32(activety * st.purch.int("purch-pay-average")) }
        workB = PLB.wrap32(workA + workB)
        activety = PLB.wrap32(activety + 1)
        st.purch.setInt("purch-pay-activety", activety)
        if activety != 0 { st.purch.setInt("purch-pay-average", workB / activety) }
        if workA > st.purch.int("purch-pay-worst") { st.purch.setInt("purch-pay-worst", workA) }
    }

    static func analiseDeductions(_ st: State) {
        let vf = PLB.valueFile(st.s)
        vf.open()
        defer { vf.close() }
        for code in ["Pzb", "Pz "] {
            guard var v = vf.read(key: code) else { return }
            for (f, d) in [("va-t-this", st.nDeduct), ("va-t-year", st.nDeduct)] {
                v.setInt(f, Cobol.truncate(abs(v.int(f) - d), digits: 5))
            }
            for f in ["va-v-this", "va-v-year"] {
                v.setInt(f, Cobol.truncate(v.int(f) - st.tDeduct, digits: 10))
            }
            vf.rewrite(v)
        }
    }

    static func blOpen(_ st: State) {
        let s = st.s
        if st.batchFile.open() != "00" { st.batchFile.openOutput() }
        st.batch.setInt("batch-nos", s.sys.int("bl-next-batch"))
        st.batch.setInt("ledger", 2)
        s.sys.setInt("bl-next-batch", s.sys.int("bl-next-batch") + 1)
        st.batch.setInt("batch-status", 0); st.batch.setInt("cleared-status", 0)
        st.batch.setInt("bcycle", Cobol.truncate(s.sys.int("scycle"), digits: 2))
        st.batch.setInt("entered", s.sys.int("run-date"))
        st.batch.set("description", s.l10n.raw("report.pl100.batch_desc"))
        for f in ["bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"] {
            st.batch.setInt(f, 0)
        }
        st.batch.set("convention", "DR")
        st.batch.set("batch-def-code", "PL")
        st.batch.set("batch-def-vat", "I")
        st.batch.setInt("batch-start", Cobol.truncate(s.sys.int("postings") + 1, digits: 5))
        // irs-post-file は open extend、posting-file は open i-o (無ければ output): いずれも書込時に作られる
        st.rrn = Int(st.batch.int("batch-start"))
    }

    static func blWrite(_ st: State) throws {
        let s = st.s
        let u = Array(Cobol.x(st.uDate, 10))
        st.post.set("post-date", String(u[0..<6]) + String(u[8..<10]))
        let items = Cobol.truncate(st.batch.int("items") + 1, digits: 2, signed: false)
        st.batch.setInt("items", items)
        st.post.setInt("post-number", items)
        let amount = st.oi.int("oi-paid")
        st.post.setInt("post-amount", amount)
        st.post.setInt("batch", st.batch.int("batch-nos"))
        let m = Pic.edit("z(7)9", value: st.oi.int("oi-invoice"), scale: 0)
        let legend = m.trimmingCharacters(in: .whitespaces) + " : " + Cobol.x(st.purch.str("purch-name"), 30)
        st.post.set("post-legend", String(legend.prefix(32)))
        st.post.setInt("post-dr", Cobol.truncate(s.sys.int("p-creditors"), digits: 6, signed: false))
        st.post.setInt("post-cr", Cobol.truncate(s.sys.int("bl-pay-ac"), digits: 6, signed: false))
        for f in ["dr-pc", "cr-pc", "vat-ac", "vat-pc", "vat-amount"] { st.post.setInt(f, 0) }
        st.batch.setInt("input-gross", Cobol.truncate(abs(st.batch.int("input-gross") + st.post.int("post-amount")), digits: 11))
        st.batch.setInt("actual-gross", Cobol.truncate(abs(st.batch.int("actual-gross") + st.post.int("post-amount")), digits: 11))
        st.post.set("post-code", "PL")
        st.post.set("post-vat-side", "DR")
        if st.irsUsed {
            // irs-posting-record (84): 金額は s9(7)v99 sign leading
            func signLeading(_ v: Int64) -> [UInt8] {
                var d = Array(Cobol.z(abs(v) % 1_000_000_000, 9).utf8)
                if v < 0 { d[0] += 0x40 }
                return d
            }
            var r: [UInt8] = st.post.raw("batch") + st.post.raw("post-number") + st.post.raw("post-code") + st.post.raw("post-date")
            r += Array(Cobol.z(st.post.int("post-dr") % 100_000, 5).utf8)
            r += Array(Cobol.z(st.post.int("post-cr") % 100_000, 5).utf8)
            r += signLeading(st.post.int("post-amount"))
            r += st.post.raw("post-legend") + Array("31".utf8) + st.post.raw("post-vat-side")
            r += signLeading(st.post.int("vat-amount"))
            s.store.appendRaw(s.irsDir + "postings2irs.dat", r)
        } else {
            st.postFile.write(st.rrn, st.post.bytes)
            st.rrn += 1
        }
        if items == 99 {
            try blClose(st)
            blOpen(st)
        }
    }

    static func blClose(_ st: State) throws {
        let s = st.s, c = s.console
        if st.batchFile.write(st.batch) != "00" {
            c.display(s.t("pl100.pl132"), at: 2301)
            c.display(st.batchFile.status, at: 2333)
            c.display(PLB.statusMessage(s, st.batchFile.status), at: 2336)
            c.display(s.t("plb.pl002"), at: 2401, color: 2)
            _ = try c.accept(at: 2430, size: 1)
        }
        if !st.irsUsed { s.sys.setInt("postings", Int64(st.rrn)) }
        st.batchFile.close()
    }
}
