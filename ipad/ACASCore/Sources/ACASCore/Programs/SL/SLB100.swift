import Foundation

/// sales/sl100.cbl: Cash Posting (入金転記)
enum SLB100 {
    static let progName = "SL100 (3.01.12)"

    final class State {
        var j = 0
        var lineCnt = 0
        var uDate = Cobol.x("", 10)
        var batch = Record(SLB.batchLayout)
        var posting = Record(SLB.postingLayout)
        var rrn = 0
        var batchFile: IndexedFile?
        var irsOpen = false
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State()
        let prt = SLB.Printer(s)
        let wsDate = SLB.wsDate(s)
        let l2Date = wsDate

        if s.sys.int("s-flag-p") != 2 {
            try SLB.maps99(s, 11)
            try SLB.maps99(s, 15)
            return
        }
        // menu-return
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("sl100.title"), at: 136, color: 2)
        c.display(SLB.wsDate(s), at: 171, color: 2)
        while true {
            c.display(s.t("sl100.ok_to_post"), at: 1212, color: 2)
            let r = try c.accept(at: 1256, size: 3, initial: "   ", options: [.update], color: 6).uppercased()
            let wx = Cobol.x(r, 3)
            if wx == "NO " { return }
            if wx == "YES" { break }
        }
        let gl = s.sys.int("level-1") == 1
        let irsUsed = s.sys.str("irs-instead") == "Y"
        let oi = SLB.oi3File(s)
        let salesFile = SLB.salesFile(s)
        _ = oi.open()
        _ = salesFile.open()
        var sales = Record(SLB.salesLayout)
        var sys4 = SLB.sys4(s)
        if gl { blOpen(s, st, irsUsed) }
        prt.openOutput()

        func headings() {
            st.j += 1
            let line1 = Cobol.x(progName, 56) + Cobol.x(s.t("report.sl100.title"), 68) + Cobol.x(s.t("report.sl100.page"), 5) + SLB.zz(Int64(st.j), 3)
            let line2 = Cobol.x(s.sys.str("usera"), 56) + Cobol.x("", 66) + l2Date
            if st.j != 1 {
                prt.afterPage(line1)
                prt.after(line2, 1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
                prt.before(line2, 1)
            }
            prt.after(Cobol.x(s.t("report.sl100.head_a"), 67) + Cobol.x(s.t("report.sl100.head_b"), 65), 1)
            prt.after("", 1)
            st.lineCnt = 5
        }
        headings()
        c.display(s.t("sl100.posting_wait"), at: 1601, color: 2)

        var tPaid: Int64 = 0, tApprop: Int64 = 0, tDeduct: Int64 = 0
        var jPaid: Int64 = 0, jApprop: Int64 = 0, jDeduct: Int64 = 0
        var nDeduct: Int64 = 0
        func m9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9) }
        func m10(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 10) }

        while var o = oi.readNext() {
            let type = o.int("oi-type")
            if type != 2 && type != 5 && type != 6 { continue }
            if type == 2 && o.int("oi-b-nos") != 0 && o.int("oi-b-item") != 0 {
                // compute-sales-pay (sales-record は直前に読んだ得意先のまま: レガシーどおり)
                if o.int("oi-date-cleared") != 0 {
                    let workA = o.int("oi-date-cleared") - o.int("oi-date")
                    var workB: Int64 = 0
                    if sales.int("sales-pay-activety") != 0 {
                        workB = sales.int("sales-pay-activety") * sales.int("sales-pay-average")
                    }
                    workB += workA
                    sales.setInt("sales-pay-activety", sales.int("sales-pay-activety") + 1)
                    sales.setInt("sales-pay-average", workB / sales.int("sales-pay-activety"))
                    if workA > sales.int("sales-pay-worst") { sales.setInt("sales-pay-worst", workA) }
                }
                o.setInt("oi-b-nos", 0); o.setInt("oi-b-item", 0); o.setInt("oi-cr", 0)
                _ = oi.rewrite(o)
                continue
            }
            if o.int("oi-status") == 1 || type == 2 { continue }
            if o.int("oi-b-nos") == 0 && o.int("oi-b-item") == 0 { continue }

            // cust-update
            let cust = o.str("oi-customer")
            var l5Name: String
            if let r = salesFile.read(key: o.raw("oi-customer")) {
                sales = r
                l5Name = Cobol.x(sales.str("sales-name"), 25)
            } else {
                sales.setRaw("sales-key", o.raw("oi-customer"))
                l5Name = Cobol.x(s.t("report.sl100.cust_unknown"), 25)
            }
            st.uDate = SLB.convBin(s, o.int("oi-date")).uDate
            let approp = o.int("oi-net"), paid = o.int("oi-paid"), deductAmt = o.int("oi-deduct-amt")
            if deductAmt != 0 { nDeduct += 1 }
            let oldBal = sales.int("sales-current") - sales.int("sales-unapplied")
            sales.setInt("sales-current", m10(sales.int("sales-current") - approp))
            sales.setInt("sales-current", m10(sales.int("sales-current") - deductAmt))
            if paid != approp {
                let work1 = m9(paid - approp)
                sales.setInt("sales-unapplied", m10(sales.int("sales-unapplied") + work1))
            }
            if sales.int("sales-current") < 0 {
                let work1 = m9(-sales.int("sales-current"))
                sales.setInt("sales-unapplied", m10(sales.int("sales-unapplied") + work1))
                sales.setInt("sales-current", 0)
            }
            let newBal = sales.int("sales-current") - sales.int("sales-unapplied")
            sales.setInt("sales-last-pay", o.int("oi-date"))
            if type == 5 {
                tApprop = m9(tApprop + approp)
                tPaid = m9(tPaid + paid)
                sys4.setInt("sl-payments", m10(sys4.int("sl-payments") + paid))
                tDeduct = m9(tDeduct + deductAmt)
            } else if type == 6 {
                jApprop = m9(jApprop + approp)
                jPaid = m9(jPaid + paid)
                jDeduct = m9(jDeduct + deductAmt)
            }
            o.setInt("oi-paid", approp)
            _ = salesFile.rewrite(sales)
            if gl { try blWrite(s, st, o, sales, irsUsed) }
            o.setInt("oi-status", 1)
            _ = oi.rewrite(o)
            let l5Type = Cobol.x(s.t(type == 6 ? "report.sl100.cr_journal" : "report.sl100.payment"), 11)
            let line5 = SLB.zz(o.int("oi-b-nos"), 5) + "/" + Cobol.z(o.int("oi-b-item"), 3) + " "
                + Cobol.x(st.uDate, 11) + Cobol.x(cust, 8) + l5Name + "    " + l5Type
                + SLB.z99cr(oldBal, 6) + "   " + SLB.z99cr(newBal, 6) + "  "
                + SLB.z99(paid, 6) + " " + "  " + SLB.z99(deductAmt, 6) + " " + "    " + SLB.z99(approp, 6) + "  "
            prt.after(line5, 1)
            st.lineCnt += 1
            if st.lineCnt > Int(s.sys.int("page-lines")) { headings() }
        }
        // main-end
        salesFile.close(); oi.close()
        func total(_ key: String, _ approp: Int64, _ deduct: Int64, _ paid: Int64) -> String {
            Cobol.x("", 29) + Cobol.x(s.t(key), 25) + Cobol.x("", 42)
                + SLB.z99(paid, 6) + " " + "  " + SLB.z99(deduct, 6) + " " + "    " + SLB.z99(approp, 6) + "  "
        }
        prt.after(total("report.sl100.payment_totals", tApprop, tDeduct, tPaid), 3)
        prt.after(total("report.sl100.journal_totals", jApprop, jDeduct, jPaid), 2)
        prt.spool()

        tDeduct = m9(tDeduct + jDeduct)
        if tDeduct != 0 {
            let vf = SLB.valueFile(s)
            _ = vf.open()
            for code in ["Szd", "Sz "] {
                guard var v = vf.read(key: code) else { break }
                v.setInt("va-t-this", abs(v.int("va-t-this") - nDeduct) % 100000)
                v.setInt("va-t-year", abs(v.int("va-t-year") - nDeduct) % 100000)
                v.setInt("va-v-this", m10(v.int("va-v-this") - tDeduct))
                v.setInt("va-v-year", m10(v.int("va-v-year") - tDeduct))
                _ = vf.rewrite(v)
            }
            vf.close()
        }
        if gl { try blClose(s, st, irsUsed) }
        SLB.setSys4(s, sys4)
        s.sys["oi-3-flag"] = "Y"
        s.sys.setInt("s-flag-p", 0)
    }

    static func blOpen(_ s: Session, _ st: State, _ irsUsed: Bool) {
        let bf = SLB.batchFile(s)
        _ = bf.open()
        st.batchFile = bf
        var b = st.batch
        b.setInt("batch-nos", Cobol.truncate(s.sys.int("next-batch"), digits: 5, signed: false))
        b.setInt("ledger", 3)
        s.sys.setInt("next-batch", s.sys.int("next-batch") + 1)
        b.setInt("batch-status", 0); b.setInt("cleared-status", 0)
        b.setInt("bcycle", s.sys.int("scycle"))
        b.setInt("entered", s.sys.int("run-date"))
        b["description"] = "Sales-Ledger Payments"
        for f in ["bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"] {
            b.setInt(f, 0)
        }
        b["convention"] = "CR"
        b["batch-def-code"] = "SL"
        b["batch-def-vat"] = "O"
        b.setInt("batch-start", Cobol.truncate(s.sys.int("postings") + 1, digits: 5, signed: false))
        st.batch = b
        if irsUsed {
            let p = s.irsDir + "postings2irs.dat"
            if !s.store.exists(p) { s.store.writeRaw(p, []) }
            st.irsOpen = true
        } else {
            let p = s.ledgers + "posting.dat"
            if !s.store.exists(p) { s.store.writeRaw(p, []) }
        }
        st.rrn = Int(b.int("batch-start"))
    }

    static func blWrite(_ s: Session, _ st: State, _ o: Record, _ sales: Record, _ irsUsed: Bool) throws {
        var p = st.posting
        let u = Array(Cobol.x(st.uDate, 10))
        p["post-date"] = String(u[0..<6]) + String(u[8..<10])
        st.batch.setInt("items", (st.batch.int("items") + 1) % 100)
        p.setInt("post-number", st.batch.int("items"))
        p.setInt("post-amount", o.int("oi-paid"))
        let legend = Cobol.z(o.int("oi-b-nos"), 5) + "/" + Cobol.z(o.int("oi-b-item"), 3) + "  :  " + Cobol.x(sales.str("sales-name"), 30)
        p.setInt("batch", st.batch.int("batch-nos"))
        p["post-legend"] = Cobol.x(legend, 32)
        p.setInt("post-cr", Cobol.truncate(s.sys.int("s-debtors"), digits: 6, signed: false))
        p.setInt("post-dr", Cobol.truncate(s.sys.int("sl-pay-ac"), digits: 6, signed: false))
        for f in ["dr-pc", "cr-pc", "vat-ac", "vat-pc", "vat-amount"] { p.setInt(f, 0) }
        st.batch.setInt("input-gross", Cobol.truncate(st.batch.int("input-gross") + abs(p.int("post-amount")), digits: 11, signed: false))
        st.batch.setInt("actual-gross", Cobol.truncate(st.batch.int("actual-gross") + abs(p.int("post-amount")), digits: 11, signed: false))
        p["post-code"] = "SL"
        p["post-vat-side"] = "CR"
        st.posting = p
        if irsUsed {
            var b: [UInt8] = []
            b += Array(Cobol.z(p.int("batch"), 5).utf8) + Array(Cobol.z(p.int("post-number"), 5).utf8)
            b += p.raw("post-code") + p.raw("post-date")
            b += Array(Cobol.z(p.int("post-dr") % 100000, 5).utf8) + Array(Cobol.z(p.int("post-cr") % 100000, 5).utf8)
            b += SLB.signLeading(p.int("post-amount"), digits: 9)
            b += p.raw("post-legend") + Array("32".utf8) + p.raw("post-vat-side")
            b += SLB.signLeading(p.int("vat-amount"), digits: 9)
            s.store.appendRaw(s.irsDir + "postings2irs.dat", b)
        } else {
            RelativeFile(s.store, path: s.ledgers + "posting.dat", recordSize: 96).write(st.rrn, p.bytes)
            st.rrn += 1
        }
        if st.batch.int("items") == 99 {
            try blClose(s, st, irsUsed)
            blOpen(s, st, irsUsed)
        }
    }

    static func blClose(_ s: Session, _ st: State, _ irsUsed: Bool) throws {
        let c = s.console
        let status = st.batchFile?.write(st.batch) ?? "48"
        if status != "00" {
            c.display(s.t("sl100.sl132"), at: 2301)
            c.display(status, at: 2333)
            c.display(SLB.fsMsg(s, status), at: 2336)
            c.display(s.t("sl100.sl002"), at: 2401, color: 2)
            _ = try c.accept(at: 2430, size: 1)
        }
        if !irsUsed { s.sys.setInt("postings", Int64(st.rrn)) }
        st.batchFile?.close()
    }
}
