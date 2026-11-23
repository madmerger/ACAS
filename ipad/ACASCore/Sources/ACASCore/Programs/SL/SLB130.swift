import Foundation

/// sales/sl130.cbl: Sales Analysis (売上分析表)
enum SLB130 {
    static let progName = "SL130 (3.01.07)"

    static func run(_ s: Session) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101)
        c.display(s.t("sl130.title"), at: 134)
        let wsDate = SLB.wsDate(s)
        c.display(wsDate, at: 171, color: 2)
        report1(s, wsDate)
        s.sys.setInt("s-flag-a", 0)
    }

    static func bwz(_ text: String, _ v: Int64) -> String {
        v == 0 ? String(repeating: " ", count: text.count) : text
    }

    static func report1(_ s: Session, _ wsDate: String) {
        let vf = SLB.valueFile(s)
        if vf.open() != "00" { vf.close(); return }
        let prt = SLB.Printer(s)
        prt.openOutput()
        var a = 0
        var lineCnt = 66
        var work1: Int64 = 0      // pic 9(4)v9(4)
        var l6Type = Cobol.x("", 9)
        let pageLines = Int(s.sys.int("page-lines"))

        func headings() {
            if lineCnt < pageLines { return }
            a = (a + 1) % 100
            lineCnt = 6
            let line1 = Cobol.x(progName, 58) + Cobol.x(s.t("report.sl130.title"), 64) + Cobol.x(s.t("report.sl130.page"), 5) + SLB.zz(Int64(a), 3)
            let line2 = Cobol.x(s.sys.str("usera"), 52) + Cobol.x("", 70) + wsDate
            if a != 1 {
                prt.afterPage(line1)
                prt.after(line2, 1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
                prt.before(line2, 1)
            }
            prt.after(Cobol.x(s.t("report.sl130.head4_a"), 52) + Cobol.x(s.t("report.sl130.head4_b"), 42) + Cobol.x(s.t("report.sl130.head4_c"), 38), 2)
            prt.after(Cobol.x(s.t("report.sl130.head5_a"), 45) + Cobol.x(s.t("report.sl130.head5_b"), 87), 1)
            prt.after("", 1)
        }
        headings()
        while let v = vf.readNext() {
            let code = Array(Cobol.x(v.str("va-code"), 3))
            if code[0] != "S" { continue }
            if code[2] != " " && v.int("va-v-this") == 0 && v.int("va-v-year") == 0 { continue }
            if code[2] == " " && v.int("va-gl") == 0 {
                l6Type = Cobol.x(s.t("report.sl130.group"), 9)
                headings()
                prt.after("", 1)
                lineCnt = (lineCnt + 1) % 100
            } else {
                l6Type = Cobol.x(s.t("report.sl130.detail"), 9)
            }
            let tThis = v.int("va-t-this"), tLast = v.int("va-t-last"), tYear = v.int("va-t-year")
            // divide (ゼロ除算は SIZE ERROR: work-1 は前の値のまま)
            if tLast != 0 { work1 = (tThis * 10000 / tLast) % 100_000_000 }
            let pT = (work1 / 100) % 10_000_000          // z(4)9.99
            let vThis = v.int("va-v-this"), vLast = v.int("va-v-last"), vYear = v.int("va-v-year")
            if vLast != 0 { work1 = (abs(vThis) * 10000 / abs(vLast)) % 100_000_000 }
            let pA = (work1 / 100) % 1_000_000           // zzz9.99
            let line6 = "   " + Cobol.x(String(code[1...2]), 6) + l6Type + Cobol.x(v.str("va-desc"), 28)
                + bwz(SLB.zz(tThis, 5), tThis) + "     " + bwz(SLB.zz(tLast, 5), tLast) + "      "
                + bwz(SLB.zz(tYear, 5), tYear) + "    "
                + bwz(SLB.z99cr(vThis, 8), vThis) + bwz(SLB.z99cr(vLast, 9), vLast) + bwz(SLB.z99cr(vYear, 9), vYear)
                + bwz(SLB.z99(pT, 5), pT) + bwz(SLB.z99(pA, 4), pA)
            prt.after(line6, 1)
            lineCnt = (lineCnt + 1) % 100
            if lineCnt > pageLines { headings() }
        }
        vf.close()
        prt.spool()
    }
}
