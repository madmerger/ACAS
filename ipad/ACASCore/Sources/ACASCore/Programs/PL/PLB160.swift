import Foundation

/// pl160.cbl: 仕入先名順一覧 (Supplier Alphabetical Listing)
enum PLB160 {
    static let progName = "PL160 (3.01.05)"

    final class State {
        let s: Session
        let prt: PLBPrint
        let pf: IndexedFile
        let sel = PLB.Selection()
        var a = 0, lineCnt = 0
        var l1Date = ""
        var l3Report = PLB.Buf(70)
        init(_ s: Session) { self.s = s; prt = PLBPrint(s); pf = PLB.purchFile(s) }
    }

    static func run(_ s: Session) throws {
        let st = State(s)
        st.l1Date = PLB.wsDate(s)
        let purchOpen = st.pf.open() == "00"
        try reportSelection(st)
        reportHeadingSetup(st)
        try reportProduce(st, purchOpen: purchOpen)
        st.prt.close()
        st.pf.close()
        st.prt.spool()
        s.store.writeRaw(s.ledgers + PLB165.sortName, [])       // 空ファイルにする
    }

    /// display-03 の表示と入力
    static func screen(_ s: Session, progName: String, sel: PLB.Selection, display: Bool) throws {
        let c = s.console
        if display {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("plb.sel.supplier_file"), at: 134, color: 2)
            c.display(s.toDay, at: 171, color: 2)
            c.display(s.t("plb.sel.report_attributes"), at: 332, color: 2)
            c.display(s.t("plb.sel.supplier_number"), at: 809, color: 2)
            c.display("]", at: 834, color: 2)
            c.display(s.t("plb.sel.supplier_number_help"), at: 839, color: 2)
            c.display(s.t("plb.sel.status"), at: 1009, color: 2)
            c.display("]", at: 1029, color: 2)
            c.display(s.t("plb.sel.status_help"), at: 1039, color: 2)
            c.display(s.t("plb.sel.credit_period"), at: 1209, color: 2)
            c.display("]  [", at: 1230, color: 2)
            c.display("]", at: 1235, color: 2)
            c.display(s.t("plb.sel.days_help"), at: 1239, color: 2)
            c.display(s.t("plb.sel.credit_l"), at: 1343, color: 2)
            c.display(s.t("plb.sel.credit_g"), at: 1443, color: 2)
            c.display(s.t("plb.sel.credit_e"), at: 1543, color: 2)
            c.display(s.t("plb.sel.invoice_activity"), at: 1709, color: 2)
            c.display("] [", at: 1733, color: 2)
            c.display("]", at: 1737, color: 2)
            c.display(s.t("plb.sel.invoices_help"), at: 1739, color: 2)
            c.display(s.t("plb.sel.average_value"), at: 1909, color: 2)
            c.display("] [", at: 1933, color: 2)
            c.display("]", at: 1937, color: 2)
            c.display(s.t("plb.sel.value_help"), at: 1939, color: 2)
            c.display(s.t("plb.sel.overdue"), at: 2109, color: 2)
            c.display("] [", at: 2133, color: 2)
            c.display("]", at: 2137, color: 2)
            c.display(s.t("plb.sel.days_help"), at: 2139, color: 2)
            c.display(s.t("plb.sel.date_entered"), at: 2309, color: 2)
            c.display("] [", at: 2333, color: 2)
            c.display("]", at: 2337, color: 2)
            c.display(s.t("plb.sel.date_help"), at: 2339, color: 2)
        }
        let f = [
            ScreenField(line: 8, col: 28, size: 6, value: sel.custIn, color: 2),
            ScreenField(line: 10, col: 28, size: 1, value: sel.statusIn, color: 2),
            ScreenField(line: 12, col: 28, size: 2, kind: .numeric, pic: "99", value: Cobol.z(sel.creditIn, 2), color: 2),
            ScreenField(line: 12, col: 34, size: 1, value: sel.creditOp, color: 2),
            ScreenField(line: 17, col: 28, size: 5, kind: .numeric, pic: "9(5)", value: Cobol.z(sel.invoiceIn, 5), color: 2),
            ScreenField(line: 17, col: 36, size: 1, value: sel.invoiceOp, color: 2),
            ScreenField(line: 19, col: 28, size: 5, kind: .numeric, pic: "9(5)", value: Cobol.z(sel.averageIn, 5), color: 2),
            ScreenField(line: 19, col: 36, size: 1, value: sel.averageOp, color: 2),
            ScreenField(line: 21, col: 28, size: 5, kind: .numeric, pic: "9(5)", value: Cobol.z(sel.overdueIn, 5), color: 2),
            ScreenField(line: 21, col: 36, size: 1, value: sel.overdueOp, color: 2),
            ScreenField(line: 23, col: 23, size: 10, value: sel.enterDateIn, color: 2),
            ScreenField(line: 23, col: 36, size: 1, value: sel.enterDateOp, color: 2)
        ]
        if display { c.displayFields(f); return }
        try c.acceptScreen(f)
        sel.custIn = Cobol.x(f[0].value, 6); sel.statusIn = Cobol.x(f[1].value, 1)
        sel.creditIn = Cobol.moveNumeric(f[2].value, digits: 2, scale: 0); sel.creditOp = Cobol.x(f[3].value, 1)
        sel.invoiceIn = Cobol.moveNumeric(f[4].value, digits: 5, scale: 0); sel.invoiceOp = Cobol.x(f[5].value, 1)
        sel.averageIn = Cobol.moveNumeric(f[6].value, digits: 5, scale: 0); sel.averageOp = Cobol.x(f[7].value, 1)
        sel.overdueIn = Cobol.moveNumeric(f[8].value, digits: 5, scale: 0); sel.overdueOp = Cobol.x(f[9].value, 1)
        sel.enterDateIn = Cobol.x(f[10].value, 10); sel.enterDateOp = Cobol.x(f[11].value, 1)
    }

    /// report-selection section (pl160 / pl190 共通の検証)
    static func select(_ s: Session, progName: String, sel: PLB.Selection, invalidDate: String) throws {
        let c = s.console
        try screen(s, progName: progName, sel: sel, display: true)
        while true {
            try screen(s, progName: progName, sel: sel, display: false)
            sel.custIn = sel.custIn.uppercased()
            sel.customerIn = Cobol.x(sel.custIn, 7).replacingOccurrences(of: " ", with: "Z")
            sel.statusIn = sel.statusIn.uppercased()
            if !["L", "D", " "].contains(sel.statusIn) { continue }
            sel.creditOp = sel.creditOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.creditOp) { continue }
            sel.invoiceOp = sel.invoiceOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.invoiceOp) { continue }
            sel.averageOp = sel.averageOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.averageOp) { continue }
            sel.overdueOp = sel.overdueOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.overdueOp) { continue }
            sel.enterDateOp = sel.enterDateOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.enterDateOp) { continue }
            if sel.enterDateIn.allSatisfy({ $0 == " " }) { return }
            let bin = PLB.validateDate(s, sel.enterDateIn)
            if bin == 0 {
                c.display(invalidDate, at: 2368, color: 2)
                continue
            }
            c.display(" ", at: 2368, eraseEOL: true)
            sel.wsEnterDate = Int64(bin)
            return
        }
    }

    static func reportSelection(_ st: State) throws {
        try select(st.s, progName: progName, sel: st.sel, invalidDate: st.s.t("plb.pl005"))
    }

    /// report-heading-setup section: l3-report (70 桁) を組み立てる
    static func headingSetup(_ s: Session, _ sel: PLB.Selection) -> PLB.Buf {
        var r = PLB.Buf(70)
        var y = 1
        func t(_ k: String) -> String { s.l10n.raw("report.plb.sel." + k) }
        func operand(_ op: String) -> String { op == "L" ? "< " : op == "G" ? "> " : op == "E" ? "= " : "  " }
        // customer-in は空白を "Z" に置換済みなので、この条件は常に偽になる (レガシーどおり)
        let blank = " "
        if sel.statusIn == blank && sel.creditOp == blank && sel.invoiceOp == blank && sel.averageOp == blank
            && sel.overdueOp == blank && sel.customerIn.allSatisfy({ $0 == " " }) {
            PLB.string(&r, &y, t("all"))
        } else {
            PLB.string(&r, &y, t("matched"))
        }
        y += 1
        if sel.statusIn == "L" { PLB.string(&r, &y, t("live")) }
        if sel.statusIn == "D" { PLB.string(&r, &y, t("dormant")) }
        y += 1
        if sel.creditOp != " " {
            PLB.string(&r, &y, operand(sel.creditOp) + Pic.edit("z9", value: sel.creditIn, scale: 0) + Cobol.x(t("days_credit"), 12))
        }
        y += 1
        if sel.invoiceOp != " " {
            PLB.string(&r, &y, operand(sel.invoiceOp) + Pic.edit("zzzz9", value: sel.invoiceIn, scale: 0) + Cobol.x(t("invoices"), 9))
        }
        y += 1
        if sel.averageOp != " " {
            PLB.string(&r, &y, operand(sel.averageOp) + Pic.edit("zzzz9", value: sel.averageIn, scale: 0) + Cobol.x(t("av_value"), 10))
        }
        y += 1
        if sel.overdueOp != " " {
            PLB.string(&r, &y, operand(sel.overdueOp) + Pic.edit("zzzz9", value: sel.overdueIn, scale: 0) + Cobol.x(t("days_overdue"), 13))
        }
        y += 1
        if sel.enterDateOp != " " {
            PLB.string(&r, &y, operand(sel.enterDateOp) + Cobol.x(sel.enterDateIn, 8) + Cobol.x(t("entry_date"), 11))
        }
        y += 1
        if !sel.custIn.allSatisfy({ $0 == " " }) {
            PLB.string(&r, &y, t("keys_matching"), sel.custIn)
        }
        return r
    }

    static func reportHeadingSetup(_ st: State) { st.l3Report = headingSetup(st.s, st.sel) }

    /// 選択条件に合うか (read-loop の判定部)
    static func matches(_ s: Session, _ sel: PLB.Selection, _ p: Record) -> Bool {
        let live = p.int("purch-status") == 1, dead = p.int("purch-status") == 0
        if sel.statusIn == "L" && dead { return false }
        if sel.statusIn == "D" && live { return false }
        if sel.creditOp != " " && !PLB.testNum(sel.creditOp, sel.creditIn, p.int("purch-credit")) { return false }
        if sel.invoiceOp != " " && !PLB.testNum(sel.invoiceOp, sel.invoiceIn, p.int("purch-activety")) { return false }
        if sel.averageOp != " " && !PLB.testNum(sel.averageOp, sel.averageIn, p.int("purch-average")) { return false }
        if sel.overdueOp != " " && p.int("purch-current") > 0 {
            let test2 = PLB.wrap32(s.sys.int("run-date") - p.int("purch-last-inv"))
            if !PLB.testNum(sel.overdueOp, sel.overdueIn, test2) { return false }
        }
        if sel.enterDateOp != " " && !PLB.testNum(sel.enterDateOp, sel.wsEnterDate, p.int("purch-create-date")) { return false }
        return true
    }

    static func reportProduce(_ st: State, purchOpen: Bool) throws {
        let s = st.s, c = s.console, sel = st.sel
        let keys = PLB.readSequential(s, s.ledgers + PLB165.sortName, size: 7)
        st.prt.openOutput()
        st.a = 0
        headings(st)
        guard let keys else {
            // open 失敗: READ は AT END にならず "Not Found" を出し続けて戻らない
            c.display(s.t("pl160.pl170"), at: 2301, color: 4)
            c.display(Cobol.x("", 7), at: 2313, color: 4)
            try PLB.hang(s)
        }
        let custIn = Array(Cobol.x(sel.custIn, 7).utf8), customerIn = Array(sel.customerIn.utf8)
        for key in keys {
            // customer-in は空白にならないので常に範囲判定する
            if key.lexicographicallyPrecedes(custIn) { continue }
            if customerIn.lexicographicallyPrecedes(key) { continue }
            guard purchOpen, let p = st.pf.read(key: key) else {
                c.display(s.t("pl160.pl170"), at: 2301, color: 4)
                c.display(SJIS.decode(key[...]), at: 2313, color: 4)
                continue
            }
            c.display(" ", at: 2301, eraseEOL: true)
            if !matches(s, sel, p) { continue }
            listing(st, p)
        }
    }

    static func headings(_ st: State) {
        let s = st.s
        st.a = (st.a + 1) % 100
        let line1 = Cobol.x(progName, 51) + Cobol.x(s.l10n.raw("report.pl160.title"), 73)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.a), scale: 0)
        let line3 = Cobol.x(s.sys.str("usera"), 40) + Cobol.x(s.l10n.raw("report.plb.sel.report_on"), 12)
            + st.l3Report.text + Cobol.x(st.l1Date, 10)
        if st.a != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line3, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line3, 1)
        }
        st.prt.after(Cobol.x(s.l10n.raw("report.pl160.line4a"), 51) + Cobol.x(s.l10n.raw("report.pl160.line4b"), 51)
                     + Cobol.x(s.l10n.raw("report.pl160.line4c"), 30), 1)
        st.prt.after(Cobol.x(s.l10n.raw("report.pl160.line5a"), 87) + Cobol.x(s.l10n.raw("report.pl160.line5b"), 45), 1)
        st.prt.after("", 1)
        st.lineCnt = 6
    }

    static func listing(_ st: State, _ p: Record) {
        let s = st.s
        let pageLines = Int(s.sys.int("page-lines"))
        if st.lineCnt > pageLines { headings(st) }
        let status = s.l10n.raw(p.int("purch-status") == 1 ? "report.pl160.active" : "report.pl160.dormant")
        var phone = PLB.Buf(17)
        let ext = p.str("purch-ext")
        if ext.allSatisfy({ $0 == " " }) {
            phone.put(0, 17, p.str("purch-phone"))
        } else {
            var y = 1
            let ph = Cobol.x(p.str("purch-phone"), 13)
            let head = ph.range(of: "  ").map { String(ph[ph.startIndex..<$0.lowerBound]) } ?? ph
            PLB.string(&phone, &y, head, "x", Cobol.x(ext, 4))
        }
        let delim = s.sys.str("pl-delim")
        var address = Cobol.x(p.str("purch-addr1"), 48) + Cobol.x(p.str("purch-addr2"), 48)
        if let d = delim.first, delim.count == 1 { address = String(address.map { $0 == d ? "," : $0 }) }
        let line6 = Cobol.x(p.str("purch-key"), 10) + Cobol.x(status, 10) + Cobol.x(p.str("purch-name"), 51)
            + phone.text + Cobol.x(p.str("purch-fax"), 14)
            + PLB.bwz("z(9)9bbbb", p.int("purch-limit")) + PLB.bwz("z9bbbbbb", p.int("purch-credit"))
            + PLB.bwz("z9.99", p.int("purch-discount"), scale: 2)
        if st.lineCnt > pageLines - 3 { headings(st) }
        st.prt.after(line6, 1)
        st.prt.after(Cobol.x("", 20) + Cobol.x(address, 96), 1)
        st.prt.after("", 1)
        st.lineCnt = PLB.addChar(st.lineCnt, 3)
    }
}
