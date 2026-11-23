import Foundation

/// sales/sl200.cbl: Invoice Deletion Report (請求書削除リスト)
enum SLB200 {
    static let progName = "SL200 (3.01.04)"

    static func run(_ s: Session) throws {
        let prt = SLB.Printer(s, variable: true)
        prt.openOutput()
        var lineCnt = 0, pageCnt = 0
        func headings1() {
            pageCnt = (pageCnt + 1) % 100
            // head-line (80 桁) は print-record の再定義。直前に print-record は空白。
            let head = Cobol.x(progName, 15) + Cobol.x("", 14) + Cobol.x(s.t("report.sl200.title"), 23) + Cobol.x("", 9)
                + Cobol.x(SLB.wsDate(s), 12) + Cobol.x(s.t("report.sl200.page"), 5) + SLB.zz(Int64(pageCnt), 2)
            lineCnt = 4
            if pageCnt != 1 { prt.afterPage(head) } else { prt.after(head, 1) }
            prt.after(s.t("report.sl200.head"), 2)
            prt.after("", 1)
        }
        headings1()
        // del-inv-nos-file: 順編成 19 バイト (del-inv-nos 9(8), del-inv-dat binary-long, del-inv-cus x(7))
        let data = s.store.readRaw(s.ledgers + "delinvno.dat")
        if let data {
            var pos = 0
            while pos + 19 <= data.count {
                let r = Array(data[pos..<pos + 19])
                pos += 19
                let nos = Cobol.moveNumeric(SJIS.decode(r[0..<8]), digits: 8, scale: 0)
                let dat = Int64(Int32(truncatingIfNeeded: UInt32(r[8]) | UInt32(r[9]) << 8 | UInt32(r[10]) << 16 | UInt32(r[11]) << 24))
                let line = "   " + SLB.zz(nos, 10) + Cobol.x("", 5) + SLB.convBin(s, dat).wsDate + "   " + SJIS.decode(r[12..<19])
                prt.after(line, 1)
                lineCnt = (lineCnt + 1) % 100
                if lineCnt > 70 { headings1() }
            }
            if pageCnt == 1 && lineCnt == 4 { prt.after(s.t("report.sl200.none"), 1) }
        } else {
            prt.after(s.t("report.sl200.none"), 2)
        }
        prt.close()
        prt.spool()
    }
}
