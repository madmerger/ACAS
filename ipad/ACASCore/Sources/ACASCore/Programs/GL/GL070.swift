import Foundation

/// general/gl070.cbl: Transaction Posting — Phase 1 (バッチ検査) / Phase 2 (仕訳の前処理: pretrans.tmp 作成)
enum GL070 {
    static let progName = "gl070 (3.00.02)"

    final class WS {
        let s: Session
        let c: Console
        let dates: GLDates
        let batchFile: IndexedFile
        var batch = Record(GL.batchLayout, bytes: [UInt8](repeating: 0, count: GL.batchLayout.size))
        var post = Record(GL.postingLayout, bytes: [UInt8](repeating: 0, count: GL.postingLayout.size))
        var pre = Record(GLTrans.layout, bytes: [UInt8](repeating: 0, count: GLTrans.layout.size))
        var a = 0, y = 0
        var lin = 0, cole = 0, lin2 = 0, col2 = 0
        var l1Page = " 0", l3Cycle = " 0", l3Date = ""
        var l6Ledger = Cobol.x("", 8), l6Status = Cobol.x("", 11)
        init(_ s: Session) { self.s = s; c = s.console; dates = GLDates(s); batchFile = GL.batchFile(s) }
        var curs: Int { lin * 100 + cole }
        var curs2: Int { lin2 * 100 + col2 }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func t(_ k: String) -> String { s.t("gl070." + k) }
    }

    static func menuInput(_ ws: WS) {
        ws.c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("title"), 132)
        ws.d(ws.dates.wsDate, 171)
    }

    static func run(_ s: Session) throws {
        let ws = WS(s)
        ws.dates.zz070()
        ws.l3Date = ws.dates.wsDate
        menuInput(ws)
        ws.a = 0
        ws.d(ws.t("phase1"), 801)
        try gl071a(ws)
        if ws.a == 1 {
            try gl060a(ws)
            s.termCode = 5
            return
        }
        ws.d(ws.t("phase2"), 801)
        try gl071b(ws)
    }

    /// gl071a: 当サイクルに未確定 (open) のバッチがあれば a = 1
    static func gl071a(_ ws: WS) throws {
        ws.batchFile.open()
        loop: while true {
            var notOpen = false
            switch ws.batchFile.glNext() {
            case .ok(let r): ws.batch = r
            case .miss: break loop
            case .error: notOpen = true
            }
            if ws.batch.int("bcycle") == ws.s.sys.int("scycle") && ws.batch.int("batch-status") == 0 { ws.a = 1 }
            // 未オープンの batch-file は at end にならず読み続ける (無限ループ)
            if notOpen { try GL.hang(ws.s) }
        }
        ws.batchFile.close()
    }

    /// gl060a: バッチ状態の表示
    static func gl060a(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        menuInput(ws)
        ws.dates.zz070()
        ws.l3Date = ws.dates.wsDate
        // line-1 (l1-prog は未設定のまま)
        ws.d(Cobol.x("", 31) + Cobol.x(ws.t("p_title"), 41) + Cobol.x(ws.t("p_page"), 6) + ws.l1Page, 301)
        ws.l3Cycle = Pic.edit("z9", value: s.sys.int("scycle"), scale: 0)
        ws.y = 1
        ws.l1Page = Pic.edit("z9", value: 1, scale: 0)
        ws.d(Cobol.x(ws.t("p_cycle"), 8), 301)
        ws.d(ws.l3Cycle, 309)
        ws.d(Cobol.x(ws.t("p_h1a"), 48) + Cobol.x(ws.t("p_h1b"), 32), 501)
        ws.d(Cobol.x(ws.t("p_h2a"), 48) + Cobol.x(ws.t("p_h2b"), 32), 601)
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
            ws.d(line6, ws.curs2)
            ws.lin2 += 1
            ws.d(line7, ws.curs2)
            ws.lin += 3
            if notOpen { try GL.hang(s) }
            if ws.lin < GL.lines - 3 { continue }
            ws.d(ws.t("next_screen"), l22 + 1)
            let r = try c.accept(at: l22 + 46, size: 1, color: 6)
            if r == "X" || r == "x" { break }
            ws.lin = 7
            c.display(" ", at: ws.curs, eraseEOS: true)
        }
        c.display(ws.t("type_return"), at: l22 + 1)
        _ = try c.accept(at: l22 + 22, size: 1, color: 2)
        ws.batchFile.close()
    }

    /// gl071b: 転記待ちの G/L バッチの仕訳を借方・貸方・VAT の行へ展開して pretrans.tmp に書く
    static func gl071b(_ ws: WS) throws {
        let s = ws.s
        s.store.writeRaw(GLTrans.prePath(s), [])
        ws.batchFile.open()
        loop: while true {
            var notOpen = false
            switch ws.batchFile.glNext() {
            case .ok(let r): ws.batch = r
            case .miss: break loop
            case .error: notOpen = true
            }
            let b = ws.batch
            if b.int("bcycle") != s.sys.int("scycle") || b.int("batch-status") == 0 || b.int("cleared-status") != 0 || b.int("ledger") != 1 {
                if notOpen { try GL.hang(s) }
                continue
            }
            try preProcess(ws)
            if notOpen { try GL.hang(s) }
        }
        ws.batchFile.close()
    }

    static func preProcess(_ ws: WS) throws {
        let s = ws.s
        ws.pre.setInt("batch", ws.batch.int("batch-nos"))
        // 未オープンの posting-file は at end にならず読み続ける (無限ループ)
        if !GL.postingFile(s).exists { try GL.hang(s) }
        var rrn = 0
        while let n = GL.relNext(s, after: rrn) {
            rrn = n.rrn
            ws.post = Record(GL.postingLayout, bytes: n.data)
            let p = ws.post
            if p.raw("post-key").allSatisfy({ $0 == 0x30 }) { continue }
            if p.int("batch") != ws.batch.int("batch-nos") { continue }
            ws.pre.setInt("batch", p.int("batch"))
            ws.pre.setInt("post", p.int("post-number"))
            ws.pre.set("code", p.str("post-code"))
            ws.pre.set("date", p.str("post-date"))
            ws.pre.set("legend", p.str("post-legend"))
            let side = p.str("post-vat-side")
            func amount(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 10, signed: true) }
            ws.pre.setInt("ac", p.int("post-dr"))
            ws.pre.setInt("pc", p.int("dr-pc"))
            ws.pre.setInt("amount", side == "CR" ? amount(p.int("post-amount") + p.int("vat-amount")) : p.int("post-amount"))
            GLTrans.append(s, GLTrans.prePath(s), ws.pre)
            ws.pre.setInt("ac", p.int("post-cr"))
            ws.pre.setInt("pc", p.int("cr-pc"))
            ws.pre.setInt("amount", -(side == "DR" ? amount(p.int("post-amount") + p.int("vat-amount")) : p.int("post-amount")))
            GLTrans.append(s, GLTrans.prePath(s), ws.pre)
            if p.int("vat-ac") == 0 || p.int("vat-amount") == 0 { continue }
            ws.pre.setInt("ac", p.int("vat-ac"))
            ws.pre.setInt("pc", p.int("vat-pc"))
            ws.pre.setInt("amount", side == "CR" ? -p.int("vat-amount") : p.int("vat-amount"))
            GLTrans.append(s, GLTrans.prePath(s), ws.pre)
        }
    }
}
