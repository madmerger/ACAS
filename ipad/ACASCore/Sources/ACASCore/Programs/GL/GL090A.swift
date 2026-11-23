import Foundation

/// general/gl090a.cbl: Structured (Profit Centre) Trial Balance — 階層別の要約試算表
enum GL090A {
    static let progName = "gl090a (3.00.04)"

    /// working-storage (gl090 から cancel されないので呼び出し間で保持される)
    final class WS {
        var lDr = [Int64](repeating: 0, count: 6), lCr = [Int64](repeating: 0, count: 6)
        var store = [Int64](repeating: 0, count: 6)
        var pageCnt: Int8 = 0, lineCnt: Int8 = 0
        var totDr: Int64 = 0, totCr: Int64 = 0
        var weError = 0
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var amounts = [Int64](repeating: 0, count: 11)
        var account = Cobol.x("", 12)
        var l3Date = "", l3User = ""
    }

    /// 符号なし 9(8)v99 への格納
    static func u(_ v: Int64) -> Int64 { abs(v) % 10_000_000_000 }

    static func run(_ s: Session) throws {
        let ws = (s.shared["gl090a.ws"] as? WS) ?? WS()
        s.shared["gl090a.ws"] = ws
        let c = s.console
        func t(_ k: String) -> String { s.t("gl090a." + k) }
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(t("title"), at: 129, color: 2)
        let dates = GLDates(s)
        dates.zz070()
        c.display(dates.wsDate, at: 171, color: 2)
        GLPrint.open(s)
        ws.l3Date = dates.wsDate
        ws.l3User = s.sys.str("usera")
        let ledgerFile = GL.ledgerFile(s)
        ledgerFile.open()
        for i in 1...5 { ws.lCr[i] = 0; ws.lDr[i] = 0; ws.store[i] = 0 }
        ws.weError = 0; ws.totDr = 0; ws.totCr = 0
        headings(s, ws)

        while true {
            switch ledgerFile.glNext() {
            case .ok(let r): ws.ledger = r
            case .miss: ws.weError = 255
            // 未オープンの ledger-file は at end にならず読み続ける (無限ループ)
            case .error: try GL.hang(s)
            }
            let nos = ws.ledger.int("ledger-nos"), level = ws.ledger.int("ledger-level")
            if ws.weError == 255 || nos / 100 == 9999 {
                detailPrint(s, ws)
                total4(s, ws); total3(s, ws); total2(s, ws); total1(s, ws)
                break
            }
            if nos != ws.store[5] && ws.store[5] != 0 {
                detailPrint(s, ws)
                ws.lCr[5] = 0; ws.lDr[5] = 0
                if level == 0 { ws.store[5] = nos }
            }
            if nos == ws.store[4] || nos == ws.store[3] || nos == ws.store[2] || nos == ws.store[1] { continue }
            if level == 4 && ws.store[4] == 0 { ws.store[4] = nos; continue }
            if level == 4 { total4(s, ws); ws.store[4] = nos; continue }
            if level == 3 && ws.store[3] == 0 { ws.store[3] = nos; continue }
            if level == 3 { total4(s, ws); total3(s, ws); ws.store[3] = nos; continue }
            if level == 2 && ws.store[2] == 0 { ws.store[2] = nos; continue }
            if level == 2 { total4(s, ws); total3(s, ws); total2(s, ws); ws.store[2] = nos; continue }
            if level == 1 && ws.store[1] == 0 { ws.store[1] = nos; continue }
            if level == 1 { total4(s, ws); total3(s, ws); total2(s, ws); total1(s, ws); ws.store[1] = nos; continue }
            let bal = ws.ledger.int("ledger-balance")
            if nos == ws.store[5] {
                // accumulate
                if bal < 0 { ws.lCr[5] = u(ws.lCr[5] - bal) } else { ws.lDr[5] = u(ws.lDr[5] + bal) }
                continue
            }
            if bal < 0 { ws.lCr[5] = u(bal) } else { ws.lDr[5] = u(bal) }
            ws.store[5] = nos
        }

        let line7 = Cobol.x("", 108) + Cobol.x(t("p_rule"), 23)
        GLPrint.write(s, line7, after: 3)
        let line8 = Cobol.x("", 20) + Cobol.x(t("p_total"), 88) + Pic.edit("zzzzzzz9.99b", value: ws.totDr, scale: 2)
            + Pic.edit("zzzzzzz9.99", value: ws.totCr, scale: 2)
        GLPrint.write(s, line8, after: 1)
        GLPrint.write(s, line7, after: 1)
        GLPrint.close(s)
        ledgerFile.close()
    }

    static func headings(_ s: Session, _ ws: WS) {
        func t(_ k: String) -> String { s.t("gl090a." + k) }
        ws.pageCnt &+= 1
        let line1 = Cobol.x(progName, 50) + Cobol.x(t("p_title"), 27) + Cobol.x("", 47) + Cobol.x(t("p_page"), 5)
            + Pic.edit("zz9", value: Int64(abs(Int(ws.pageCnt))), scale: 0)
        let line3 = Cobol.x(ws.l3User, 32) + Cobol.x("", 25) + Cobol.x(t("p_report"), 16) + Cobol.x("", 49) + Cobol.x(ws.l3Date, 10)
        if ws.pageCnt != 1 {
            GLPrint.writePage(s, line1)
            GLPrint.write(s, line3, after: 1)
            GLPrint.write(s, "", after: 1)
        } else {
            GLPrint.write(s, line1, before: 1)
            GLPrint.write(s, line3, before: 1)
        }
        GLPrint.write(s, Cobol.x(t("p_h1a"), 50) + Cobol.x(t("p_h1b"), 54) + Cobol.x(t("p_h1c"), 28), after: 1)
        GLPrint.write(s, Cobol.x(t("p_h2a"), 53) + Cobol.x(t("p_h2b"), 56) + Cobol.x(t("p_h2c"), 23), after: 1)
        GLPrint.write(s, "", after: 1)
        ws.lineCnt = 6
    }

    /// string redef-ac into l6-account with pointer
    static func setAccount(_ ws: WS, _ level: Int, pointer: Int) {
        var a = Array(Cobol.x("", 12))
        a.replaceSubrange((pointer - 1)..<(pointer + 6), with: Array(Pic.edit("9999.99", value: ws.store[level] % 1_000_000, scale: 2)))
        ws.account = String(a)
    }

    static func writeLine6(_ s: Session, _ ws: WS) {
        var line = ws.account
        for i in 1...10 { line += ws.amounts[i] == 0 ? Cobol.x("", 12) : Pic.edit("zzzzzzz9.99b", value: ws.amounts[i], scale: 2) }
        GLPrint.write(s, line, after: 1)
        ws.lineCnt &+= 1
        if Int64(ws.lineCnt) > s.sys.int("page-lines") { headings(s, ws) }
    }

    /// 上位の階層 (無ければ総合計) へ集計
    static func rollUp(_ ws: WS, from level: Int) {
        var parent = level - 1
        while parent >= 1 && ws.store[parent] == 0 { parent -= 1 }
        if parent >= 1 {
            ws.lDr[parent] = u(ws.lDr[parent] + ws.lDr[level])
            ws.lCr[parent] = u(ws.lCr[parent] + ws.lCr[level])
        } else {
            toTotal(ws, level)
        }
    }

    static func toTotal(_ ws: WS, _ level: Int) {
        if ws.lDr[level] > ws.lCr[level] {
            ws.totDr = u(u(ws.totDr + ws.lDr[level]) - ws.lCr[level])
        } else {
            ws.totCr = u(u(ws.totCr + ws.lCr[level]) - ws.lDr[level])
        }
    }

    static func detailPrint(_ s: Session, _ ws: WS) {
        setAccount(ws, 5, pointer: 5)
        ws.amounts = [Int64](repeating: 0, count: 11)
        ws.amounts[1] = ws.lDr[5]; ws.amounts[2] = ws.lCr[5]
        writeLine6(s, ws)
        rollUp(ws, from: 5)
        ws.lDr[5] = 0; ws.lCr[5] = 0
    }

    static func net(_ ws: WS, _ level: Int, _ col: Int) {
        ws.amounts = [Int64](repeating: 0, count: 11)
        if ws.lDr[level] > ws.lCr[level] {
            ws.amounts[col] = u(ws.lDr[level] - ws.lCr[level])
        } else {
            ws.amounts[col + 1] = u(ws.lCr[level] - ws.lDr[level])
        }
    }

    static func total4(_ s: Session, _ ws: WS) { total(s, ws, 4, pointer: 4, col: 3) }
    static func total3(_ s: Session, _ ws: WS) { total(s, ws, 3, pointer: 3, col: 5) }
    static func total2(_ s: Session, _ ws: WS) { total(s, ws, 2, pointer: 2, col: 7) }

    static func total(_ s: Session, _ ws: WS, _ level: Int, pointer: Int, col: Int) {
        setAccount(ws, level, pointer: pointer)
        net(ws, level, col)
        if ws.store[level] != 0 { writeLine6(s, ws) }
        rollUp(ws, from: level)
        ws.store[level] = 0; ws.lDr[level] = 0; ws.lCr[level] = 0
    }

    static func total1(_ s: Session, _ ws: WS) {
        setAccount(ws, 1, pointer: 1)
        net(ws, 1, 9)
        writeLine6(s, ws)
        GLPrint.write(s, "", after: 1)
        toTotal(ws, 1)
        ws.store[1] = 0; ws.lDr[1] = 0; ws.lCr[1] = 0
    }
}
