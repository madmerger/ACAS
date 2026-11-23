import Foundation

/// pl170.cbl: 仕入先別取引高帳票 (Purchase Ledger Turnover Report)
enum PLB170 {
    static let progName = "PL170 (3.01.06)"

    final class State {
        let s: Session
        let prt: PLBPrint
        let pf: IndexedFile
        let sel = PLB.Selection()
        var a = 0, lineCnt = 0
        var l1Date = ""
        init(_ s: Session) { self.s = s; prt = PLBPrint(s); pf = PLB.purchFile(s) }
    }

    static func run(_ s: Session) throws {
        let st = State(s)
        st.l1Date = PLB.wsDate(s)
        let purchOpen = st.pf.open() == "00"
        st.prt.openOutput()
        try reportSelection(st)
        produceReport(st, purchOpen: purchOpen)
        // レガシーの癖: end-report 段落が後続の shorten-ws-date section 内にあるため、
        // 帳票作成後は report-selection section へ落ちて選択画面をもう一度表示・入力し、
        // そのままプログラム終端で戻る。print-file の close と印刷コマンドの呼出しは実行されない
        // (帳票の内容は終了時に prt-1 へ書き出される)。
        st.prt.close()
        try reportSelection(st)
    }

    static func reportSelection(_ st: State) throws {
        try PLB160.select(st.s, progName: progName, sel: st.sel, invalidDate: st.s.t("plb.pl005"), replaceSpaces: false)
    }

    static func produceReport(_ st: State, purchOpen: Bool) {
        let s = st.s, sel = st.sel
        st.a = 0
        headings(st)
        var readOK = purchOpen
        var customerIn = Array(sel.customerIn.utf8)
        let blank = customerIn.allSatisfy { $0 == 0x20 }
        if !blank {
            if !st.pf.start(notLessThan: customerIn) { st.a = 1; readOK = false }
            customerIn = customerIn.map { $0 == 0x20 ? 0x5a : $0 }
        }
        while readOK, let p = st.pf.readNext() {
            let status = p.int("purch-status")
            if sel.statusIn == "L" && status == 0 { continue }
            if sel.statusIn == "D" && status == 1 { continue }
            if !blank && customerIn.lexicographicallyPrecedes(p.raw("purch-key")) { break }
            if sel.creditOp != " " && !testNum(sel.creditOp, sel.creditIn, p.int("purch-credit")) { continue }
            if sel.invoiceOp != " " && !testNum(sel.invoiceOp, sel.invoiceIn, p.int("purch-activety")) { continue }
            if sel.averageOp != " " && !testNum(sel.averageOp, sel.averageIn, p.int("purch-average")) { continue }
            if sel.overdueOp != " " && p.int("purch-current") > 0 {
                let test2 = PLB.wrap32(s.sys.int("run-date") - p.int("purch-last-inv"))
                if !testNum(sel.overdueOp, sel.overdueIn, test2) { continue }
            }
            if sel.enterDateOp != " " && !testNum(sel.enterDateOp, sel.wsEnterDate, p.int("purch-create-date")) { continue }
            listing(st, p)
        }
    }

    static func testNum(_ op: String, _ test1: Int64, _ test2: Int64) -> Bool {
        switch op {
        case " ": return true
        case "L": return test2 < test1
        case "G": return test2 > test1
        case "E": return test2 == test1
        default: return false
        }
    }

    static func headings(_ st: State) {
        let s = st.s
        st.a = (st.a + 1) % 1000
        let line1 = Cobol.x(progName, 51) + Cobol.x(s.l10n.raw("report.pl170.title"), 73)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.a), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 51) + Cobol.x("", 71) + Cobol.x(st.l1Date, 10)
        if st.a != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line2, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line2, 1)
        }
        st.prt.after(Cobol.x("", 38) + s.l10n.raw("report.pl170.line3"), 1)
        st.prt.after(Cobol.x(s.l10n.raw("report.pl170.line4a"), 38) + s.l10n.raw("report.pl170.line4b"), 1)
        st.prt.after("", 1)
        st.lineCnt = 6
    }

    /// zz060-Convert-Date + shorten-ws-date
    static func shortDate(_ s: Session, _ bin: Int64) -> String {
        var d = Array(Cobol.x(PLB.binDate(s, bin), 10))
        let form = s.sys.int("date-form")
        if form == 1 || form == 2 {
            d[6] = d[8]; d[7] = d[9]
        } else {
            for i in 0..<8 { d[i] = d[i + 2] }
        }
        d[8] = " "; d[9] = " "
        return String(d)
    }

    static func listing(_ st: State, _ p: Record) {
        let s = st.s
        func n(_ pic: String, _ v: Int64) -> String { Pic.edit(pic, value: v, scale: 0) }
        func m(_ v: Int64) -> String { Pic.edit("-(7)9", value: v, scale: 2) }
        let current = Cobol.truncate(p.int("purch-current") - p.int("purch-unapplied"), digits: 10)
        let lastInv = p.int("purch-last-inv"), lastPay = p.int("purch-last-pay")
        let line5 = Cobol.x(p.str("purch-key"), 8) + Cobol.x(p.str("purch-name"), 30)
            + n("zzz9", p.int("purch-credit")) + n("z(7)9", p.int("purch-limit"))
            + n("-(5)9", p.int("purch-activety")) + n("-(7)9", p.int("purch-average"))
            + m(p.int("turnover-q1")) + m(p.int("turnover-q2")) + m(p.int("turnover-q3")) + m(p.int("turnover-q4"))
            + m(current) + m(p.int("purch-last")) + "  "
            + Cobol.x(lastInv == 0 ? "" : shortDate(s, lastInv), 10) + "  "
            + Cobol.x(lastPay == 0 ? "" : shortDate(s, lastPay), 8)
        st.prt.after(line5, 1)
        st.lineCnt = PLB.addChar(st.lineCnt, 1)
        if st.lineCnt > Int(s.sys.int("page-lines")) { headings(st) }
    }
}
