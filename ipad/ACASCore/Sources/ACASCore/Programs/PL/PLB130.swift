import Foundation

/// pl130.cbl: 仕入分析帳票 (Purchase Analysis)
enum PLB130 {
    static let progName = "PL130 (3.01.04)"

    final class State {
        let s: Session
        let prt: PLBPrint
        var a = 0, lineCnt = 66
        var work1: Int64 = 0        // 9(4)v9(4)
        var l2Date = ""
        init(_ s: Session) { self.s = s; prt = PLBPrint(s) }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State(s)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("pl130.title"), at: 134, color: 2)
        st.l2Date = PLB.wsDate(s)
        c.display(st.l2Date, at: 171, color: 2)
        report1(st)
        s.sys.setInt("p-flag-a", 0)
    }

    static func report1(_ st: State) {
        let s = st.s
        let vf = PLB.valueFile(s)
        if vf.open() != "00" { return }
        st.prt.openOutput()
        st.a = 0
        headings(st)
        while let v = vf.readNext() {
            let code = Array(Cobol.x(v.str("va-code"), 3))
            if code[0] != "P" { continue }
            let vThis = v.int("va-v-this"), vLast = v.int("va-v-last"), vYear = v.int("va-v-year")
            let tThis = v.int("va-t-this"), tLast = v.int("va-t-last"), tYear = v.int("va-t-year")
            if code[2] != " " && vThis == 0 && vYear == 0 { continue }
            let type: String
            if code[2] == " " && v.int("va-gl") == 0 {
                type = s.l10n.raw("report.pl130.group")
                headings(st)
                st.prt.after("", 1)
                st.lineCnt = PLB.addChar(st.lineCnt, 1)
            } else {
                type = s.l10n.raw("report.pl130.detail")
            }
            // 0 での除算は桁あふれ扱いで work-1 は変わらない
            if tLast != 0 { st.work1 = (tThis * 10_000 / tLast) % 100_000_000 }
            let pT = st.work1 * 100
            if vLast != 0 { st.work1 = abs(vThis * 10_000 / vLast) % 100_000_000 }
            let pA = st.work1 * 100
            let line6 = "   " + String(code[1...2]) + "    " + Cobol.x(type, 9) + Cobol.x(v.str("va-desc"), 28)
                + PLB.bwz("zzzz9", tThis) + "     " + PLB.bwz("zzzz9", tLast) + "      " + PLB.bwz("zzzz9", tYear) + "    "
                + PLB.bwz("z(7)9.99cr", vThis, scale: 2) + PLB.bwz("z(8)9.99cr", vLast, scale: 2)
                + PLB.bwz("z(8)9.99cr", vYear, scale: 2)
                + PLB.bwz("z(4)9.99", pT, scale: 4) + PLB.bwz("zzz9.99", pA, scale: 4)
            st.prt.after(line6, 1)
            st.lineCnt = PLB.addChar(st.lineCnt, 1)
            if st.lineCnt > Int(s.sys.int("page-lines")) { headings(st) }
        }
        vf.close()
        st.prt.close()
        st.prt.spool()
    }

    static func headings(_ st: State) {
        let s = st.s
        if st.lineCnt < Int(s.sys.int("page-lines")) - 8 { return }
        st.a = (st.a + 1) % 100
        st.lineCnt = 0
        let line1 = Cobol.x(progName, 49) + Cobol.x(s.l10n.raw("report.pl130.title"), 75)
            + Cobol.x(s.l10n.raw("report.pl130.page"), 6) + Pic.edit("z9", value: Int64(st.a), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 49) + Cobol.x("", 73) + Cobol.x(st.l2Date, 10)
        if st.a != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line2, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line2, 1)
        }
        st.prt.after(s.l10n.raw("report.pl130.line4"), 1)
        st.prt.after(Cobol.x(s.l10n.raw("report.pl130.line5a"), 45) + s.l10n.raw("report.pl130.line5b"), 1)
        st.prt.after("", 1)
    }
}
