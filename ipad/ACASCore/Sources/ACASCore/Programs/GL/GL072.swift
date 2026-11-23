import Foundation

/// general/gl072.cbl: Transaction Posting — Phase 4 (postrans.tmp を元帳へ転記し、転記帳票を印刷)
enum GL072 {
    static let progName = "gl072 (3.00.04)"

    final class WS {
        let s: Session
        let dates: GLDates
        let batchFile: IndexedFile
        let ledgerFile: IndexedFile
        var batch = Record(GL.batchLayout, bytes: [UInt8](repeating: 0, count: GL.batchLayout.size))
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var trans = Record(GLTrans.layout, bytes: [UInt8](repeating: 0, count: GLTrans.layout.size))
        var saveBatch: Int64 = 0, saveLedger: Int64 = 0
        var readLedger = " "
        var lineCnt = 0, y = 0, weError = 0
        var totDr: Int64 = 0, totCr: Int64 = 0
        var l3Desc = Cobol.x("", 32), l3Date = Cobol.x("", 10)
        // line-6
        var l6Account: Int64 = 0, l6Pc: Int64 = 0, l6Balance: Int64 = 0, l6Tran: Int64 = 0
        var l6Date = Cobol.x("", 12), l6Debit: Int64 = 0, l6Credit: Int64 = 0, l6Legend = Cobol.x("", 32)
        init(_ s: Session) { self.s = s; dates = GLDates(s); batchFile = GL.batchFile(s); ledgerFile = GL.ledgerFile(s) }
        func t(_ k: String) -> String { s.t("gl072." + k) }
        var pageLines: Int { Int(s.sys.int("page-lines")) }
        func bwz(_ pic: String, _ v: Int64, _ scale: Int) -> String { v == 0 ? Cobol.x("", Pic.size(pic)) : Pic.edit(pic, value: v, scale: scale) }
        var line6: String {
            bwz("9999.99", l6Account, 2) + Cobol.x("", 6) + bwz("99", l6Pc, 0) + Cobol.x("", 5)
                + bwz("zzzzzzz9.99cr", l6Balance, 2) + bwz("bbbz9", l6Tran, 0) + Cobol.x("", 4) + Cobol.x(l6Date, 12)
                + bwz("zzzzzzz9.99", abs(l6Debit), 2) + Cobol.x("", 4) + bwz("zzzzzzz9.99", abs(l6Credit), 2) + Cobol.x("", 6) + Cobol.x(l6Legend, 32)
        }
        var line7: String { Cobol.x("", 54) + String(repeating: "=", count: 11) + Cobol.x("", 4) + String(repeating: "=", count: 11) }
        func write(_ line: String, after: Int) { GLPrint.write(s, line, after: after) }
        func add8(_ a: Int64, _ b: Int64) -> Int64 { abs(a + b) % 10_000_000_000 }
    }

    static func run(_ s: Session) throws {
        let ws = WS(s)
        s.console.display(ws.t("phase4"), at: 801, color: 2)
        ws.batchFile.open(); ws.ledgerFile.open()
        // 未オープンの post-trans は at end にならず読み続ける (無限ループ)
        guard let recs = GLTrans.readAll(s, GLTrans.postPath(s)) else { GLPrint.open(s); try GL.hang(s) }
        GLPrint.open(s)
        ws.saveBatch = 0; ws.saveLedger = 0
        for r in recs {
            ws.trans = r
            if !r.raw("batch").allSatisfy({ (0x30...0x39).contains($0) }) { continue }
            if r.int("batch") != ws.saveBatch && ws.saveBatch != 0 && ws.weError != 999 {
                endAccount(ws)
                endBatch(ws)
                ws.saveLedger = 0
                headings(ws)
            }
            if ws.saveBatch == 0 {
                ws.saveBatch = r.int("batch")
                headings(ws)
            }
            if ws.weError == 999 { continue }
            let postLedger = r.int("ac") * 100 + r.int("pc")
            if postLedger != ws.saveLedger && ws.saveLedger != 0 {
                endAccount(ws)
                newAccount(ws)
            }
            if ws.saveLedger == 0 { newAccount(ws) }
            ws.saveLedger = postLedger
            ws.l6Tran = r.int("post")
            ws.l6Date = Cobol.x(r.str("date"), 12)
            let amount = r.int("amount")
            if amount > 0 {
                ws.l6Debit = amount
                ws.totDr = ws.add8(ws.totDr, amount)
                ws.l6Credit = 0
            } else {
                ws.l6Credit = amount
                ws.totCr = ws.add8(ws.totCr, -amount)
                ws.l6Debit = 0
            }
            ws.l6Legend = r.str("legend")
            ws.ledger.setInt("ledger-balance", Cobol.truncate(ws.ledger.int("ledger-balance") + amount, digits: 10, signed: true))
            ws.write(ws.line6, after: 1)
            ws.lineCnt += 1
            if ws.lineCnt > ws.pageLines {
                endAccount(ws)
                headings(ws)
                ws.readLedger = "R"
                newAccount(ws)
            }
        }
        endAccount(ws)
        endBatch(ws)
        ws.batchFile.close(); ws.ledgerFile.close()
        GLPrint.close(s)
    }

    /// headings thru headings-end
    static func headings(_ ws: WS) {
        let s = ws.s
        // get-batch
        ws.batch.setInt("ledger", 1)
        ws.saveBatch = ws.trans.int("batch")
        ws.batch.setInt("batch-nos", ws.saveBatch)
        if case .ok(let r) = ws.batchFile.glRead(key: ws.batch.raw("batch-key")) { ws.batch = r }
        ws.l3Desc = Cobol.x(GL.shown(ws.batch, "description"), 32)
        if ws.batch.int("cleared-status") != 0 { ws.weError = 999; ws.saveBatch = 0 } else { ws.weError = 0 }
        if ws.weError == 999 { return }
        ws.dates.zz070()
        ws.l3Date = ws.dates.wsDate
        ws.y = (ws.y + 1) % 100
        let line1 = Cobol.x(progName, 50) + Cobol.x(ws.t("p_title"), 63) + Cobol.x(ws.t("p_page"), 5) + Pic.edit("z9", value: Int64(ws.y), scale: 0)
        let line3 = Cobol.x(ws.t("p_cycle"), 8) + Pic.edit("z9", value: s.sys.int("scycle"), scale: 0) + Cobol.x(ws.t("p_batch"), 18)
            + Pic.edit("zzzz9", value: ws.trans.int("batch"), scale: 0) + Cobol.x("", 10) + Cobol.x(ws.t("p_type"), 12) + ws.l3Desc
            + Cobol.x("", 23) + Cobol.x(ws.l3Date, 10)
        if ws.y != 1 {
            GLPrint.writePage(s, line1)
            ws.write(line3, after: 1)
            ws.write("", after: 1)
        } else {
            GLPrint.write(s, line1, before: 1)
            GLPrint.write(s, line3, before: 1)
        }
        ws.write(Cobol.x(ws.t("p_head"), 120), after: 1)
        ws.write(Cobol.x(ws.t("p_rule1"), 34) + Cobol.x(ws.t("p_rule2"), 5), after: 1)
        ws.lineCnt = 5
    }

    static func endBatch(_ ws: WS) {
        ws.batch.setInt("cleared-status", 1)
        ws.batch.setInt("posted", ws.s.sys.int("run-date"))
        ws.batchFile.rewrite(ws.batch)
    }

    static func endAccount(_ ws: WS) {
        ws.ledgerFile.rewrite(ws.ledger)
        ws.write(ws.line7, after: 1)
        ws.lineCnt += 1
        ws.l6Account = ws.ledger.int("ledger-nos")
        ws.l6Pc = ws.ledger.int("ledger-pc")
        ws.l6Balance = ws.ledger.int("ledger-balance")
        ws.l6Debit = ws.totDr
        ws.l6Credit = ws.totCr
        ws.l6Date = Cobol.x(ws.s.toDay, 12)
        ws.l6Legend = Cobol.x(GL.shown(ws.ledger, "ledger-name"), 32)
        ws.l6Tran = 0
        ws.write(ws.line6, after: 1)
        ws.write(ws.line7, after: 1)
        ws.write("", after: 1)
        ws.lineCnt += 3
    }

    static func newAccount(_ ws: WS) {
        ws.ledger.setInt("ledger-nos", ws.trans.int("ac"))
        ws.ledger.setInt("ledger-pc", ws.trans.int("pc"))
        if ws.readLedger != "R" {
            if case .ok(let r) = ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) { ws.ledger = r }
            ws.totDr = 0; ws.totCr = 0
        }
        ws.l6Account = ws.ledger.int("ledger-nos")
        ws.l6Pc = ws.ledger.int("ledger-pc")
        ws.l6Balance = ws.ledger.int("ledger-balance")
        ws.l6Debit = 0; ws.l6Credit = 0
        ws.dates.zz070()
        ws.l6Date = Cobol.x(ws.dates.wsDate, 12)
        if ws.readLedger != "R" {
            let bal = ws.ledger.int("ledger-balance")
            if bal > 0 {
                ws.l6Debit = bal
                ws.totDr = ws.add8(ws.totDr, bal)
            } else {
                ws.l6Credit = bal
                ws.totCr = ws.add8(ws.totCr, bal)
            }
        }
        ws.l6Legend = Cobol.x(ws.t("brought_forward"), 32)
        ws.l6Tran = 0
        ws.readLedger = " "
        ws.write(ws.line6, after: 2)
        ws.lineCnt += 2
        ws.l6Balance = 0
    }
}
