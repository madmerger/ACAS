import Foundation

/// general/gl090b.cbl: Detailed Trial Balance — 勘定別の明細試算表
enum GL090B {
    static let progName = "gl090b (3.00.04)"

    /// working-storage (gl090 から cancel されないので呼び出し間で保持される)
    final class WS {
        var j = 0, k = 0
        var totlDr: Int64 = 0, totlCr: Int64 = 0, prevDr: Int64 = 0, prevCr: Int64 = 0
        var pageNos = 0
        var lineCnt: Int8 = 0
        var saveN: Int64 = 0
        var weError = 0
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var filler1 = Cobol.x("", 10)
        var l3Date = "", l3User = ""
    }

    static func u(_ v: Int64) -> Int64 { abs(v) % 10_000_000_000 }

    /// ledger-q (j): 添字は検査されない (0 は ledger-last の位置)
    static func quarter(_ r: Record, _ j: Int) -> Int64 {
        switch j {
        case 0: return r.int("ledger-last")
        case 1...4: return r.int("ledger-q\(j)")
        default: return 0
        }
    }

    static func run(_ s: Session) throws {
        let ws = (s.shared["gl090b.ws"] as? WS) ?? WS()
        s.shared["gl090b.ws"] = ws
        let c = s.console
        func t(_ k: String) -> String { s.t("gl090b." + k) }
        let ledgerFile = GL.ledgerFile(s)
        if !s.store.exists(ledgerFile.path) {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(t("gl106"), at: 901, color: 4)
            c.display(t("gl012"), at: 1001, color: 2)
            _ = try c.accept(at: 1026, size: 1)
            return
        }
        ledgerFile.open()
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        let dates = GLDates(s)
        dates.zz070()
        c.display(dates.wsDate, at: 171, color: 2)
        c.display(t("title"), at: 129, color: 2)
        c.display(t("working"), at: 1212, color: 2)
        GLPrint.open(s)
        if s.sys.str("p-c") == "P" {
            ws.filler1 = Cobol.x(t("p_pc"), 10)
        } else if s.sys.str("p-c") == "B" {
            ws.filler1 = Cobol.x(t("p_branch"), 10)
        } else {
            ws.filler1 = Cobol.x("", 10)
        }
        ws.l3Date = dates.wsDate
        ws.pageNos = 0
        ws.l3User = s.sys.str("usera")
        pageHeading(s, ws)

        func bwz(_ pic: String, _ v: Int64, _ scale: Int) -> String {
            v == 0 ? Cobol.x("", Pic.size(pic)) : Pic.edit(pic, value: v, scale: scale)
        }
        func line6(_ account: Int64, _ pc: Int64, _ name: String, _ cDr: Int64, _ cCr: Int64, _ pDr: Int64, _ pCr: Int64,
                   _ q1: Int64, _ q2: Int64) -> String {
            bwz("9999.99", account, 2) + Cobol.x("", 5) + bwz("z9bbbbbb", pc, 0) + Cobol.x(name, 30)
                + bwz("zzzzzzz9.99b", u(cDr), 2) + bwz("zzzzzzz9.99", u(cCr), 2) + Cobol.x("", 4)
                + bwz("zzzzzzz9.99b", u(pDr), 2) + bwz("zzzzzzz9.99", u(pCr), 2) + Cobol.x("", 4)
                + bwz("zzzzzzz9.99cr", q1, 2) + Cobol.x("", 2) + bwz("zzzzzzz9.99cr", q2, 2)
        }

        while true {
            switch ledgerFile.glNext() {
            case .ok(let r): ws.ledger = r
            case .miss: ws.weError = 255
            case .error: break
            }
            let r = ws.ledger
            let n = r.int("ledger-nos") / 100
            if ws.weError == 255 || n == 9999 { break }
            if n != ws.saveN {
                ws.saveN = n
                GLPrint.write(s, "", after: 1)
                ws.lineCnt &+= 1
            }
            let bal = r.int("ledger-balance"), last = r.int("ledger-last")
            if bal < 0 { ws.totlCr = u(ws.totlCr - bal) } else { ws.totlDr = u(ws.totlDr + bal) }
            if last < 0 { ws.prevCr = u(ws.prevCr - last) } else { ws.prevDr = u(ws.prevDr + last) }
            GLPrint.write(s, line6(r.int("ledger-nos"), r.int("ledger-pc"), GL.shown(r, "ledger-name"),
                                   bal < 0 ? 0 : bal, bal < 0 ? bal : 0, last < 0 ? 0 : last, last < 0 ? last : 0,
                                   quarter(r, ws.j), quarter(r, ws.k)), after: 1)
            ws.lineCnt &+= 1
            if Int64(ws.lineCnt) > s.sys.int("page-lines") { pageHeading(s, ws) }
        }

        let line7 = Cobol.x("", 50) + Cobol.x(t("p_rule"), 50)
        GLPrint.write(s, line7, after: 3)
        GLPrint.write(s, line6(0, 0, t("p_total"), ws.totlDr, ws.totlCr, ws.prevDr, ws.prevCr, 0, 0), after: 1)
        GLPrint.write(s, line7, after: 1)
        GLPrint.close(s)
        ledgerFile.close()
    }

    static func pageHeading(_ s: Session, _ ws: WS) {
        func t(_ k: String) -> String { s.t("gl090b." + k) }
        ws.pageNos = (ws.pageNos + 1) % 1000
        switch s.sys.int("current-quarter") {
        case 1: ws.j = 4; ws.k = 3
        case 2: ws.j = 1; ws.k = 4
        case 3: ws.j = 2; ws.k = 1
        case 4: ws.j = 3; ws.k = 2
        default: break
        }
        let line1 = Cobol.x(progName, 56) + Cobol.x(t("p_title"), 20) + Cobol.x("", 48) + Cobol.x(t("p_page"), 5)
            + Pic.edit("zz9", value: Int64(ws.pageNos), scale: 0)
        let line3 = Cobol.x(ws.l3User, 32) + Cobol.x("", 90) + Cobol.x(ws.l3Date, 10)
        let line4 = Cobol.x(t("p_account"), 10) + ws.filler1 + Cobol.x(t("p_h1"), 94) + "\(ws.j)" + Cobol.x(t("p_h1q"), 14) + "\(ws.k)"
            + Cobol.x(t("p_h1e"), 2)
        if ws.pageNos != 1 {
            GLPrint.writePage(s, line1)
            GLPrint.write(s, line3, after: 1)
            GLPrint.write(s, "", after: 1)
        } else {
            GLPrint.write(s, line1, before: 1)
            GLPrint.write(s, line3, before: 1)
        }
        GLPrint.write(s, line4, after: 1)
        GLPrint.write(s, Cobol.x("", 53) + Cobol.x(t("p_h2"), 43), after: 1)
        GLPrint.write(s, "", after: 1)
        ws.lineCnt = 6
    }
}
