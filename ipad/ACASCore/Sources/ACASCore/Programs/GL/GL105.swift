import Foundation

/// general/gl105.cbl: Ledger Print (整列済みアーカイブ workarc.tmp から勘定別の元帳を印刷)
enum GL105 {
    static let progName = "gl105 (3.00.04)"

    final class WS {
        let s: Session
        let c: Console
        let ledgerFile: IndexedFile
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var arc = Record(GL080.arcLayout, bytes: [UInt8](repeating: 0, count: GL080.arcLayout.size))
        var lineCnt = 0, countx = 0, sheet = 0
        var saveAc: Int64 = 0, savePc: Int64 = 0
        var totDr: Int64 = 0, totCr: Int64 = 0
        var acToPrint: Int64 = 0, pcToPrint: Int64 = 0
        var arcOutName = "workarc.tmp"
        var l3Date = "", l3User = ""
        var l4Ac: Int64 = 0, l4Pc: Int64 = 0, l4Name = ""
        init(_ s: Session) { self.s = s; c = s.console; ledgerFile = GL.ledgerFile(s) }
        func t(_ k: String) -> String { s.t("gl105." + k) }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func bwz(_ pic: String, _ v: Int64, _ scale: Int) -> String { v == 0 ? Cobol.x("", Pic.size(pic)) : Pic.edit(pic, value: v, scale: scale) }
        /// read ledger-file invalid key (未オープンなら invalid key にならない)
        func readLedger() -> Bool {
            switch ledgerFile.glRead(key: ledger.raw("ledger-key")) {
            case .ok(let r): ledger = r; return true
            case .miss: return false
            case .error: return true
            }
        }
    }

    static func run(_ s: Session) throws {
        let ws = WS(s), c = ws.c
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("title"), 135)
        let dates = GLDates(s)
        dates.zz070()
        ws.d(dates.wsDate, 171)
        ws.l3Date = dates.wsDate
        ws.l3User = s.sys.str("usera")
        ws.d(ws.l3User, 301, 3)
        try diskChange(ws)
        c.display(" ", at: 1201, eraseEOS: true)
        ws.ledgerFile.open()
        ws.d(ws.t("all_accounts"), 621)

        enum St { case get1, get2, get3, get4, start }
        var st = St.get1
        while st != .start {
            switch st {
            case .get1:
                let r = try c.accept(at: 648, size: 1, initial: "Y", options: [.update], color: 3).uppercased()
                if r == "Y" { st = .get3 } else if r == "N" { st = .get2 }
            case .get2:
                ws.d(ws.t("enter_account"), 821)
                ws.acToPrint = Cobol.moveNumeric(try c.accept(at: 847, size: 6, kind: .numeric, initial: Cobol.z(ws.acToPrint, 6),
                                                              options: [.update], color: 3), digits: 6, scale: 0)
                if ws.acToPrint == 0 { st = .get1; continue }
                ws.ledger.setInt("ledger-nos", ws.acToPrint)
                ws.ledger.setInt("ledger-pc", 0)
                if !ws.readLedger() {
                    c.display(ws.t("gl118"), at: 854)
                    continue
                }
                c.display(" ", at: 854, eraseEOL: true)
                st = .get3
            case .get3:
                ws.d(ws.t("all_pcs"), 1221)
                let r = try c.accept(at: 1248, size: 1, initial: "Y", options: [.update], color: 3).uppercased()
                if r == "Y" { st = .start } else if r == "N" { st = .get4 }
            case .get4:
                ws.d(ws.t("enter_pc"), 1421)
                ws.pcToPrint = Cobol.moveNumeric(try c.accept(at: 1447, size: 2, kind: .numeric, initial: Cobol.z(ws.pcToPrint, 2),
                                                              options: [.update], color: 3), digits: 2, scale: 0)
                if ws.pcToPrint == 0 { st = .get3; continue }
                if ws.acToPrint == 0 { st = .start; continue }
                ws.ledger.setInt("ledger-pc", ws.pcToPrint)
                if !ws.readLedger() {
                    ws.d(ws.t("gl119"), 1454)
                    continue
                }
                c.display(" ", at: 1454, eraseEOL: true)
                st = .start
            case .start: break
            }
        }

        let recs = GLTrans.readAll(s, ws.arcOutName, GL080.arcLayout)
        GLPrint.open(s)
        // 未オープンの archive は at end にならず読み続ける (無限ループ)
        guard let recs else { try GL.hang(s) }
        for r in recs {
            ws.arc = r
            let ac = r.int("arc-ac"), pc = r.int("arc-pc")
            if ws.acToPrint != 0 {
                if ws.acToPrint < ac { continue }
                if ws.acToPrint > ac { break }
            }
            if ws.pcToPrint != 0 && ws.pcToPrint != pc { continue }
            if ws.saveAc == 0 {
                newAc(ws)
            } else if ac != ws.saveAc || pc != ws.savePc {
                acEnd(ws)
                newAc(ws)
            }
            let amount = r.int("arc-amount")
            if amount > 0 { ws.totDr = Cobol.truncate(ws.totDr + amount, digits: 10, signed: true) }
            else { ws.totCr = Cobol.truncate(ws.totCr + amount, digits: 10, signed: true) }
            let line7 = Pic.edit("zzzz9", value: r.int("arc-batch"), scale: 0) + "/" + Pic.edit("zzzz9bbbbbb", value: r.int("arc-post"), scale: 0)
                + Cobol.x(r.str("arc-code"), 7) + Cobol.x(r.str("arc-date"), 14) + Cobol.x(r.str("arc-legend"), 37)
                + ws.bwz("zzz9.99bb", r.int("arc-c-ac") % 1_000_000, 2) + ws.bwz("z9bbbb", r.int("arc-c-pc"), 0)
                + ws.bwz("zzzzzzz9.99", amount > 0 ? amount : 0, 2) + Cobol.x("", 3) + ws.bwz("zzzzzzz9.99", amount > 0 ? 0 : abs(amount), 2)
            GLPrint.write(s, line7, after: 1)
            ws.lineCnt = (ws.lineCnt + 1) % 100
            if Int64(ws.lineCnt) > s.sys.int("page-lines") { headings(ws) }
        }
        acEnd(ws)
        GLPrint.close(s)
        ws.ledgerFile.close()
    }

    static func newAc(_ ws: WS) {
        let ac = ws.arc.int("arc-ac"), pc = ws.arc.int("arc-pc")
        ws.ledger.setInt("ledger-nos", ac)
        ws.ledger.setInt("ledger-pc", pc)
        if !ws.readLedger() { ws.ledger.set("ledger-name", ws.t("unknown")) }
        ws.l4Ac = ac
        ws.saveAc = ac
        ws.l4Pc = pc; ws.savePc = pc
        ws.l4Name = GL.shown(ws.ledger, "ledger-name")
        ws.sheet = 0
        headings(ws)
    }

    static func headings(_ ws: WS) {
        let s = ws.s
        ws.countx = (ws.countx + 1) % 1000
        ws.sheet = (ws.sheet + 1) % 100
        let line1 = Cobol.x(progName, 54) + Cobol.x(ws.t("p_title"), 70) + Cobol.x(ws.t("p_page"), 5) + Pic.edit("zz9", value: Int64(ws.countx), scale: 0)
        let line3 = Cobol.x(ws.l3User, 122) + Cobol.x(ws.l3Date, 10)
        let line4 = Cobol.x(ws.t("p_account"), 10) + Pic.edit("zzz9.99", value: ws.l4Ac, scale: 2) + Cobol.x(ws.t("p_sep"), 3)
            + ws.bwz("99bbbb", ws.l4Pc, 0) + Cobol.x(ws.l4Name, 98) + Cobol.x(ws.t("p_sheet"), 6) + Pic.edit("z9", value: Int64(ws.sheet), scale: 0)
        if ws.countx != 1 {
            GLPrint.writePage(s, line1)
            GLPrint.write(s, line3, after: 1)
            GLPrint.write(s, line4, after: 1)
            GLPrint.write(s, "", after: 1)
        } else {
            GLPrint.write(s, line1, before: 1)
            GLPrint.write(s, line3, before: 1)
            GLPrint.write(s, line4, before: 1)
        }
        GLPrint.write(s, Cobol.x(ws.t("p_h1a"), 75) + Cobol.x(ws.t("p_h1b"), 57), after: 1)
        GLPrint.write(s, Cobol.x("", 75) + Cobol.x(ws.t("p_h2"), 12), after: 1)
        GLPrint.write(s, "", after: 1)
        ws.lineCnt = 7
    }

    static func acEnd(_ ws: WS) {
        let s = ws.s
        let line8 = Cobol.x("", 90) + Cobol.x(ws.t("p_rule"), 25)
        let line9 = Cobol.x("", 75) + Cobol.x(ws.t("p_balance"), 15) + Pic.edit("zzzzzzz9.99bbb", value: abs(ws.totDr), scale: 2)
            + Pic.edit("zzzzzzz9.99bbbb", value: abs(ws.totCr), scale: 2)
            + ws.bwz("zzzzzzz9.99cr", Cobol.truncate(ws.totDr + ws.totCr, digits: 10, signed: true), 2)
        GLPrint.write(s, line8, after: 2)
        GLPrint.write(s, line9, after: 1)
        GLPrint.write(s, line8, after: 1)
        ws.totDr = 0; ws.totCr = 0
    }

    /// disk-change: 整列済みアーカイブのパスを確認する (9 で抜けても処理は続く)
    static func diskChange(_ ws: WS) throws {
        let s = ws.s, c = ws.c
        ws.arcOutName = GLTrans.archivesPath(s, ws.arcOutName)
        c.display(ws.t("gl115"), at: 1201, color: 2, eraseEOL: true)
        c.display(ws.t("gl114"), at: 1301, color: 2, eraseEOL: true)
        while true {
            let a = Cobol.moveNumeric(try c.accept(at: 1369, size: 2, kind: .numeric), digits: 2, scale: 0)
            if a == 9 { return }
            if a != 0 { continue }
            c.display(ws.t("current_path"), at: 1401, color: 2, eraseEOL: true)
            c.display(ws.arcOutName, at: 1501, color: 2, eraseEOL: true)
            ws.arcOutName = Cobol.rtrim(try c.accept(at: 1501, size: 532, initial: ws.arcOutName, options: [.update], color: 2))
            if ws.arcOutName.isEmpty || ws.arcOutName.hasPrefix(" ") { continue }
            return
        }
    }
}
