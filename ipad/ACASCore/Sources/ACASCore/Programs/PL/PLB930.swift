import Foundation

/// pl930.cbl: 支払予定の検証帳票 (Payments Due Proof Report)
enum PLB930 {
    static let progName = "PL930 (3.01.07)"

    final class State {
        let s: Session
        let prt: PLBPrint
        var p = 0, lineCnt = 0
        var l1Date = ""
        init(_ s: Session) { self.s = s; prt = PLBPrint(s) }
    }

    static func u9(_ v: Int64) -> Int64 { abs(v) % 1_000_000_000 }

    static func run(_ s: Session) throws {
        let st = State(s)
        st.l1Date = PLB.wsDate(s)
        let pf = PLB.purchFile(s), payFile = PLB.payFile(s)
        let purchOpen = pf.open() == "00"
        let payOpen = payFile.open() == "00"
        st.prt.openOutput()
        headings(st)
        if !payOpen {
            // レガシー実測: pay-file が開けないと READ NEXT は AT END にならず、空行を帳票へ書き続けて戻らない。
            // 端末内では見出しまでを帳票へ残し、際限のない空行の出力は行わずに停止状態だけを再現する。
            st.prt.close()
            try PLB.hang(s)
        }
        let pageLines = Int(s.sys.int("page-lines"))
        var bal0: Int64 = 0, bal30: Int64 = 0, bal60: Int64 = 0, bal90: Int64 = 0, balT: Int64 = 0
        var tot0: Int64 = 0, tot30: Int64 = 0, tot60: Int64 = 0, tot90: Int64 = 0, totT: Int64 = 0
        var purchKey = Cobol.x("", 7), purchName = Cobol.x("", 30)
        var l5Key = "", l5Supplier = ""
        var next = payFile.readNext()
        readPurchase: while var pay = next {
            var skipPayRead = true
            while true {
                if skipPayRead {
                    if st.lineCnt != 5 { st.prt.after("", 1) }
                    st.lineCnt = PLB.addChar(st.lineCnt, 1)
                    purchKey = pay.str("pay-supl-key")
                    if purchOpen {
                        if let p = pf.read(key: pay.raw("pay-supl-key")) {
                            purchName = p.str("purch-name")
                        } else {
                            purchKey = String(repeating: "Z", count: 7)
                            purchName = String(repeating: "Z", count: 30)
                        }
                    }
                    l5Supplier = purchName
                    l5Key = pay.str("pay-supl-key") + "/" + Cobol.z(pay.int("pay-nos") % 100, 2)
                }
                for z in 1...9 {
                    let value = pay.int("pay-value-\(z)")
                    if value == 0 { continue }
                    let method = pay.int("pay-sortcode") != 0 ? "B" : "C"
                    switch pay.int("pay-period-\(z)") {
                    case 0: bal0 = u9(value)
                    case 30: bal30 = u9(value)
                    case 60: bal60 = u9(value)
                    case 90: bal90 = u9(value)
                    default: break
                    }
                    balT = u9(balT + value)
                    tot0 = u9(tot0 + bal0); tot30 = u9(tot30 + bal30); tot60 = u9(tot60 + bal60); tot90 = u9(tot90 + bal90)
                    func cr(_ v: Int64) -> String { PLB.bwz("z(6)9.99cr", v, scale: 2) }
                    let line5 = Cobol.x(l5Key, 12) + Cobol.x(l5Supplier, 23)
                        + Pic.edit("z(7)9b", value: pay.int("pay-folio-\(z)"), scale: 0) + method + " "
                        + Cobol.x(PLB.binDate(s, pay.int("pay-date")), 12) + Cobol.x(pay.str("pay-invoice-\(z)"), 11)
                        + cr(bal0) + cr(bal30) + cr(bal60) + cr(bal90) + "    " + PLB.bwz("z(6)9.99", balT, scale: 2)
                    st.prt.after(line5, 1)
                    st.lineCnt = PLB.addChar(st.lineCnt, 1)
                    if st.lineCnt > pageLines { headings(st) }
                    bal0 = 0; bal30 = 0; bal60 = 0; bal90 = 0
                    l5Key = ""; l5Supplier = ""
                }
                if pay.str("pay-cont") != "C" {
                    totT = u9(totT + balT)
                    balT = 0
                    next = payFile.readNext()
                    continue readPurchase
                }
                // process-cont
                guard let cont = payFile.readNext() else {
                    totT = u9(totT + balT)
                    break readPurchase
                }
                pay = cont
                skipPayRead = purchKey != pay.str("pay-supl-key")
            }
        }
        // main-end
        func cr(_ v: Int64) -> String { PLB.bwz("z(6)9.99cr", v, scale: 2) }
        let dash = Cobol.x("  --------  ", 12)
        st.prt.after(Cobol.x("", 69) + dash + dash + dash + dash + "    " + Cobol.x("  ========", 12), 1)
        st.prt.after(Cobol.x(s.l10n.raw("report.pl910.total"), 69) + cr(tot0) + cr(tot30) + cr(tot60) + cr(tot90)
                     + "    " + PLB.bwz("z(6)9.99", totT, scale: 2), 1)
        st.prt.close()
        pf.close(); payFile.close()
        st.prt.spool()
    }

    static func headings(_ st: State) {
        let s = st.s
        st.p = (st.p + 1) % 100
        let line1 = Cobol.x(progName, 53) + Cobol.x(s.l10n.raw("report.pl930.title"), 71)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.p), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 53) + Cobol.x("", 69) + Cobol.x(st.l1Date, 10)
        if st.p != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line2, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line2, 1)
        }
        st.prt.after(Cobol.x("", 38) + Cobol.x(s.l10n.raw("report.pl910.line4b"), 94), 1)
        st.prt.after("", 1)
        st.lineCnt = 5
    }
}
