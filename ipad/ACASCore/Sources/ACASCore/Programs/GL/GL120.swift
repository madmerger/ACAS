import Foundation

/// general/gl120.cbl: P&L and Balance Sheet (元帳を第 1 階層で集計して final.dat を作り、損益計算書・貸借対照表を印刷)
enum GL120 {
    static let progName = "gl120 (3.00.04)"

    static let finalLayout = Layout("final-record", [
        ("l-place", .x(1)),
        ("l-nos", .n9(digits: 6, scale: 0, signed: false)),
        ("l-pc", .n9(digits: 2, scale: 0, signed: false)),
        ("l-name", .x(24)),
        ("l-balance", .comp3(digits: 10, scale: 2, signed: true)),
        ("l-last", .comp3(digits: 10, scale: 2, signed: true)),
    ])
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let alphaNos = Array("11112222334444555666778888").map { Int(String($0))! }

    final class WS {
        let s: Session
        var lDr = [Int64](repeating: 0, count: 6), lCr = [Int64](repeating: 0, count: 6)
        var store = [Int64](repeating: 0, count: 6)
        var storePlace = " ", storeName = Cobol.x("", 30)
        var totDr: Int64 = 0, totCr: Int64 = 0
        var totalThis: Int64 = 0, totalLast: Int64 = 0, runThis: Int64 = 0, runLast: Int64 = 0
        var gpThis: Int64 = 0, gpLast: Int64 = 0, npThis: Int64 = 0, npLast: Int64 = 0, netThis: Int64 = 0, netLast: Int64 = 0
        var xx = 0, a = 0, weError = 0
        var datePl = "", l3Date = "", l11Name = Cobol.x("", 66)
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var final = Record(GL120.finalLayout, bytes: [UInt8](repeating: 0, count: GL120.finalLayout.size))
        let finalFile: IndexedFile
        init(_ s: Session) {
            self.s = s
            finalFile = IndexedFile(s.store, path: s.ledgers + "final.dat", layout: GL120.finalLayout, keyOffset: 0, keyLength: 9)
        }
        func t(_ k: String) -> String { s.t("gl120." + k) }
        func cr(_ v: Int64) -> String { Pic.edit("zzzzzzz9.99cr", value: v, scale: 2) }
        func crBwz(_ v: Int64) -> String { v == 0 ? Cobol.x("", 13) : cr(v) }
        func line7(_ name: String, _ this: Int64, _ last: Int64) -> String {
            Cobol.x("", 20) + Cobol.x(name, 30) + cr(this) + Cobol.x("", 27) + crBwz(last)
        }
        func line11(_ this: Int64, _ last: Int64) -> String { Cobol.x(l11Name, 66) + cr(this) + Cobol.x("", 27) + crBwz(last) }
        var line0: String { Cobol.x(s.sys.str("usera"), 32) }
        var line5: String { Cobol.x("", 50) + Cobol.x(t("p_this_year"), 40) + Cobol.x(t("p_last_year"), 28) }
        var line8: String { Cobol.x("", 50) + String(repeating: "=", count: 11) + Cobol.x("", 29) + String(repeating: "=", count: 11) }
        var line10: String { Cobol.x("", 66) + String(repeating: "=", count: 11) + Cobol.x("", 29) + String(repeating: "=", count: 11) }
        func w(_ line: String, _ after: Int) { GLPrint.write(s, line, after: after) }
    }

    static func u(_ v: Int64) -> Int64 { abs(v) % 10_000_000_000 }
    static func sg(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 10, signed: true) }

    static func run(_ s: Session) throws {
        let ws = WS(s), c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(ws.t("title"), at: 131, color: 2)
        let dates = GLDates(s)
        dates.zz070()
        let today = dates.wsDate
        ws.l3Date = today; ws.datePl = today
        c.display(today, at: 171, color: 2)
        while true {
            c.display(ws.t("enter_date"), at: 521, color: 2)
            c.display("]", at: 567, color: 2)
            ws.datePl = try c.accept(at: 557, size: 10, initial: ws.datePl, options: [.update], color: 3)
            if Cobol.rtrim(ws.datePl).isEmpty { return }
            // 入力した日付は ws-date で上書きされる (ソースのまま)
            ws.datePl = dates.wsDate
            let test = dates.zz050(ws.datePl)
            if dates.uBin == 0 { continue }
            ws.l3Date = test; ws.datePl = test
            c.display(ws.t("ok_to_continue"), at: 721, color: 2)
            c.display("[Y]", at: 746, color: 2)
            let r = try c.accept(at: 747, size: 1, initial: "Y", options: [.update], color: 3)
            if r == "N" || r == "n" { continue }
            break
        }
        let ledgerFile = GL.ledgerFile(s)
        if !s.store.exists(ledgerFile.path) {
            c.display(ws.t("gl106"), at: 901, color: 4)
            c.display(ws.t("gl012"), at: 1001, color: 2)
            _ = try c.accept(at: 1026, size: 1)
            return
        }
        ledgerFile.open()
        ws.finalFile.openOutput()

        while true {
            switch ledgerFile.glNext() {
            case .ok(let r): ws.ledger = r
            case .miss: ws.weError = 255
            case .error: break
            }
            let nos = ws.ledger.int("ledger-nos"), level = ws.ledger.int("ledger-level")
            if ws.weError == 255 || nos / 100 == 9999 {
                rollUp(ws, 5)
                total(ws, 4); total(ws, 3); total(ws, 2); total1(ws)
                break
            }
            if nos != ws.store[5] && ws.store[5] != 0 {
                rollUp(ws, 5)
                ws.lCr[5] = 0; ws.lDr[5] = 0
                if level == 0 { ws.store[5] = nos }
            }
            if nos == ws.store[4] || nos == ws.store[3] || nos == ws.store[2] || nos == ws.store[1] { continue }
            if level == 4 && ws.store[4] == 0 { ws.store[4] = nos; continue }
            if level == 4 { total(ws, 4); ws.store[4] = nos; continue }
            if level == 3 && ws.store[3] == 0 { ws.store[3] = nos; continue }
            if level == 3 { total(ws, 4); total(ws, 3); ws.store[3] = nos; continue }
            if level == 2 && ws.store[2] == 0 { ws.store[2] = nos; continue }
            if level == 2 { total(ws, 4); total(ws, 3); total(ws, 2); ws.store[2] = nos; continue }
            if level == 1 {
                if ws.store[1] != 0 { total(ws, 4); total(ws, 3); total(ws, 2); total1(ws) }
                ws.store[1] = nos
                ws.storePlace = GL.shown(ws.ledger, "ledger-place")
                ws.storeName = Cobol.x(GL.shown(ws.ledger, "ledger-name"), 30)
                continue
            }
            let bal = ws.ledger.int("ledger-balance")
            if nos == ws.store[5] {
                if bal < 0 { ws.lCr[5] = u(ws.lCr[5] - bal) } else { ws.lDr[5] = u(ws.lDr[5] + bal) }
                continue
            }
            if bal < 0 { ws.lCr[5] = u(bal) } else { ws.lDr[5] = u(bal) }
            ws.store[5] = nos
        }

        ws.finalFile.close(); ledgerFile.close()
        GLPrint.open(s)
        ws.finalFile.open()
        ws.w(ws.line0, 1)
        ws.w(Cobol.x("", 32) + Cobol.x(ws.t("p_pl_title"), 43) + Cobol.x(ws.datePl, 10), 2)
        ws.w(Cobol.x("", 33) + String(repeating: "*", count: 52), 1)
        ws.w(ws.line5, 3)
        ws.storePlace = " "
        while let rec = ws.finalFile.readNext() {
            ws.final = rec
            if ws.final.str("l-place") != ws.storePlace { placeChange(ws) }
            if ws.a == 1 || ws.a == 3 || ws.a == 5 {
                ws.final.setInt("l-balance", -ws.final.int("l-balance"))
                ws.final.setInt("l-last", -ws.final.int("l-last"))
            }
            let bal = ws.final.int("l-balance"), last = ws.final.int("l-last")
            ws.totalThis = sg(ws.totalThis + bal)
            ws.totalLast = sg(ws.totalLast + last)
            ws.w(ws.line7(ws.final.str("l-name"), bal, last), 1)
        }
        // main-end
        ws.w(ws.line7(ws.t("net_profit"), ws.npThis, ws.npLast), 1)
        ws.runThis = sg(ws.runThis + ws.npThis)
        ws.runLast = sg(ws.runLast + ws.npLast)
        ws.w(ws.line10, 2)
        ws.w(ws.line11(ws.runThis, ws.runLast), 1)
        ws.w(ws.line10, 1)
        GLPrint.close(s)
        ws.finalFile.close()
    }

    /// detail-print / total4-print / total3-print / total2-print の集計 (上位の階層、無ければ総合計へ)
    static func rollUp(_ ws: WS, _ level: Int) {
        var parent = level - 1
        while parent >= 1 && ws.store[parent] == 0 { parent -= 1 }
        if parent >= 1 {
            ws.lDr[parent] = u(ws.lDr[parent] + ws.lDr[level])
            ws.lCr[parent] = u(ws.lCr[parent] + ws.lCr[level])
        } else if ws.lDr[level] > ws.lCr[level] {
            ws.totDr = u(u(ws.totDr + ws.lDr[level]) - ws.lCr[level])
        } else {
            ws.totCr = u(u(ws.totCr + ws.lCr[level]) - ws.lDr[level])
        }
        if level == 5 { ws.lDr[5] = 0; ws.lCr[5] = 0 }
    }

    static func total(_ ws: WS, _ level: Int) {
        rollUp(ws, level)
        ws.store[level] = 0; ws.lDr[level] = 0; ws.lCr[level] = 0
    }

    /// total1-print: 第 1 階層の合計を final-file へ書く (キー重複は無視される)
    static func total1(_ ws: WS) {
        ws.final.set("l-place", ws.storePlace)
        ws.final.setInt("l-nos", ws.store[1])
        ws.final.setInt("l-pc", 0)
        ws.final.set("l-name", ws.storeName)
        ws.final.setInt("l-balance", sg(ws.lDr[1] - ws.lCr[1]))
        ws.final.setInt("l-last", 0)
        _ = ws.finalFile.write(ws.final)
        ws.store[1] = 0; ws.lDr[1] = 0; ws.lCr[1] = 0
    }

    static func placeChange(_ ws: WS) {
        let place = ws.final.str("l-place")
        // search place-table (at end 無し: 見つからなければ表の外 = alpha-names の先頭 "S" を数字として読む)
        if let j = alphabet.firstIndex(of: Character(place.isEmpty ? " " : place)) { ws.a = alphaNos[j] } else { ws.a = 3 }
        ws.storePlace = place
        if ws.a != ws.xx && ws.xx != 0 { numberChange(ws) }
        if ws.a != ws.xx {
            ws.w(Cobol.x(ws.t("place\(ws.a)"), 24), 1)
            ws.xx = ws.a
            ws.totalThis = 0; ws.totalLast = 0
        }
    }

    static func numberChange(_ ws: WS) {
        let line9 = Cobol.x("", 50) + ws.cr(ws.totalThis) + Cobol.x("", 3) + ws.cr(ws.totalThis) + Cobol.x("", 11)
            + ws.crBwz(ws.totalLast) + Cobol.x("", 3) + ws.crBwz(ws.totalLast)
        ws.w(ws.line8, 2)
        ws.w(line9, 1)
        ws.w(ws.line8, 1)
        if ws.xx == 1 || ws.xx == 3 || ws.xx == 5 {
            ws.runThis = sg(ws.runThis + ws.totalThis); ws.runLast = sg(ws.runLast + ws.totalLast)
        } else {
            ws.runThis = sg(ws.runThis - ws.totalThis); ws.runLast = sg(ws.runLast - ws.totalLast)
        }
        var this: Int64 = 0, last: Int64 = 0
        switch ws.a {
        case 3:
            ws.l11Name = Cobol.x(ws.t("gross_profit"), 66)
            this = ws.runThis; last = ws.runLast
            ws.gpThis = this; ws.gpLast = last
        case 5:
            ws.l11Name = Cobol.x(ws.t("net_profit"), 66)
            ws.npThis = sg(ws.runThis + ws.gpThis); ws.npLast = sg(ws.runLast + ws.gpLast)
            this = ws.npThis; last = ws.npLast
        case 8:
            ws.l11Name = Cobol.x(ws.t("net_current_value"), 66)
            this = ws.runThis; last = ws.runLast
        default: return
        }
        ws.w(ws.line10, 2)
        ws.w(ws.line11(this, last), 1)
        if ws.a == 5 {
            ws.w(ws.line10, 1)
            // b-heading
            ws.w(ws.line0, 1)
            ws.w(Cobol.x("", 42) + Cobol.x(ws.t("p_bs_title"), 22) + Cobol.x(ws.l3Date, 10), 2)
            ws.w(Cobol.x("", 44) + String(repeating: "*", count: 30), 1)
            ws.w(ws.line5, 3)
            ws.netThis = ws.runThis; ws.netLast = ws.runLast
        } else {
            ws.w("", 2)
        }
        ws.runThis = 0; ws.runLast = 0
    }
}
