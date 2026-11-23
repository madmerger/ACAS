import Foundation

/// purchase/pl060.cbl: 仕入転記 (Invoice Posting Report)
final class PLA060 {
    static let progName = "PL060 (3.01.07)"
    static func run(_ s: Session) throws { try PLA060(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, oi5: IndexedFile, batchFile: IndexedFile
    let oi4: PLA.SeqFile
    let posting: RelativeFile
    let p: PLA.Printer
    var purch = PLA.fdArea(PLA.purchLayout)
    var batch = PLA.fdArea(PLA.batchLayout)
    var post = PLA.fdArea(PLA.postLayout)
    var oi = Record(PLA.oiLayout)
    var si = Record(PLA.oiLayout)
    var wsReply = " "
    var wsError = 0
    var work1: Int64 = 0, workA: Int64 = 0, workB: Int64 = 0
    var workNet: Int64 = 0, workVat: Int64 = 0, workGoods: Int64 = 0
    var totalNet = [Int64](repeating: 0, count: 4), totalVat = [Int64](repeating: 0, count: 4)
    var j = 0, lineCnt = 0, rrn = 0
    var uDate = ""
    var l5Type = Cobol.x("", 9)
    var pageLines: Int { Int(s.sys.int("page-lines")) }

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); oi5 = PLA.openItem5(s); batchFile = PLA.batchFile(s)
        oi4 = PLA.SeqFile(s, path: PLA.openItem4Path(s), recSize: 109)
        posting = PLA.postingFile(s)
        p = PLA.Printer(s)
    }

    func t9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9) }
    func oiSum(_ r: Record) -> Int64 { r.int("oi-net") + r.int("oi-carriage") + r.int("oi-vat") + r.int("oi-c-vat") }
    func oi5Key(_ supplier: String, _ invoice: Int64) -> [UInt8] {
        var r = Record(PLA.oiLayout)
        r.set("oi-supplier", supplier); r.setInt("oi-invoice", invoice)
        return Array(r.bytes[0..<11])
    }

    func main() throws {
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA060.progName, at: 101, color: 2)
        c.display(s.t("pl060.title"), at: 131, color: 2)
        c.display(PLA.toDayDisplay(s), at: 171, color: 2)
        while true {
            c.display(s.t("pl060.ok_to_post"), at: 812, color: 2)
            let wx = try c.accept(at: 858, size: 3, initial: "   ", options: [.update], color: 6).uppercased()
            if wx == "NO " { return }
            if wx == "YES" { break }
        }
        c.display(" ", at: 801, eraseEOL: true)
        s.sys.setInt("p-flag-i", 2)
        s.sys.setInt("p-flag-a", 1)
        PLA.setFileStatus(s, 28, 0)
        s.sys.set("oi-5-flag", "Y")
        if PLA.fileStatus(s, 29) == 0 {
            oi5.openOutput()
            oi5.close()
            PLA.setFileStatus(s, 29, 1)
        }
        if PLA.gl(s) { blOpen() }
        _ = purchase.open()
        p.openOutput()
        c.display(" ", at: 1201, eraseEOS: true)
        c.display(s.t("pl060.posting_wait"), at: 1201, color: 2)
        c.display(s.t("pl060.phase_1"), at: 1401, color: 2)
        j = 0
        headings()
        _ = oi4.openInput()
        _ = oi5.open()
        while let rec = oi4.read() {
            oi = Record(PLA.oiLayout, bytes: rec)
            purch.set("purch-key", oi.str("oi-supplier"))
            let l5Cust = Cobol.x(oi.str("oi-supplier"), 9)
            wsReply = " "
            var l5Name: String
            if let pr = purchase.read(key: oi.str("oi-supplier")) {
                purch = pr
                l5Name = Cobol.x(purch.str("purch-name"), 25)
            } else {
                wsReply = "X"
                wsError = 1
                PLA.initialize(&purch)
                l5Name = Cobol.x(s.l10n.raw("pl060.supplier_unknown"), 25)
                purch.set("purch-name", s.l10n.raw("pl060.supplier_unknown"))
                purch.set("purch-key", oi.str("oi-supplier"))
            }
            uDate = Maps04.toDate(Int(oi.int("oi-date")))
            let l5Date = Cobol.x(PLA.dateDisplay(s, oi.int("oi-date")), 11)
            let type = oi.int("oi-type")
            let a = Int(type)
            if type == 2 { l5Type = Cobol.x(s.l10n.raw("pl060.type_invoice"), 9) }
            else if type == 3 { l5Type = Cobol.x(s.l10n.raw("pl060.type_cr_note"), 9) }
            else if type == 1 { l5Type = Cobol.x(s.l10n.raw("pl060.type_receipt"), 9) }
            workVat = t9(oi.int("oi-vat") + oi.int("oi-c-vat"))
            workGoods = oi.int("oi-net")
            workNet = t9(oi.int("oi-net") + oi.int("oi-carriage"))
            if (1...3).contains(a) {
                totalVat[a] = t9(totalVat[a] + workVat)
                totalNet[a] = t9(totalNet[a] + workNet)
            }
            work1 = t9(workNet + workVat)
            let l5Gross = PLA.cr("z(6)9.99cr", work1, int: 7)
            if PLA.gl(s) { try blWrite() }
            let oldBal = purch.int("purch-current") - purch.int("purch-unapplied")
            if type == 1 || type == 2 { purchComp() }
            let cq = Int(s.sys.int("current-quarter"))
            func addTurnover() {
                guard (1...4).contains(cq) else { return }
                purch.setInt("turnover-q\(cq)", Cobol.truncate(purch.int("turnover-q\(cq)") + workGoods, digits: 10))
            }
            func addCurrent() {
                purch.setInt("purch-current", Cobol.truncate(purch.int("purch-current") + workVat + workNet, digits: 10))
            }
            if type == 1 {
                addTurnover()
                purch.setInt("purch-last-inv", oi.int("oi-date")); purch.setInt("purch-last-pay", oi.int("oi-date"))
            }
            if type == 2 {
                addTurnover(); addCurrent()
                purch.setInt("purch-last-inv", oi.int("oi-date"))
            }
            if type == 3 {
                addTurnover(); addCurrent()
                purch.setInt("purch-last-pay", oi.int("oi-date"))
                crNotes()
                creditComp()
            }
            if purch.int("purch-status") == 0 { purch.setInt("purch-status", 1) }
            if purch.int("purch-current") < 0 {
                purch.setInt("purch-current", -purch.int("purch-current"))
                purch.setInt("purch-unapplied", Cobol.truncate(purch.int("purch-unapplied") + purch.int("purch-current"), digits: 10))
                purch.setInt("purch-current", 0)
            }
            let newBal = purch.int("purch-current") - purch.int("purch-unapplied")
            if wsReply == "X" {
                purch.setInt("purch-status", 1)
                purchase.write(purch)
            } else {
                purchase.rewrite(purch)
            }
            var l5Nos = Pic.edit("z(7)9", value: abs(oi.int("oi-invoice")) % 100_000_000, scale: 0) + " "
            if oi5.write(oi) != "00" {
                c.display(s.t("pl060.pl130"), at: 1601)
                c.display(oi.str("oi-supplier"), at: 1701)
                l5Nos = Pic.edit("z(7)9", value: abs(oi.int("oi-invoice")) % 100_000_000, scale: 0) + " "
                c.display(l5Nos, at: 1801)
                c.display(s.t("pl060.fs_reply"), at: 1901)
                c.display(oi5.status, at: 1912)
                c.display(PLA.fileStatMsg(s, oi5.status), at: 1915)
                c.display(s.t("pl060.pl133"), at: 2401, color: 4)
                c.display(s.t("pl060.pl002"), at: 2412)
                wsReply = try c.accept(at: 2450, size: 1)
            }
            let line5 = l5Nos + l5Date + l5Cust + l5Name + "  " + l5Type
                + PLA.cr("z(6)9.99cr", oldBal, int: 7) + PLA.cr("z(6)9.99cr", newBal, int: 7) + Cobol.x("", 7)
                + PLA.cr("z(6)9.99cr", workNet, int: 7) + PLA.cr("z(6)9.99cr", workVat, int: 7) + l5Gross
            p.write(line5, after: 1)
            lineCnt += 1
            if lineCnt > pageLines { headings() }
        }
        // main-end
        purchase.close(); oi4.close(); oi5.close()
        if lineCnt > pageLines - 7 { headings() }
        for (a, n) in [(1, 3), (2, 2), (3, 2)] {
            let lit = s.l10n.raw(a == 1 ? "pl060.lit_receipts" : (a == 2 ? "pl060.lit_invoices" : "pl060.lit_credit_notes"))
            p.write(Cobol.x("", 11) + Cobol.x(s.t("pl060.total_posted"), 14) + Cobol.x(Cobol.x(lit, 17), 18)
                + PLA.cr("z(7)9.99cr", totalNet[a], int: 8) + PLA.cr("z(7)9.99cr", totalVat[a], int: 8)
                + PLA.cr("z(7)9.99cr", totalNet[a] + totalVat[a], int: 8), after: n)
        }
        if PLA.gl(s) { try blClose() }
        _ = oi5.open()
        workB = 0
        c.display("2", at: 1407, color: 2)
        oi5.startFirst()
        while let rec = oi5.readNext() {
            oi = rec
            if oi.int("oi-status") == 1 { continue }
            if oi.int("oi-type") == 3 { try crSwop() }
        }
        oi4.openOutput()
        oi4.close(); oi5.close()
        if lineCnt > pageLines - 6 && PLA.fileStatus(s, 28) == 1 { newHeading() }
        if PLA.fileStatus(s, 28) == 1 {
            p.write(Cobol.x("", 24) + Cobol.x(s.t("pl060.unapplied_cf"), 32) + PLA.bwz("z(7)9.99", workB, int: 8, scale: 2), after: 3)
        }
        PLA.setSys4(s, "pl-cn-unappl-this-month", PLA.sys4(s, "pl-cn-unappl-this-month") + workB)
        if wsError == 1 { p.write(s.t("pl060.pl134"), after: 3) }
        p.close()
        p.spool()
        PLA.setFileStatus(s, 28, 0)
    }

    // MARK: cr-swop section

    func crSwop() throws {
        work1 = t9(oiSum(oi))
        work1 = t9(work1 + oi.int("oi-paid"))
        if work1 == 0 {
            c.display(s.t("pl060.pl131"), at: 2401, color: 4)
            wsReply = try c.accept(at: 2434, size: 1)
        }
        if PLA.fileStatus(s, 28) == 0 { newHeading() }
        oi.setInt("oi-status", 1)
        let line7 = Cobol.x(oi.str("oi-supplier"), 12)
            + (oi.int("oi-invoice") == 0 ? Cobol.x("", 10) : Pic.edit("z(7)9", value: abs(oi.int("oi-invoice")) % 100_000_000, scale: 0) + "  ")
            + "    " + PLA.bwz("z(7)9.99", work1, int: 8, scale: 2)
            + "    " + PLA.bwz("z(7)9.99", oi.int("oi-paid"), int: 8, scale: 2)
            + "    " + (oi.int("oi-cr") == 0 ? Cobol.x("", 10) : Pic.edit("z(7)9", value: abs(oi.int("oi-cr")) % 100_000_000, scale: 0) + "  ")
            + "    " + Cobol.x(s.l10n.raw("pl060.type_cr_note"), 12)
        p.write(line7, after: 1)
        lineCnt += 1
        if lineCnt > pageLines { newHeading() }
        workB = t9(workB + work1)
        work1 = -work1
        oi.setInt("oi-paid", t9(oi.int("oi-paid") + work1))
        oi5.rewrite(oi)
    }

    // MARK: new-heading / headings section

    func pageHead(extra: Bool) {
        j += 1
        let line1 = Cobol.x(PLA060.progName, 54) + Cobol.x(s.t("pl060.rep_title"), 70) + s.t("pl060.rep_page") + Pic.edit("zz9", value: Int64(j % 1000), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 54) + Cobol.x("", 68) + Cobol.x(s.toDay, 10)
        let line1a = Cobol.x("", 56) + s.t("pl060.rep_unapplied_credits")
        if j != 1 {
            p.writePage(line1)
            p.write(line2, after: 1)
            if extra { p.write(line1a, after: 1) }
            p.write("", after: 1)
        } else {
            p.writeBefore(line1, before: 1)
            p.writeBefore(line2, before: 1)
            if extra { p.writeBefore(line1a, before: 1) }
        }
    }

    func newHeading() {
        if PLA.fileStatus(s, 28) == 0 { PLA.setFileStatus(s, 28, 1) }
        pageHead(extra: true)
        p.write(s.t("pl060.rep_line4a"), after: 1)
        p.write("", after: 1)
        lineCnt = 6
    }

    func headings() {
        pageHead(extra: false)
        p.write(Cobol.x(s.t("pl060.rep_line4_1"), 64) + Cobol.x(s.t("pl060.rep_line4_2"), 68), after: 1)
        p.write("", after: 1)
        lineCnt = 5
    }

    // MARK: purch-comp / credit-comp section

    /// work-2 は s9(14) の整数 (小数部は切り捨て)
    func purchComp() {
        var work2: Int64 = 0
        if purch.int("purch-activety") != 0 && purch.int("purch-average") != 0 {
            work2 = purch.int("purch-activety") * purch.int("purch-average")
        }
        purch.setInt("purch-activety", purch.int("purch-activety") + 1)
        work2 = (work2 * 100 + workGoods) / 100
        if purch.int("purch-activety") != 0 { purch.setInt("purch-average", work2 / purch.int("purch-activety")) }
    }

    func creditComp() {
        var work2: Int64 = 0
        if purch.int("purch-activety") != 0 && purch.int("purch-average") != 0 {
            work2 = purch.int("purch-activety") * purch.int("purch-average")
        }
        if work2 != 0 {
            work2 = (work2 * 100 + workGoods) / 100
            purch.setInt("purch-average", work2 / purch.int("purch-activety"))
        }
    }

    // MARK: cr-notes section

    func crNotes() {
        si = oi
        var firstPass = true
        defer { oi = si }
        guard oi5.start(notLessThan: oi5Key(oi.str("oi-supplier"), oi.int("oi-cr"))) else { return }
        workB = 0
        if work1 < 0 { work1 = -work1 }
        work1 = t9(work1 - si.int("oi-paid"))
        while true {
            var ended = false
            while true {
                guard let rec = oi5.readNext() else { ended = true; break }
                oi = rec
                if oi.int("oi-type") != 2 { continue }
                if oi.str("oi-supplier") != si.str("oi-supplier") { ended = true; break }
                if oi.int("oi-status") == 1 { continue }
                if si.int("oi-cr") == oi.int("oi-invoice") || !firstPass { apportion() }
                if work1 != 0 { continue }
                break
            }
            _ = ended
            // end-loop
            if work1 == 0 || !firstPass { return }
            firstPass = false
            guard oi5.start(notLessThan: oi5Key(si.str("oi-supplier"), 0)) else { return }
        }
    }

    // MARK: apportion section

    func apportion() {
        workA = t9(oiSum(oi))
        workA = t9(workA - oi.int("oi-paid"))
        if workA == 0 {
            oi.setInt("oi-status", 1)
            oi5.rewrite(oi)
            return
        }
        if workA <= 0 { return }
        func pay(_ v: Int64) {
            oi.setInt("oi-paid", t9(oi.int("oi-paid") + v))
            si.setInt("oi-paid", t9(si.int("oi-paid") + v))
            oi.setInt("oi-p-c", t9(oi.int("oi-p-c") + v))
        }
        if workA == work1 {
            pay(work1)
            work1 = 0
            oi.setInt("oi-status", 1); si.setInt("oi-status", 1)
        } else if workA > work1 {
            pay(work1)
            work1 = 0
            si.setInt("oi-status", 1)
        } else {
            pay(workA)
            work1 = t9(work1 - workA)
            oi.setInt("oi-status", 1)
        }
        if work1 == 0 { si.setInt("oi-status", 1) }
        oi5.rewrite(oi)
    }

    // MARK: BL-Open / bl-write / bl-close section

    func blOpen() {
        if batchFile.open() != "00" {
            batchFile.close()
            batchFile.openOutput()
        }
        batch.setInt("batch-nos", abs(s.sys.int("next-batch")) % 100_000)
        batch.setInt("ledger", 2)
        s.sys.setInt("next-batch", s.sys.int("next-batch") + 1)
        batch.setInt("batch-status", 0); batch.setInt("cleared-status", 0)
        batch.setInt("bcycle", abs(s.sys.int("scycle")) % 100)
        batch.setInt("entered", s.sys.int("run-date"))
        batch.set("description", s.l10n.raw("pl060.batch_description"))
        for f in ["bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"] { batch.setInt(f, 0) }
        batch.set("convention", "DR")
        batch.set("batch-def-code", "PL")
        batch.set("batch-def-vat", "I")
        batch.setInt("batch-start", abs(s.sys.int("postings") + 1) % 100_000)
        if PLA.irsUsed(s) {
            if s.store.readRaw(PLA.irsPostPath(s)) == nil { s.store.writeRaw(PLA.irsPostPath(s), []) }
        } else if !posting.exists {
            s.store.writeRaw(posting.path, [])
        }
        rrn = Int(batch.int("batch-start"))
    }

    func addUnsigned(_ f: String, _ v: Int64) { batch.setInt(f, abs(batch.int(f) + v) % 100_000_000_000) }

    func blWrite() throws {
        let u = Array(Cobol.x(uDate, 10))
        post.set("post-date", String(u[0..<6]) + String(u[8..<10]))
        post.setInt("batch", batch.int("batch-nos"))
        batch.setInt("items", (batch.int("items") + 1) % 100)
        post.setInt("post-number", batch.int("items"))
        post.setInt("post-amount", workNet)
        // post-legend は STRING で先頭から上書きされるだけ (残りは以前の内容)
        let m = Pic.edit("z(7)9", value: abs(oi.int("oi-invoice")) % 100_000_000, scale: 0).drop { $0 == " " }
        var legend = post.raw("post-legend")
        for (k, b) in SJIS.encode(String(m) + " : " + purch.str("purch-name"), size: 45).enumerated() where k < min(32, m.count + 3 + 30) { legend[k] = b }
        post.setRaw("post-legend", legend)
        post.setInt("post-cr", abs(s.sys.int("p-creditors")) % 1_000_000)
        post.setInt("post-dr", abs(s.sys.int("bl-purch-ac")) % 1_000_000)
        post.setInt("dr-pc", 0); post.setInt("cr-pc", 0); post.setInt("vat-pc", 0)
        post.setInt("vat-ac", abs(s.sys.int("vat-ac")) % 1_000_000)
        post.setInt("vat-amount", Cobol.truncate(oi.int("oi-vat") + oi.int("oi-c-vat"), digits: 10))
        post.set("post-vat-side", "DR")
        post.set("post-code", "PL")
        addUnsigned("input-gross", post.int("post-amount")); addUnsigned("actual-gross", post.int("post-amount"))
        addUnsigned("input-vat", post.int("vat-amount")); addUnsigned("actual-vat", post.int("vat-amount"))
        if PLA.irsUsed(s) {
            var r: [UInt8] = Array(post.bytes[0..<10]) + Array(post.raw("post-code")) + Array(post.raw("post-date"))
            r += Array(Cobol.z(post.int("post-dr") % 100_000, 5).utf8) + Array(Cobol.z(post.int("post-cr") % 100_000, 5).utf8)
            r += PLA.signLeading(post.int("post-amount"), digits: 9) + post.raw("post-legend")
            r += Array("31".utf8) + post.raw("post-vat-side") + PLA.signLeading(post.int("vat-amount"), digits: 9)
            s.store.appendRaw(PLA.irsPostPath(s), r)
        } else {
            posting.write(rrn, post.bytes)
            rrn += 1
        }
        if batch.int("items") == 99 {
            try blClose()
            blOpen()
        }
    }

    func blClose() throws {
        if batchFile.write(batch) != "00" {
            c.display(s.t("pl060.pl132"), at: 2301)
            c.display(batchFile.status, at: 2333)
            c.display(PLA.fileStatMsg(s, batchFile.status), at: 2336)
            c.display(s.t("pl060.pl002"), at: 2401, color: 2)
            wsReply = try c.accept(at: 2430, size: 1)
        }
        if !PLA.irsUsed(s) { s.sys.setInt("postings", Int64(rrn)) }
        batchFile.close()
    }
}
