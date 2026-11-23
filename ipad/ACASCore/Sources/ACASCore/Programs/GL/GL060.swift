import Foundation

/// general/gl060.cbl: Batch Status Report (バッチ状態の表示・印刷)
enum GL060 {
    static let progName = "gl060 (3.00.04)"

    final class WS {
        let s: Session
        let c: Console
        let dates: GLDates
        let batchFile: IndexedFile
        var batch = Record(GL.batchLayout, bytes: [UInt8](repeating: 0, count: GL.batchLayout.size))
        var a = 0, y = 0, lineCnt = 0
        var lin = 0, cole = 0, lin2 = 0, col2 = 0
        var l3Date = "", l6Ledger = Cobol.x("", 8), l6Status = Cobol.x("", 11)
        init(_ s: Session) { self.s = s; c = s.console; dates = GLDates(s); batchFile = GL.batchFile(s) }
        var curs: Int { lin * 100 + cole }
        var curs2: Int { lin2 * 100 + col2 }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func t(_ k: String) -> String { s.t("gl060." + k) }
        var line4: String { Cobol.x(t("p_h1a"), 48) + Cobol.x(t("p_h1b"), 32) }
        var line5: String { Cobol.x(t("p_h2a"), 48) + Cobol.x(t("p_h2b"), 32) }
        var l3Cycle: String { Pic.edit("z9", value: s.sys.int("scycle"), scale: 0) }
    }

    /// menu-input 段落 (画面見出し)
    static func menuInput(_ ws: WS) {
        ws.dates.zz070()
        ws.l3Date = ws.dates.wsDate
        ws.c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("title"), 132)
        ws.d(ws.dates.wsDate, 171)
    }

    static func run(_ s: Session) throws {
        let ws = WS(s)
        while true {
            menuInput(ws)
            ws.d(s.sys.str("usera"), 301)
            ws.d(ws.t("select"), 801)
            ws.d(ws.t("opt1"), 1001)
            ws.d(ws.t("opt2"), 1201)
            ws.d(ws.t("opt9"), 1501)
            ws.a = Int(Cobol.moveNumeric(try s.console.accept(at: 843, size: 1, kind: .numeric, initial: "0", options: [.update], color: 6), digits: 1, scale: 0))
            if ws.a == 9 { return }
            if ws.a == 1 || ws.a == 2 { try gl060a(ws) }
        }
    }

    static func headings(_ ws: WS) {
        let s = ws.s
        ws.y = Int(Int8(truncatingIfNeeded: ws.y + 1))
        let line1 = Cobol.x(progName, 31) + Cobol.x(ws.t("p_title"), 41) + Cobol.x(ws.t("p_page"), 6) + Pic.edit("z9", value: Int64(ws.y), scale: 0)
        let line3 = Cobol.x(ws.t("p_cycle"), 8) + ws.l3Cycle + Cobol.x("", 60) + Cobol.x(ws.l3Date, 10)
        if ws.y != 1 {
            GLPrint.writePage(s, line1)
            GLPrint.write(s, line3, after: 1)
            GLPrint.write(s, "", after: 1)
        } else {
            GLPrint.write(s, line1, before: 1)
            GLPrint.write(s, line3, before: 1)
        }
        GLPrint.write(s, ws.line4, after: 1)
        GLPrint.write(s, ws.line5, after: 1)
        GLPrint.write(s, "", after: 1)
        ws.lineCnt = 6
    }

    static func gl060a(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        menuInput(ws)
        ws.d(ws.t("cycle"), 301)
        ws.d(ws.l3Cycle, 309)
        if ws.a == 2 {
            GLPrint.open(s)
            headings(ws)
        } else {
            ws.d(ws.line4, 501)
            ws.d(ws.line5, 601)
        }
        ws.lin = 7; ws.cole = 1
        ws.batchFile.open()
        let l22 = (GL.lines - 2) * 100
        loop: while true {
            var notOpen = false
            switch ws.batchFile.glNext() {
            case .ok(let r): ws.batch = r
            case .miss: break loop
            case .error: notOpen = true
            }
            let b = ws.batch
            // 未オープンの batch-file は at end にならず読み続ける (無限ループ)
            if b.int("bcycle") != s.sys.int("scycle") { if notOpen { try GL.hang(s) }; continue }
            switch b.int("ledger") {
            case 1: ws.l6Ledger = Cobol.x(ws.t("l_gl"), 8)
            case 2: ws.l6Ledger = Cobol.x(ws.t("l_pl"), 8)
            case 3: ws.l6Ledger = Cobol.x(ws.t("l_sl"), 8)
            default: break
            }
            for f in ["stored", "posted", "proofed", "entered"] where b.int(f) != 0 {
                ws.dates.uBin = Int(b.int(f))
                ws.dates.zz060()
                break
            }
            let st = b.int("batch-status"), cl = b.int("cleared-status")
            if st == 0 { ws.l6Status = Cobol.x(ws.t("s_open"), 11) }
            if st == 1 && cl == 0 { ws.l6Status = Cobol.x(ws.t("s_waiting"), 11) }
            if st == 1 && cl == 1 { ws.l6Status = Cobol.x(ws.t("s_processed"), 11) }
            if st == 1 && cl == 2 { ws.l6Status = Cobol.x(ws.t("s_archived"), 11) }
            let items = Pic.edit("z9bbbb", value: b.int("items"), scale: 0)
            func vat(_ v: Int64) -> String { v == 0 ? Cobol.x("", 12) : Pic.edit("zzzzzzzz9.99", value: v, scale: 2) }
            let line6 = ws.l6Ledger + Pic.edit("zzzz9bb", value: b.int("batch-nos"), scale: 0) + ws.l6Status + Cobol.x(ws.dates.wsDate, 14)
                + Cobol.x(ws.t("p_header"), 9) + items + Pic.edit("zzzzzzzz9.99b", value: b.int("input-gross"), scale: 2) + vat(b.int("input-vat"))
            let line7 = Cobol.x("", 40) + Cobol.x(ws.t("p_actual"), 9) + items
                + Pic.edit("zzzzzzzz9.99b", value: b.int("actual-gross"), scale: 2) + vat(b.int("actual-vat"))
            ws.lin2 = ws.lin + 1; ws.col2 = ws.cole
            if ws.a == 2 {
                // detail-print
                GLPrint.write(s, line6, after: 2)
                ws.lineCnt += 2
                if ws.lineCnt > Int(s.sys.int("page-lines")) { headings(ws) }
                GLPrint.write(s, line7, after: 1)
                ws.lineCnt += 1
            } else {
                ws.d(line6, ws.curs2)
                ws.lin2 += 1
                ws.d(line7, ws.curs2)
                ws.lin += 3
            }
            if notOpen { try GL.hang(s) }
            if ws.lin < GL.lines - 3 { continue }
            ws.d(ws.t("next_screen"), l22 + 1)
            while true {
                let r = Cobol.upper(try c.accept(at: l22 + 46, size: 1, color: 6))
                if r == "X" { break loop }
                if r == "N" {
                    ws.lin = 7
                    c.display(" ", at: ws.curs, eraseEOS: true)
                    continue loop
                }
            }
        }
        // end-report
        if ws.a == 2 {
            GLPrint.close(s)
        } else {
            ws.d(ws.t("type_return"), l22 + 1)
            _ = try c.accept(at: l22 + 22, size: 1)
        }
        ws.batchFile.close()
    }
}
