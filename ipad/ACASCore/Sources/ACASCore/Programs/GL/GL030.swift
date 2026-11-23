import Foundation

/// general/gl030.cbl: Chart Of Account Utilities (勘定科目表の登録・修正・表示・印刷、Profit Centre/Branch)
enum GL030 {
    static let progName = "GL030 (3.00.04)"

    final class WS {
        let s: Session
        let c: Console
        var file: IndexedFile
        var rec = Record(GL.ledgerLayout)       // ledger-record
        var menu = 0, a = 1, est = 0, y = 0, z = 0
        var lin = 0, cole = 0, lin2 = 0, col2 = 0
        var weError = 0, truth = 0, gateSw = 1
        var seek = " ", aTest = " "
        var check: [Character] = Array("000000") // ledger-check
        var pcCode = "  "
        var codes = [Character](repeating: " ", count: 99) // p-b-codes
        var pcKey = "        "
        var saveS: Int64 = 0, saveType: Int64 = 0, savePlace = " ", saveCode = "  ", saveLedger: Int64 = 0
        var lineCnt = 0, pageNos = 0
        var l1Prog = "", l1Date = "", l3User = "", fill2 = ""
        init(_ s: Session) { self.s = s; c = s.console; file = GL.ledgerFile(s) }
        var curs: Int { lin * 100 + cole }
        var curs2: Int { lin2 * 100 + col2 }
        var pc: String { s.sys.str("p-c") }
        var profitCentres: Bool { pc == "P" }
        var branches: Bool { pc == "B" }
        var revenueOnly: Bool { s.sys.str("p-c-level") == "R" }
        var pc1: Character { Array(pcCode)[0] }
        var pc2: Character { Array(pcCode)[1] }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func t(_ k: String) -> String { s.t("gl030." + k) }
        func head(_ title: String, _ at: Int) {
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            d(GL.zz070(s), 171)
            d(t(title), at)
        }
        var checkNos: Int64 { Int64(String(check)) ?? 0 }
        func setCheck(_ v: Int64) { check = Array(Cobol.z(v, 6)) }
        func sub(_ r: Range<Int>) -> Int { Int(String(check[r])) ?? 0 }
        func setSub(_ r: Range<Int>, _ v: Int) { check.replaceSubrange(r, with: Array(Cobol.z(v, r.count))) }
        var readKey: [UInt8] { rec.raw("ledger-key") }
        /// read ledger-file record invalid key move 255 to we-error
        func read() { if let r = file.read(key: readKey) { rec = r } else { weError = 255 } }
        /// p-c-branches ← ledger-record (999999/00)
        func loadPC() {
            rec.setInt("ledger-nos", 999999); rec.setInt("ledger-pc", 0)
            read()
            if weError == 255 { codes = [Character](repeating: " ", count: 99) }
            else { codes = Array(SJIS.decode(rec.bytes[8..<107])) ; while codes.count < 99 { codes.append(" ") } }
            pcKey = "99999900"; est = 0
            if let i = codes.firstIndex(of: "E") { est = i + 1 }
        }
        func code(_ i: Int) -> Character { (1...99).contains(i) ? codes[i - 1] : " " }
        func setCode(_ i: Int, _ v: Character) { if (1...99).contains(i) { codes[i - 1] = v } }
        func zeroAmounts() { for f in ["ledger-balance", "ledger-last", "ledger-q1", "ledger-q2", "ledger-q3", "ledger-q4"] { rec.setInt(f, 0) } }
    }

    /// 英数字項目から数字項目への MOVE (空白は 0)
    static func num(_ t: String) -> Int { Int(t.trimmingCharacters(in: .whitespaces).filter { $0.isNumber }) ?? 0 }
    static func nAccept(_ ws: WS, _ at: Int, _ size: Int, _ v: Int64, color: UInt8 = 3) throws -> Int64 {
        Cobol.moveNumeric(try ws.c.accept(at: at, size: size, kind: .numeric, initial: Cobol.z(v, size), options: [.update], color: color), digits: size, scale: 0)
    }

    static func run(_ s: Session) throws {
        let ws = WS(s)
        let c = s.console
        while true {
            // menu-input
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            ws.d(ws.t("title"), 128)
            ws.d(GL.zz070(s), 171)
            ws.d(s.sys.str("usera"), 301, 3)
            ws.d(ws.t("select"), 801)
            ws.lin = 10; ws.a = 1
            func displaya() {
                ws.cole = 1; ws.d("(", ws.curs)
                ws.cole = 2; ws.d(String(ws.a % 10), ws.curs)
                ws.cole = 3; ws.d(")", ws.curs)
                ws.cole = 6
            }
            func item(_ k: String) { displaya(); ws.d(ws.t(k), ws.curs); ws.lin += 1; ws.a += 1 }
            if ws.profitCentres { item("m_pc") }
            if ws.branches { item("m_branch") }
            item("m_add")
            item("m_amend")
            if s.sys.str("ledger-2nd-index") == "Y" { item("m_alpha") }
            item("m_display")
            item("m_print")
            if ws.profitCentres { displaya(); ws.d(ws.t("m_rep_pc"), ws.curs) }
            if ws.branches { displaya(); ws.d(ws.t("m_rep_branch"), ws.curs) }
            ws.lin += 3; ws.a += 1
            ws.z = ws.a; ws.a = 9; displaya(); ws.a = ws.z
            ws.d(ws.t("m_exit"), ws.curs)
            ws.menu = Int(Cobol.moveNumeric(try c.accept(at: 843, size: 1, kind: .numeric, color: 6), digits: 1, scale: 0))
            if ws.menu == 9 { return }
            if ws.pc == " " { ws.menu = (ws.menu + 1) % 10 }
            if ws.menu == 1 { try gl030a(ws); continue }
            if ws.menu == 2 { try gl030b(ws); continue }
            if ws.menu == 3 { try gl030c(ws); continue }
            if s.sys.str("ledger-2nd-index") != "Y" { ws.menu = (ws.menu + 1) % 10 }
            if ws.menu == 4 { gl030e(ws); continue }
            if ws.menu == 5 || ws.menu == 6 { try gl030f(ws); continue }
            if ws.menu == 7 { gl030g(ws) }
        }
    }

    // MARK: gl030a — Profit Centre / Branch の設定

    /// gl030a の main 段落: 元帳ファイルが無ければ作成して終端レコード (999999/99) を書く
    static func gl030aMain(_ ws: WS) {
        if ws.file.open() != "00" {
            ws.file.openOutput()
            ws.rec.setRaw("ledger-name", [UInt8](repeating: 0, count: 24))
            ws.rec.setInt("ledger-nos", 999999); ws.rec.setInt("ledger-pc", 99)
            ws.rec.setInt("ledger-type", 0); ws.rec.set("ledger-place", "0"); ws.rec.setInt("ledger-level", 0)
            ws.zeroAmounts()
            ws.file.write(ws.rec)
        }
    }

    static func gl030a(_ ws: WS) throws {
        let c = ws.c
        gl030aMain(ws)
        ws.file.close(); ws.file.open()
        ws.loadPC()
        ws.head(ws.profitCentres ? "a_title_pc" : "a_title_branch", ws.profitCentres ? 127 : 130)
        while true {
            ws.d(ws.t("a_est"), 401)
            ws.d(Cobol.z(ws.est, 2), 424)
            ws.est = Int(try nAccept(ws, 424, 2, Int64(ws.est)))
            if ws.est == 0 { ws.d(ws.t("gl101"), 501); continue }
            break
        }
        ws.setCode(ws.est, "E")
        c.display(" ", at: 501, eraseEOL: true)
        reinput: while true {
            ws.lin = 7; ws.cole = 1; ws.y = 1
            while true {
                ws.lin2 = ws.lin; ws.col2 = ws.cole
                ws.d(Cobol.z(ws.y, 3), ws.curs2)
                ws.col2 += 3; ws.d(". [", ws.curs2)
                ws.col2 += 3; ws.d(String(ws.code(ws.y)), ws.curs2, 3)
                ws.col2 += 1; ws.d("]", ws.curs2)
                ws.lin += 1; ws.y += 1
                if ws.lin < GL.lines - 1 && ws.y < 100 { continue }
                if ws.y < 100 { ws.lin = 7; ws.cole += 11; continue }
                break
            }
            ws.lin = 7; ws.cole = 7; ws.y = 1
            ws.d(ws.t("a_help"), (GL.lines - 1) * 100 + 1)
            loop2: while true {
                if ws.code(ws.y) != "E" {
                    while true {
                        let r = Cobol.upper(try c.accept(at: ws.curs, size: 1, initial: String(ws.code(ws.y)), options: [.update], color: 3))
                        ws.setCode(ws.y, r.first ?? " ")
                        if r == "Q" { ws.setCode(ws.y, " "); break loop2 }
                        if r == " " || r == "Y" { break }
                    }
                }
                ws.lin += 1; ws.y += 1
                if ws.lin < GL.lines - 1 && ws.y < 100 { continue }
                if ws.y < 100 { ws.lin = 7; ws.cole += 11; continue }
                break
            }
            let l23 = (GL.lines - 1) * 100
            c.display(" ", at: l23 + 1, eraseEOL: true)
            ws.d(ws.t("a_ok"), l23 + 1)
            let r = try c.accept(at: l23 + 32, size: 1, initial: "Y", options: [.update], color: 6)
            if r == "N" || r == "n" { continue reinput }
            break
        }
        var bytes = [UInt8](repeating: 0x20, count: GL.ledgerLayout.size)
        bytes.replaceSubrange(0..<107, with: SJIS.encode(ws.pcKey + String(ws.codes), size: 107))
        ws.rec = Record(GL.ledgerLayout, bytes: bytes)
        if ws.weError == 255 { ws.file.write(ws.rec) } else { ws.file.rewrite(ws.rec) }
        ws.weError = 0
        ws.head(ws.profitCentres ? "a_name_pc" : "a_name_branch", ws.profitCentres ? 128 : 131)
        ws.lin = 4; ws.y = 1
        ws.rec.setInt("ledger-pc", 0); ws.rec.setInt("ledger-type", 0); ws.zeroAmounts()
        ws.rec.set("ledger-place", " ")
        loop3: while true {
            if ws.code(ws.y) != " " {
                ws.z = ws.y
                ws.rec.setInt("ledger-nos", 999999); ws.rec.setInt("ledger-pc", Int64(ws.z))
                ws.read()
                if ws.weError == 255 { ws.rec.set("ledger-name", "") }
                while true {
                    ws.cole = 1; ws.d(ws.t("a_code"), ws.curs)
                    ws.cole = 8; ws.d(Cobol.z(ws.y, 3), ws.curs)
                    ws.cole = 11; ws.d(ws.t("a_name"), ws.curs)
                    ws.cole = 45; ws.d("]", ws.curs)
                    ws.cole = 21; ws.d(ws.rec.str("ledger-name"), ws.curs)
                    let name = try c.accept(at: ws.curs, size: 24, initial: ws.rec.str("ledger-name"), options: [.update], color: 3)
                    ws.rec.set("ledger-name", name)
                    let n = Cobol.rtrim(name)
                    if n == "QUIT" || n == "quit" || c.crtStatus == 2005 { break loop3 }
                    if ws.weError == 255 && n.isEmpty { continue }
                    break
                }
                if ws.weError == 255 { ws.file.write(ws.rec) } else { ws.file.rewrite(ws.rec) }
                ws.weError = 0
                ws.lin += 1
            }
            ws.y += 1
            if ws.y > 99 { break }
            if ws.lin < GL.lines - 2 { continue }
            ws.lin = 4; ws.cole = 1
            repeat { c.display(" ", at: ws.curs, eraseEOL: true); ws.lin += 1 } while ws.lin < GL.lines - 2
            ws.lin = 4
        }
        ws.file.close()
    }

    // MARK: 共通段落

    /// ledger-read: ledger-check の勘定が存在するか (truth)。レコード域は読む前の内容へ戻す。
    static func ledgerRead(_ ws: WS) {
        ws.truth = 0
        ws.rec.setInt("ledger-nos", ws.checkNos)
        ws.rec.setInt("ledger-pc", ws.pc2 == "*" ? 0 : Int64(num(ws.pcCode)))
        let dummy = ws.rec
        ws.weError = 0
        ws.read()
        if ws.weError != 255 { ws.truth = 1 }
        if ws.aTest == "D" {
            ws.savePlace = ws.rec.str("ledger-place")
            let t = ws.rec.raw("ledger-type")[0]
            ws.saveType = (0x30...0x39).contains(t) ? Int64(t - 0x30) : 0
        }
        ws.rec = dummy
        if ws.aTest == "D" { ws.rec.setInt("ledger-type", ws.saveType); ws.rec.set("ledger-place", ws.savePlace) }
    }

    /// pc-code-check thru pc-code-check-exit
    static func pcCodeCheck(_ ws: WS) {
        ws.truth = 1
        if ws.pcCode == "  " { ws.pcCode = "00" }
        if ws.pcCode == "**" { return }
        if ws.pcCode >= "00" && ws.pcCode <= "99" { return }
        if ws.pc2 != "*" { ws.truth = 0; return }
        if !(ws.pc1 >= "0" && ws.pc1 <= "9") { ws.truth = 0; return }
        // pc-code-main-check (pc-code2 は必ず "*")
        ws.z = (num(String(ws.pc1)) * 10) % 100
        ws.truth = 0
        var n = 10
        if ws.z == 0 { ws.z = 1; n = 9 }
        for _ in 0..<n {
            if ws.code(ws.z) == "E" || ws.code(ws.z) == "Y" { ws.truth = 1 }
            ws.z += 1
        }
    }

    /// loop-end 〜 addition-end: P/C 指定 (nn / n* / **) に応じて body を各 P/C と 00 に適用する
    static func multi(_ ws: WS, _ body: () throws -> Void) rethrows {
        if ws.pc2 != "*" {
            ws.y = num(ws.pcCode)
            try body()
        } else {
            ws.rec.setInt("ledger-pc", 0); ws.y = 0
            var n: Int
            if ws.pc1 == "*" { ws.y = 1; n = 99 } else {
                ws.y = (num(String(ws.pc1)) * 10) % 1000
                n = 10
                if ws.y == 0 { ws.y = 1; n = 9 }
            }
            for _ in 0..<n {
                if ws.code(ws.y) == "E" || ws.code(ws.y) == "Y" { try body() }
                ws.y += 1
            }
        }
        ws.y = 0
        try body()
    }

    static func headings(_ ws: WS, _ title: String) {
        ws.d(ws.t(title), 129)
        ws.d(ws.t("h_ledger_sub"), 401)
        if ws.profitCentres { ws.d(ws.t("h_pc"), 417) }
        if ws.branches { ws.d(ws.t("h_branch"), 415) }
        ws.d(ws.t("h_name_type"), 423)
        ws.lin = 6
    }

    // MARK: gl030b — 勘定科目の追加

    static func gl030b(_ ws: WS) throws {
        let c = ws.c
        if ws.file.open() != "00" { gl030aMain(ws) }
        ws.file.close(); ws.file.open()
        if ws.profitCentres || ws.branches { ws.loadPC() }
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.s.toDay, 171)
        headings(ws, "b_title")
        let missing = { ws.col2 = 1; ws.d(ws.t("header_missing"), ws.curs2); ws.truth = 1 }
        loop: while true {
            ws.cole = 1; ws.d("[    ]   [  ]", ws.curs)
            if ws.profitCentres || ws.branches { ws.cole = 16; ws.d("[  ]", ws.curs) }
            ws.cole = 23; ws.d("[", ws.curs)
            ws.cole = 48; ws.d("]  [ ]      [ ]      [ ]", ws.curs)
            ws.rec.setInt("ledger-n", 0); ws.rec.setInt("ledger-s", 0)
            acceptLedger: while true {
                ws.cole = 2
                ws.rec.setInt("ledger-n", try nAccept(ws, ws.curs, 4, ws.rec.int("ledger-n")))
                if ws.rec.int("ledger-n") == 0 { break loop }
                ws.lin2 = ws.lin + 1; ws.col2 = 1
                if ws.rec.int("ledger-n") < 1000 { ws.d(ws.t("gl102"), ws.curs2); continue }
                c.display(" ", at: ws.curs2, eraseEOL: true)
                ws.cole = 11
                ws.rec.setInt("ledger-s", try nAccept(ws, ws.curs, 2, ws.rec.int("ledger-s")))
                ws.setCheck(ws.rec.int("ledger-nos"))
                let first = Int64(ws.sub(0..<1))
                if first == ws.s.sys.int("sales-range") || first == ws.s.sys.int("purchase-range") {
                    ws.d(ws.t("invalid_start"), ws.curs2); continue
                }
                if String(ws.check[0..<4]) == "9999" { ws.d(ws.t("reserved"), ws.curs2); continue }
                // accept-pc
                if !ws.profitCentres && !ws.branches {
                    ws.rec.setInt("ledger-pc", 0)
                } else {
                    while true {
                        ws.pcCode = "  "
                        ws.cole = 17
                        ws.pcCode = try c.accept(at: ws.curs, size: 2, initial: ws.pcCode, options: [.update], color: 2)
                        pcCodeCheck(ws)
                        if ws.truth == 0 { ws.col2 = 17; ws.d(ws.t("b_invalid_pc"), ws.curs2); continue }
                        break
                    }
                }
                // accept-name
                ws.cole = 24
                ws.rec.set("ledger-name", try c.accept(at: ws.curs, size: 24, initial: "", options: [.update], color: 3))
                // accept-type
                if ws.sub(4..<6) == 0 {
                    while true {
                        ws.cole = 52
                        ws.rec.setInt("ledger-type", 0)
                        ws.d("0", ws.curs)
                        ws.rec.setInt("ledger-type", try nAccept(ws, ws.curs, 1, 0))
                        let t = ws.rec.int("ledger-type")
                        if t != 0 && t != 1 && t != 9 { ws.col2 = 52; ws.d(ws.t("invalid_type"), ws.curs2); continue }
                        break
                    }
                    // accept-placement
                    var again = false
                    while true {
                        ws.cole = 61
                        c.display(" ", at: ws.curs)
                        if ws.rec.int("ledger-type") != 0 { break }
                        let r = Cobol.upper(try c.accept(at: ws.curs, size: 1, initial: " ", options: [.update], color: 3))
                        ws.rec.set("ledger-place", r)
                        if r < "A" || r > "Z" { ws.col2 = 61; ws.d(ws.t("b_invalid_place"), ws.curs2); continue }
                        if ws.revenueOnly && r > "N" && ws.pcCode != "00" {
                            ws.col2 = 61; ws.d(ws.t("revenue_only"), ws.curs2); again = true; break
                        }
                        // accept-header
                        while true {
                            ws.rec.setInt("ledger-level", 0)
                            ws.cole = 70; ws.col2 = 70
                            c.display(" ", at: ws.curs)
                            ws.rec.setInt("ledger-level", try nAccept(ws, ws.curs, 1, 0))
                            if !(1...4).contains(ws.rec.int("ledger-level")) { ws.d(ws.t("invalid"), ws.curs2); continue }
                            break
                        }
                        break
                    }
                    if again { continue acceptLedger }
                }
                // accept-end
                ws.zeroAmounts()
                if ws.rec.int("ledger-s") != 0 {
                    // detail-check
                    ws.saveS = ws.rec.int("ledger-s")
                    ws.setSub(4..<6, 0)
                    ws.aTest = "D"
                    ledgerRead(ws)
                    ws.aTest = " "
                    ws.setSub(4..<6, Int(ws.saveS)); ws.rec.setInt("ledger-s", ws.saveS)
                    if ws.truth == 0 { missing() } else { ledgerRead(ws) }
                    if ws.rec.int("ledger-type") != 9 { ws.rec.setInt("ledger-type", 1) }
                    ws.rec.setInt("ledger-level", 0)
                } else {
                    // header-check
                    func parent(_ r: Range<Int>, _ level: Int64) {
                        ws.rec.setInt("ledger-level", level)
                        let save = ws.sub(r)
                        ws.setSub(r, 0)
                        ledgerRead(ws)
                        ws.setSub(r, save)
                        if ws.truth == 1 { ledgerRead(ws) } else { missing() }
                    }
                    if ws.sub(1..<4) == 0 { ledgerRead(ws); ws.rec.setInt("ledger-level", 1) }
                    if ws.sub(1..<4) != 0 && ws.sub(2..<4) == 0 { parent(1..<4, 2) }
                    if ws.sub(2..<4) != 0 && ws.sub(3..<4) == 0 { parent(2..<4, 3) }
                    if ws.sub(3..<4) != 0 { parent(3..<4, 4) }
                }
                ws.cole = 52; ws.d(String(ws.rec.int("ledger-type")), ws.curs)
                ws.cole = 70; ws.d(String(ws.rec.int("ledger-level")), ws.curs)
                if ws.truth == 1 { continue }
                break
            }
            // loop-end
            multi(ws) { ws.rec.setInt("ledger-pc", Int64(ws.y % 100)); ws.file.write(ws.rec) }
            ws.lin += 1; ws.cole = 1
            c.display(" ", at: ws.curs, eraseEOL: true)
            c.display(" ", at: (GL.lines - 1) * 100 + 1, eraseEOL: true)
            if ws.lin < GL.lines - 2 { continue }
            ws.lin = 6; ws.cole = 1
            repeat { c.display(" ", at: ws.curs, eraseEOL: true); ws.lin += 1 } while ws.lin < GL.lines - 2
            ws.lin = 6
        }
        ws.file.close()
    }

    // MARK: gl030c — 勘定科目の修正・削除

    static func ledgerRewrite(_ ws: WS) throws {
        ws.rec.setInt("ledger-pc", Int64(ws.y % 100))
        if ws.file.rewrite(ws.rec) != "00" {
            let l23 = (GL.lines - 1) * 100
            ws.d(ws.t("gl104"), l23 + 1, 4)
            _ = try ws.c.accept(at: l23 + 48, size: 1, color: 2)
            ws.file.write(ws.rec)
        }
    }

    static func ledgerDelete(_ ws: WS) {
        ws.rec.setInt("ledger-pc", Int64(ws.y % 100))
        if ws.rec.int("ledger-balance") != 0 {
            ws.truth = 0
            ws.col2 = GL.lines
            ws.d(ws.t("c_denied"), ws.curs2)
            return
        }
        ws.file.delete(key: ws.readKey)
    }

    static func gl030c(_ ws: WS) throws {
        let c = ws.c
        if ws.file.open() != "00" {
            c.display(" ", at: 101)   // display space
            ws.d(ws.t("gl103"), 901)
            return
        }
        ws.file.close(); ws.file.open()
        if ws.profitCentres || ws.branches {
            ws.rec.setInt("ledger-nos", 999999); ws.rec.setInt("ledger-pc", 0)
            ws.read()
            if ws.weError == 255 { ws.codes = [Character](repeating: " ", count: 99) }
            else { ws.codes = Array(SJIS.decode(ws.rec.bytes[8..<107])); while ws.codes.count < 99 { ws.codes.append(" ") } }
        }
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(GL.zz070(ws.s), 171)
        headings(ws, "c_title")
        loop: while true {
            ws.cole = 1; ws.d("[    ]", ws.curs)
            ws.cole = 11; ws.d("[  ]", ws.curs)
            if ws.profitCentres || ws.branches { ws.cole = 16; ws.d("[  ]", ws.curs) }
            ws.cole = 23; ws.d("[", ws.curs)
            ws.cole = 48; ws.d("]  [ ]      [ ]      [ ]", ws.curs)
            var deleted = false
            acceptLedger: while true {
                ws.rec.setInt("ledger-nos", 0)
                ws.cole = 2
                ws.rec.setInt("ledger-n", try nAccept(ws, ws.curs, 4, 0))
                if ws.rec.int("ledger-n") == 0 { break loop }
                ws.cole = 12
                ws.rec.setInt("ledger-s", try nAccept(ws, ws.curs, 2, ws.rec.int("ledger-s")))
                // accept-pc
                while true {
                    ws.lin2 = ws.lin
                    if !(ws.profitCentres || ws.branches) { ws.pcCode = "0 "; break }
                    ws.cole = 17
                    ws.pcCode = try c.accept(at: ws.curs, size: 2, initial: ws.pcCode, options: [.update], color: 3)
                    pcCodeCheck(ws)
                    ws.lin2 += 1; ws.col2 = 17
                    if ws.truth == 0 { ws.d(ws.t("c_invalid_pc"), ws.curs2); continue }
                    break
                }
                // a-test-key
                ws.col2 = 1
                c.display(" ", at: ws.curs2, eraseEOL: true)
                ws.weError = 0
                if ws.pc2 == "*" { ws.aTest = "A"; ws.saveCode = ws.pcCode; ws.pcCode = "00" }
                ws.rec.setInt("ledger-pc", Int64(num(ws.pcCode)))
                ws.read()
                if ws.weError == 255 {
                    ws.col2 = 1; ws.d(Cobol.z(ws.rec.int("ledger-nos"), 6), ws.curs2)
                    ws.col2 = 7; ws.d("/", ws.curs2)
                    ws.col2 = 8; ws.d(Cobol.z(ws.rec.int("ledger-pc"), 2), ws.curs2)
                    ws.col2 = 11; ws.d(ws.t("c_not_exist"), ws.curs2)
                    continue
                }
                if ws.aTest == "A" { ws.pcCode = ws.saveCode; ws.aTest = " " }
                ws.col2 = 24; ws.cole = 24
                ws.d(ws.t("c_delete_hint"), ws.curs2)
                ws.d(ws.rec.str("ledger-name"), ws.curs)
                ws.rec.set("ledger-name", try c.accept(at: ws.curs, size: 24, initial: ws.rec.str("ledger-name"), options: [.update], color: 3))
                if ws.rec.str("ledger-name").hasPrefix("+") {
                    // deletion section
                    multi(ws) { ledgerDelete(ws) }
                    ws.truth = 1
                    deleted = true
                    break
                }
                // accept-type
                while true {
                    ws.col2 = 1
                    c.display(" ", at: ws.curs2, eraseEOL: true)
                    ws.cole = 52; ws.col2 = 52
                    ws.d(String(ws.rec.int("ledger-type")), ws.curs)
                    ws.rec.setInt("ledger-type", try nAccept(ws, ws.curs, 1, ws.rec.int("ledger-type")))
                    let t = ws.rec.int("ledger-type")
                    if t == 0 || t == 1 || t == 9 { break }
                    ws.d(ws.t("invalid_type"), ws.curs2)
                }
                if ws.rec.int("ledger-type") == 0 {
                    // accept-placement
                    while true {
                        ws.cole = 61; ws.col2 = 61
                        let r = Cobol.upper(try c.accept(at: ws.curs, size: 1, initial: ws.rec.str("ledger-place"), options: [.update], color: 3))
                        ws.rec.set("ledger-place", r)
                        if r < "A" || r > "Z" { ws.d(ws.t("c_invalid_place"), ws.curs2); continue }
                        break
                    }
                    if ws.revenueOnly && ws.rec.str("ledger-place") > "N" && ws.rec.int("ledger-pc") != 0 {
                        ws.d(ws.t("revenue_only"), ws.curs2)
                        continue acceptLedger
                    }
                    // accept-header
                    while true {
                        ws.cole = 70; ws.col2 = 70
                        ws.d(String(ws.rec.int("ledger-level")), ws.curs)
                        ws.rec.setInt("ledger-level", try nAccept(ws, ws.curs, 1, ws.rec.int("ledger-level")))
                        if (1...4).contains(ws.rec.int("ledger-level")) { break }
                        ws.d(ws.t("invalid"), ws.curs2)
                    }
                }
                break
            }
            if !deleted { try multi(ws) { try ledgerRewrite(ws) } }
            // addition-end-2
            ws.lin += 1; ws.cole = 1
            c.display(" ", at: ws.curs, eraseEOL: true)
            if ws.lin < GL.lines - 2 { continue }
            ws.lin = 6
            repeat { c.display(" ", at: ws.curs, eraseEOL: true); ws.lin += 1 } while ws.lin < GL.lines - 2
        }
        ws.file.close()
    }

    // MARK: 印刷

    static func computePlacement(_ ws: WS) {
        let p = ws.rec.str("ledger-place")
        let bounds = ["E", "I", "K", "O", "R", "U", "W"]
        ws.z = (bounds.firstIndex { p < $0 } ?? 7) + 1
    }
    static func place(_ ws: WS, _ z: Int) -> String { (1...8).contains(z) ? Cobol.x(ws.t("place\(z)"), 13) : Cobol.x("", 13) }
    static func line1(_ ws: WS) -> String {
        Cobol.x(ws.l1Prog, 14) + Cobol.x("", 28) + Cobol.x(ws.t("p_chart"), 17) + Cobol.x("", 31) + Cobol.x(ws.l1Date, 10)
    }
    static func line3(_ ws: WS, _ user: String) -> String {
        Cobol.x(user, 32) + Cobol.x("", 60) + Cobol.x(ws.t("p_page"), 6) + Pic.edit("z9", value: Int64(ws.pageNos), scale: 0)
    }
    static func bwz(_ pic: String, _ v: Int64, _ scale: Int) -> String {
        v == 0 ? Cobol.x("", Pic.size(pic)) : Pic.edit(pic, value: v, scale: scale)
    }
    /// page-heading (heading: 見出し行、second: 2 行目)
    static func pageHeading(_ ws: WS, second: String, heading: String) {
        ws.pageNos = Int(Int8(truncatingIfNeeded: ws.pageNos + 1))
        if ws.pageNos != 1 { GLPrint.writePage(ws.s, line1(ws)) } else { GLPrint.write(ws.s, line1(ws), after: 1) }
        GLPrint.write(ws.s, second, after: 1)
        GLPrint.write(ws.s, heading, after: 2)
        GLPrint.write(ws.s, "", after: 1)
        ws.lineCnt = 5
    }
    static func fill2(_ ws: WS) -> String {
        ws.profitCentres ? ws.t("p_fill_pc") : (ws.branches ? ws.t("p_fill_branch") : "")
    }
    static func levelFiller(_ ws: WS) -> String {
        var lv = [Character](repeating: " ", count: 10)
        let level = Int(ws.rec.int("ledger-level"))
        ws.z = level
        let i = (level * 2 + 1) % 10
        if i >= 1 { lv[i - 1] = Character(String(level)) }
        return String(lv)
    }

    // gl030e — 名称順の印刷 (元帳に副キーが無いため read key ledger-name は invalid key になり、主キー順に読み進む)
    static func gl030e(_ ws: WS) {
        ws.l1Prog = progName
        if ws.file.open() != "00" { ws.d(ws.t("gl105"), GL.lines * 100 + 1); return }
        ws.head("e_title", 123)
        ws.truth = 0
        GLPrint.open(ws.s)
        let h4 = { Cobol.x(ws.t("p_h_name"), 24) + Cobol.x(ws.t("p_h_level"), 36) + Cobol.x("", 4) + Cobol.x(fill2(ws), 17) + Cobol.x(ws.t("p_h_place"), 19) }
        ws.l1Date = GL.zz070(ws.s)
        ws.pageNos = 0
        ws.l3User = ws.s.sys.str("usera")
        pageHeading(ws, second: line3(ws, ws.l3User), heading: h4())
        ws.rec.setRaw("ledger-name", [UInt8](repeating: 0, count: 24))
        ws.weError = 255
        ws.file.startFirst()
        while let r = ws.file.readNext() {
            ws.rec = r
            if r.int("ledger-n") == 9999 { continue }
            var lv = Cobol.x("", 10), header: Int64 = 0, detail: Int64 = 0
            ws.z = 0
            if r.int("ledger-level") != 0 { lv = levelFiller(ws); header = r.int("ledger-nos") } else { detail = r.int("ledger-nos") }
            computePlacement(ws)
            let line = Cobol.x(r.str("ledger-name"), 24) + lv + "   " + bwz("zzz9.99", header, 2) + Cobol.x("", 7) + bwz("zzz9.99", detail, 2)
                + Cobol.x("", 6) + bwz("bbbbbz9", r.int("ledger-pc"), 0) + Cobol.x("", 10) + place(ws, ws.z) + Cobol.x("", 6)
            GLPrint.write(ws.s, line, after: 1)
            ws.lineCnt += 1
            if ws.lineCnt > Int(ws.s.sys.int("page-lines")) { pageHeading(ws, second: line3(ws, ws.l3User), heading: h4()) }
        }
        GLPrint.close(ws.s)
        ws.file.close()
    }

    // MARK: gl030f — 表示・印刷

    static func secondHead(_ ws: WS) {
        ws.cole = 1; ws.d(ws.t("f_ledger"), ws.curs)
        ws.cole = 11; ws.d(ws.t("f_sub"), ws.curs)
        ws.cole = 18
        if ws.profitCentres { ws.d(ws.t("f_pc"), ws.curs) }
        else if ws.branches { ws.d(ws.t("f_branch"), ws.curs) }
        else { ws.c.display("        ", at: ws.curs) }
        ws.cole = 26; ws.d(ws.t("f_name_type"), ws.curs)
    }

    static func displayChart(_ ws: WS) {
        if ws.truth == 1 { secondHead(ws); return }
        ws.cole = 2; ws.d(Cobol.z(ws.rec.int("ledger-n"), 4), ws.curs)
        ws.cole = 11; ws.d(Cobol.z(ws.rec.int("ledger-s"), 2), ws.curs)
        ws.cole = 20
        if ws.profitCentres || ws.branches { ws.d(Cobol.z(ws.rec.int("ledger-pc"), 2), ws.curs) }
        ws.cole = 25; ws.d(ws.rec.str("ledger-name"), ws.curs)
        var t = ws.rec.int("ledger-type")
        t = t == 9 ? 5 : (t + 1) % 10
        ws.rec.setInt("ledger-type", t)
        ws.cole = 53
        ws.d(Cobol.x((1...5).contains(t) ? ws.t("type\(t)") : ws.t("f_error"), 7), ws.curs)
        if ws.rec.int("ledger-level") != 0 {
            ws.cole = 64; ws.d(String(ws.rec.int("ledger-level")), ws.curs)
            computePlacement(ws)
            ws.cole = 68; ws.d(place(ws, ws.z), ws.curs)
        }
    }

    static func askClear(_ ws: WS) throws {
        let l23 = (GL.lines - 1) * 100
        ws.c.display(ws.t("f_next_screen"), at: l23 + 1, color: 2, eraseEOL: true)
        _ = try ws.c.accept(at: l23 + 41, size: 1, color: 2)
    }

    static func screenClear(_ ws: WS) throws {
        if ws.gateSw == 2 { try askClear(ws) }
        ws.gateSw = 2
        let save = ws.lin
        repeat { ws.cole = 1; ws.c.display(" ", at: ws.curs, eraseEOL: true); ws.lin += 1 } while ws.lin < GL.lines - 1
        ws.lin = save
    }

    static func gl030f(_ ws: WS) throws {
        let c = ws.c
        ws.l1Prog = progName
        if ws.file.open() != "00" {
            c.display(" ", at: 101, eraseEOS: true)
            ws.d(ws.t("gl106"), 901)
            return
        }
        let dHead1 = { ws.head("f_title", 127) }
        dHead1()
        ws.truth = 0
        let l23 = (GL.lines - 1) * 100
        target: while true {
            if ws.menu == 6 { ws.d(ws.t("f_print_out"), 145); printOut(ws); break }
            ws.lin = 3
            try screenClear(ws)
            ws.rec.setInt("ledger-n", 0); ws.rec.setInt("ledger-s", 0)
            ws.d(ws.t("f_start"), 401)
            if ws.profitCentres || ws.branches { ws.d("/  ]", 434) }
            c.display(" ", at: l23 + 1, eraseEOL: true)
            ws.d(ws.t("f_esc"), l23 + 1)
            ws.d(Cobol.z(ws.rec.int("ledger-nos"), 6), 428)
            ws.rec.setInt("ledger-nos", try nAccept(ws, 428, 6, ws.rec.int("ledger-nos")))
            if c.crtStatus == 2005 { ws.seek = "Q"; ws.truth = 0; break }
            ws.rec.setInt("ledger-pc", 0)
            if ws.profitCentres || ws.branches {
                ws.d("00", 435)
                ws.rec.setInt("ledger-pc", try nAccept(ws, 435, 2, 0))
            }
            ws.saveLedger = ws.rec.int("ledger-nos")
            ws.lin = 4; ws.truth = 1; ws.gateSw = 1
            displayChart(ws)
            if !ws.file.start(notLessThan: ws.readKey) { ws.weError = 255 }
            if ws.weError == 0 {
                if let r = ws.file.readNext() { ws.rec = r } else { ws.weError = 255 }
            }
            if ws.weError == 255 { ws.d(ws.t("f_no_match"), 841); continue }
            ws.truth = 0
            ws.lin += 2
            mainLoop: while true {
                ws.d(ws.t("f_prompt"), l23 + 1)
                ws.seek = "I"
                displayChart(ws)
                ws.seek = Cobol.upper(try c.accept(at: l23 + 61, size: 1, initial: ws.seek, options: [.update], color: 3))
                if ws.seek == "Q" { ws.truth = 0; break target }
                while true {
                    // subsid-loop
                    ws.gateSw = 2
                    if let r = ws.file.readNext() { ws.rec = r } else { ws.weError = 255 }
                    if ws.weError == 255 || ws.rec.int("ledger-n") == 9999 { continue target }
                    if ws.seek == "I" && ws.rec.int("ledger-nos") == ws.saveLedger { continue }
                    ws.saveLedger = ws.rec.int("ledger-nos")
                    ws.lin += 1
                    if ws.lin == GL.lines - 2 {
                        try askClear(ws)
                        if c.crtStatus == 2005 { ws.gateSw = 1; continue target }
                        dHead1()
                        ws.lin = 4
                        secondHead(ws)
                        ws.lin = 6
                    }
                    if ws.seek != "C" && ws.seek != "I" { continue mainLoop }
                    displayChart(ws)
                }
            }
        }
        ws.file.close()
    }

    static func printOut(_ ws: WS) {
        GLPrint.open(ws.s)
        let h6 = { Cobol.x(ws.t("p_h_level"), 36) + Cobol.x("", 4) + Cobol.x(fill2(ws), 17) + Cobol.x(ws.t("p_h_place_name"), 43) }
        ws.l1Date = ws.s.toDay
        ws.pageNos = 0
        ws.l3User = ws.s.sys.str("usera")
        pageHeading(ws, second: line3(ws, ws.l3User), heading: h6())
        while true {
            if let r = ws.file.readNext() { ws.rec = r } else { ws.weError = 255 }
            if ws.weError == 255 || ws.rec.int("ledger-n") == 9999 { break }
            let r = ws.rec
            var lv = Cobol.x("", 10), header: Int64 = 0, detail: Int64 = 0, pl = Cobol.x("", 13)
            ws.z = 0
            if r.int("ledger-level") != 0 {
                lv = levelFiller(ws); header = r.int("ledger-nos")
                computePlacement(ws); pl = place(ws, ws.z)
            } else { detail = r.int("ledger-nos") }
            let line = lv + "   " + bwz("zzz9.99", header, 2) + Cobol.x("", 7) + bwz("zzz9.99", detail, 2)
                + Cobol.x("", 6) + bwz("bbbbbz9", r.int("ledger-pc"), 0) + Cobol.x("", 10) + pl + Cobol.x("", 6) + Cobol.x(r.str("ledger-name"), 24)
            GLPrint.write(ws.s, line, after: 1)
            ws.lineCnt += 1
            if ws.lineCnt > Int(ws.s.sys.int("page-lines")) { pageHeading(ws, second: line3(ws, ws.l3User), heading: h6()) }
        }
        GLPrint.close(ws.s)
    }

    // MARK: gl030g — Profit Centre 一覧の印刷

    static func gl030g(_ ws: WS) {
        if ws.file.open() != "00" {
            ws.c.display(" ", at: 101, eraseEOS: true)
            ws.d(ws.t("gl106"), 901)
            return
        }
        ws.head("g_title", 127)
        ws.truth = 0
        ws.loadPC()
        GLPrint.open(ws.s)
        // l11-date へ日付を入れるが、見出しは line-1 を印字する (レガシーどおり)
        ws.pageNos = 0
        let user = ws.s.sys.str("usera")
        let heading = { pageHeading(ws, second: line3(ws, user), heading: Cobol.x(ws.t("p_h_number"), 36)) }
        heading()
        ws.y = 1
        repeat {
            if ws.code(ws.y) != " " {
                ws.rec.setInt("ledger-nos", 999999); ws.rec.setInt("ledger-pc", Int64(ws.y))
                ws.read()
                if ws.weError == 255 { ws.rec.set("ledger-name", "") }
                GLPrint.write(ws.s, Pic.edit("z9", value: ws.rec.int("ledger-pc"), scale: 0) + Cobol.x("", 10) + Cobol.x(ws.rec.str("ledger-name"), 32), after: 1)
                ws.lineCnt += 1
                if ws.lineCnt > Int(ws.s.sys.int("page-lines")) { heading() }
                ws.lin += 1
            }
            ws.y += 1
        } while ws.y < 99
        GLPrint.close(ws.s)
        ws.file.close()
    }
}
