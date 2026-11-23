import Foundation

/// general/gl050.cbl: Transaction Entry Functions (バッチ登録・仕訳入力)
enum GL050 {
    static let progName = "gl050 (3.00.03)"
    static let esc = 2005, pgUp = 2001, pgDn = 2002, keyUp = 2003, keyDown = 2004

    /// wspint.cob posting-array (occurs 11)。添字 12 まで使われるため (レガシーの添字超過)、連続領域として持つ。
    struct PostingArray {
        var b = [UInt8](repeating: 0x20, count: 990) + [UInt8](repeating: 0, count: 10)
        static let code = (0, 2), date = (22, 10), dr = (132, 6), drPc = (198, 2), cr = (220, 6), crPc = (286, 2)
        static let amount = (308, 10), legend = (418, 32), vatAc = (770, 6), vatPc = (836, 2), vatSide = (858, 2), vatAmount = (880, 10)
        func str(_ f: (Int, Int), _ i: Int) -> String {
            let o = f.0 + (i - 1) * f.1
            return SJIS.decode(b[o..<(o + f.1)])
        }
        mutating func set(_ f: (Int, Int), _ i: Int, _ v: String) {
            let o = f.0 + (i - 1) * f.1
            b.replaceSubrange(o..<(o + f.1), with: SJIS.encode(v, size: f.1))
        }
        func num(_ f: (Int, Int), _ i: Int) -> Int64 {
            let o = f.0 + (i - 1) * f.1
            var v: Int64 = 0, neg = false
            for (k, c) in b[o..<(o + f.1)].enumerated() {
                if k == f.1 - 1 && (0x70...0x79).contains(c) { neg = true }
                v = v * 10 + Int64(min(c & 0x0f, 9))
            }
            return neg ? -v : v
        }
        mutating func setNum(_ f: (Int, Int), _ i: Int, _ v: Int64, signed: Bool = false) {
            let o = f.0 + (i - 1) * f.1
            var d = Array(Cobol.z(abs(v) % Cobol.pow10(f.1), f.1).utf8)
            if signed && v < 0 { d[f.1 - 1] += 0x40 }
            b.replaceSubrange(o..<(o + f.1), with: d)
        }
    }

    final class WS {
        let s: Session
        let c: Console
        let batchFile: IndexedFile
        let ledgerFile: IndexedFile
        var batch = Record(GL.batchLayout, bytes: [UInt8](repeating: 0, count: GL.batchLayout.size))
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var post = Record(GL.postingLayout, bytes: [UInt8](repeating: 0, count: GL.postingLayout.size))
        var arr = PostingArray()
        var a = 0, saveA = 0, v = 0, w = 0, y = 0, z = 0
        var truth = 0, weError = 0, vatFlag = 0, vatFlag2 = 0
        var lin = 0, cole = 0, lin2 = 0, col2 = 0
        var wsDate = Cobol.x("", 10)
        var vatRate: Int64 = 0
        var escapeCode = " "
        var accountIn: Int64 = 0, arrayPc: Int64 = 0, arrayVat = " "
        var codes = [Character](repeating: " ", count: 99)
        var rrn = 0
        var scrAcc = Array("0000.00"), scr8 = Array("00000000.00"), scr9 = Array("000000000.00")
        var exitProgram = false
        init(_ s: Session) {
            self.s = s; c = s.console
            batchFile = GL.batchFile(s); ledgerFile = GL.ledgerFile(s)
        }
        var curs: Int { lin * 100 + cole }
        var curs2: Int { lin2 * 100 + col2 }
        func setCurs2(_ v: Int) { lin2 = (v / 100) % 100; col2 = v % 100 }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func t(_ k: String) -> String { s.t("gl050." + k) }
        var pcOn: Bool { ["P", "B"].contains(s.sys.str("p-c")) }
        var autoVat: Bool { s.sys.str("vat") == "Y" }
        var preserveBatch: Bool { s.sys.str("batch-id") == "Y" }
        var status: Int { c.crtStatus }
    }

    static func digits(_ a: ArraySlice<Character>) -> Int64 { a.reduce(0) { $0 * 10 + Int64($1.wholeNumberValue ?? 0) } }
    static func fill(_ buf: inout [Character], _ r: Range<Int>, _ v: Int64) { buf.replaceSubrange(r, with: Array(Cobol.z(v % Cobol.pow10(r.count), r.count))) }
    static func nAccept(_ ws: WS, _ at: Int, _ size: Int, _ v: Int64, update: Bool = true, color: UInt8 = 3) throws -> Int64 {
        Cobol.moveNumeric(try ws.c.accept(at: at, size: size, kind: .numeric, initial: Cobol.z(v, size), options: update ? [.update] : [], color: color), digits: size, scale: 0)
    }

    /// accept-account: 9(4).99
    static func acceptAccount(_ ws: WS) throws -> Int64 {
        fill(&ws.scrAcc, 0..<4, 0); fill(&ws.scrAcc, 5..<7, 0)
        ws.d(String(ws.scrAcc), ws.curs2, 3)
        ws.scrAcc = Array(try ws.c.accept(at: ws.curs2, size: 7, initial: String(ws.scrAcc), options: [.update], color: 3))
        return digits(ws.scrAcc[0..<4]) * 100 + digits(ws.scrAcc[5..<7])
    }
    /// accept-money8s: 9(8).99
    static func acceptMoney8s(_ ws: WS) throws -> Int64 {
        fill(&ws.scr8, 0..<8, 0); fill(&ws.scr8, 9..<11, 0)
        ws.d(String(ws.scr8), ws.curs2, 3)
        ws.scr8 = Array(try ws.c.accept(at: ws.curs2, size: 11, initial: String(ws.scr8), options: [.update], color: 3))
        return digits(ws.scr8[0..<8]) * 100 + digits(ws.scr8[9..<11])
    }
    /// accept-money8s2: 既存値を初期値に入力
    static func acceptMoney8s2(_ ws: WS, _ amt: Int64) throws -> Int64 {
        fill(&ws.scr8, 9..<11, amt % 100); fill(&ws.scr8, 0..<8, amt / 100)
        ws.scr8 = Array(try ws.c.accept(at: ws.curs2, size: 11, initial: String(ws.scr8), options: [.update], color: 3))
        return digits(ws.scr8[0..<8]) * 100 + digits(ws.scr8[9..<11])
    }
    /// accept-money9: 9(9).99
    static func acceptMoney9(_ ws: WS) throws -> Int64 {
        fill(&ws.scr9, 0..<9, 0); fill(&ws.scr9, 10..<12, 0)
        ws.d(String(ws.scr9), ws.curs2, 3)
        ws.scr9 = Array(try ws.c.accept(at: ws.curs2, size: 12, initial: String(ws.scr9), options: [.update], color: 3))
        return digits(ws.scr9[0..<9]) * 100 + digits(ws.scr9[10..<12])
    }

    static func run(_ s: Session) throws {
        let ws = WS(s)
        let c = s.console
        // init01
        if ws.batchFile.open() != "00" {
            ws.batchFile.openOutput()
            // initialize batch-record
            var r = Record(GL.batchLayout)
            for f in ["ledger", "batch-nos", "items", "batch-status", "cleared-status", "bcycle", "entered", "proofed", "posted", "stored",
                      "input-gross", "input-vat", "actual-gross", "actual-vat", "bdefault", "batch-def-ac", "batch-def-pc", "batch-start"] { r.setInt(f, 0) }
            for f in ["description", "convention", "batch-def-code", "batch-def-vat"] { r.set(f, "") }
            r.setInt("ledger", 9); r.setInt("batch-nos", 99999); r.setInt("bcycle", 99)
            ws.batch = r
            ws.batchFile.write(r)
        }
        ws.batchFile.close(); ws.batchFile.open()
        if !GL.postingFile(s).exists {
            // open output posting-file; initialize posting-record; write (rrn = 0 のため書かれない)
            s.store.writeRaw(s.ledgers + "posting.dat", [])
            var p = Record(GL.postingLayout)
            for f in ["batch", "post-number", "post-dr", "dr-pc", "post-cr", "cr-pc", "post-amount", "vat-ac", "vat-pc", "vat-amount"] { p.setInt(f, 0) }
            for f in ["post-code", "post-date", "post-legend", "post-vat-side"] { p.set(f, "") }
            ws.post = p
            GL.relWrite(s, ws.rrn, p.bytes)
        }
        while true {
            // menu-input
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            ws.d(ws.t("title"), 127)
            ws.wsDate = GL.zz070(s)
            ws.d(ws.wsDate, 171)
            ws.d(s.sys.str("usera"), 301)
            ws.d(ws.t("select"), 801)
            ws.a = 1
            ws.d(ws.t("opt1"), 1001)
            ws.d(ws.t("opt9"), 1301)
            let menu = try nAccept(ws, 843, 1, 1, color: 6)
            if menu == 9 { break }
            if menu != 1 { continue }
            // get-next-batch
            ws.batch.setInt("ledger", 1)
            ws.batch.setInt("batch-nos", s.sys.int("next-batch"))
            s.sys.setInt("next-batch", s.sys.int("next-batch") + 1)
            try gl050a(ws)
            if ws.exitProgram { return }
            if ws.batch.int("bdefault") == 0 { break }
            try gl050b(ws)
            // write-next-batch
            if ws.z == 9 { s.sys.setInt("next-batch", s.sys.int("next-batch") - 1) } else { ws.batchFile.write(ws.batch) }
        }
        ws.batchFile.close()
    }

    // MARK: 既定勘定の表示

    static func gl020cShow(_ ws: WS) throws {
        ws.c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("show_title"), 126)
        ws.d(ws.wsDate, 171)
        ws.d(ws.s.sys.str("usera"), 301)
        inputHeadings(ws)
        ws.d(ws.t("end_listing"), 2301)
        _ = try ws.c.accept(at: 2379, size: 1, color: 6)
    }

    static func inputHeadings(_ ws: WS) {
        let s = ws.s
        ws.d(ws.t("h_acnos"), 504); ws.d(ws.t("h_codevat"), 533)
        ws.d(ws.t("h_acnos"), 544); ws.d(ws.t("h_codevat"), 573)
        func each(_ body: () -> Void) {
            ws.lin = 7; ws.w = 1; ws.cole = 1
            while true {
                body()
                ws.w += 1
                if ws.w > 32 { break }
                if ws.w == 17 { ws.lin = 6; ws.cole = 41 }
                ws.lin += 1
            }
        }
        each {
            ws.c.display(Cobol.z(ws.w, 2), at: ws.curs)
            ws.setCurs2(ws.curs + 2)
            ws.d("[       ]", ws.curs2)
            ws.col2 += 30
            ws.d("[  ] [ ]", ws.curs2)
        }
        each {
            ws.setCurs2(ws.curs + 3)
            let acs = GL.defAcs(s, ws.w)
            ws.d(Cobol.z(acs / 100, 4) + "." + Cobol.z(acs % 100, 2), ws.curs2, 3)
            if acs != 0 {
                // get-description (a ではなく w を使う段落)
                ws.weError = 0
                ws.ledger.setInt("ledger-nos", acs); ws.ledger.set("ledger-pc", "00")
                switch ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) {
        case .ok(let r): ws.ledger = r
        case .miss: ws.weError = 255
        case .error: break
        }
                if ws.weError != 255 {
                    ws.setCurs2(ws.curs + 12)
                    ws.d(ws.ledger.str("ledger-name"), ws.curs2, 3)
                    ws.col2 += 20
                    ws.d("[  ] ", ws.curs2)
                }
            }
            ws.setCurs2(ws.curs + 33)
            ws.d(GL.defCodes(s, ws.w), ws.curs2, 3)
            ws.col2 += 5
            ws.d(GL.defVat(s, ws.w), ws.curs2, 3)
        }
        ws.w = 1; ws.cole = 1; ws.lin = 7
    }

    // MARK: gl050a — バッチの設定

    /// gl050a の get-description: def-acs (a) の勘定を読み truth を設定
    static func getDescription(_ ws: WS) {
        ws.weError = 0
        ws.ledger.setInt("ledger-nos", GL.defAcs(ws.s, ws.a))
        ws.ledger.setInt("ledger-pc", ws.truth == 0 ? 0 : ws.batch.int("batch-def-pc"))
        switch ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) {
        case .ok(let r): ws.ledger = r
        case .miss: ws.weError = 255
        case .error: break
        }
        ws.truth = ws.weError == 255 ? 0 : 1
    }

    static func batchOutline(_ ws: WS) {
        let sp = Cobol.x("", 44)
        for l in 16...23 { ws.c.display(sp, at: l * 100 + 1) }
        ws.lin = 15
        ws.d(String(repeating: "*", count: 46), 1501)
        ws.d(String(repeating: "*", count: 46), 2301)
    }

    static func gl050a(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        ws.ledgerFile.open()
        if ws.pcOn {
            ws.ledger.setInt("ledger-nos", 999999); ws.ledger.set("ledger-pc", "00")
            switch ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) {
            case .ok(let r): ws.ledger = r
            case .error: break
            case .miss:
                c.display(ws.t("gl107"), at: 101, color: 4, eraseEOS: true)
                c.display(ws.t("gl010"), at: 211)
                _ = try c.accept(at: 234, size: 1)
                ws.ledgerFile.close()
                ws.exitProgram = true
                return
            }
            ws.codes = Array(SJIS.decode(ws.ledger.bytes[8..<107]))
            while ws.codes.count < 99 { ws.codes.append(" ") }
        }
        enum St { case initDone, defIn, postIn, defaultPc, defDate, cycleIn, itemsIn, grossIn, vatIn, descIn }
        var st = St.initDone
        var tranDate = Cobol.x("", 8)
        var convention2 = "CR"
        loop: while true {
            switch st {
            case .initDone:
                c.display(progName, at: 101, color: 2, eraseEOS: true)
                ws.d(ws.t("a_title"), 126)
                ws.d(ws.wsDate, 171)
                if ws.preserveBatch {
                    batchOutline(ws)
                    repeat {
                        ws.lin += 1
                        ws.cole = 1; ws.d("*", ws.curs)
                        ws.cole = 46; ws.d("*", ws.curs)
                    } while ws.lin < 22
                    ws.d(ws.t("a_batch_data"), 1618)
                }
                // help-outline thru h-o-data
                ws.lin = 15
                ws.d(String(repeating: "+", count: 31), 1550)
                ws.d(String(repeating: "+", count: 31), 2350)
                repeat {
                    ws.lin += 1
                    ws.cole = 50; ws.d("+", ws.curs)
                    ws.cole = 80; ws.d("+", ws.curs)
                } while ws.lin < 22
                ws.d(ws.t("a_help_data"), 1661)
                ws.d(ws.t("a_sel_default"), 401)
                ws.d(ws.t("a_sel_convention"), 701)
                if s.sys.str("p-c") == "P" { ws.d(ws.t("a_sel_pc"), 1001) }
                if s.sys.str("p-c") == "B" { ws.d(ws.t("a_sel_branch"), 1001) }
                ws.d(ws.t("a_enter_date"), 1301)
                st = .defIn
            case .defIn:
                ws.d(ws.t("a_help0"), 1851)
                ws.d(ws.t("a_help33"), 1951)
                ws.d(ws.t("a_help99"), 2051)
                c.display(" ", at: 2151, eraseEOL: true)
                c.display(" ", at: 2251, eraseEOL: true)
                ws.a = Int(try nAccept(ws, 436, 2, 0, update: false, color: 6))
                if ws.a == 99 { try gl020cShow(ws); st = .initDone; continue }
                if ws.a == 0 { ws.batch.setInt("bdefault", 0); break loop }
                if ws.a > 33 { continue }
                ws.batch.setInt("batch-def-pc", 0)
                if ws.a == 33 { try defSetUp(ws) }
                if ws.a < 33 {
                    // def-val
                    ws.truth = GL.defAcs(s, ws.a) == 0 ? 0 : 1
                    getDescription(ws)
                }
                if ws.truth == 0 { continue }
                ws.batch.setInt("bdefault", Int64(ws.a))
                ws.vatFlag = (GL.defAcs(s, ws.a) == GL.defAcs(s, 31) || GL.defAcs(s, ws.a) == GL.defAcs(s, 32)) ? 1 : 0
                st = .postIn
            case .postIn:
                ws.d(ws.t("a_help_drcr"), 1851)
                ws.d(ws.t("a_help_dr1"), 1951)
                ws.d(ws.t("a_help_dr2"), 2051)
                ws.d(ws.t("a_help_esc"), 2151)
                convention2 = try c.accept(at: 736, size: 2, initial: "CR", options: [.update], color: 3)
                ws.batch.set("convention", Cobol.upper(convention2))
                if ws.status == esc { st = .defIn; continue }
                if !["DR", "CR"].contains(ws.batch.str("convention")) { continue }
                st = .defaultPc
            case .defaultPc:
                for l in [1851, 1951, 2051, 2151] { c.display(" ", at: l, eraseEOL: true) }
                if ws.pcOn {
                    ws.d(Cobol.z(ws.batch.int("batch-def-pc"), 2), 1036, 3)
                    ws.batch.setInt("batch-def-pc", try nAccept(ws, 1036, 2, ws.batch.int("batch-def-pc")))
                    if ws.status == esc { st = .postIn; continue }
                    // validate-pc
                    let pc = Int(ws.batch.int("batch-def-pc"))
                    ws.truth = (pc == 0 || ws.codes[pc - 1] == "Y" || ws.codes[pc - 1] == "E") ? 1 : 0
                    if ws.truth == 1 { getDescription(ws) }
                    if ws.truth == 1 { ws.d(ws.ledger.str("ledger-name"), 441, 3) } else { ws.d(ws.t("a_unrecognised"), 441) }
                    if ws.truth == 0 { continue }
                }
                st = .defDate
            case .defDate:
                // store-defaults
                ws.batch.setInt("batch-def-ac", GL.defAcs(s, ws.a))
                ws.batch.set("batch-def-vat", GL.defVat(s, ws.a))
                ws.batch.set("batch-def-code", GL.defCodes(s, ws.a))
                if ws.autoVat {
                    let v = ws.batch.str("batch-def-vat")
                    if v == "I" { ws.d(ws.t("a_input_vat"), 470) }
                    if v == "O" { ws.d(ws.t("a_output_vat"), 470) }
                    if v == "N" { ws.d(ws.t("a_no_vat"), 470) }
                }
                tranDate = Cobol.x(ws.wsDate, 8)
                ws.d(tranDate, 1336, 3)
                tranDate = try c.accept(at: 1336, size: 8, initial: tranDate, options: [.update], color: 3)
                if ws.status == esc { st = ws.pcOn ? .defaultPc : .postIn; continue }
                // val-date
                let r = GL.zz050(s, tranDate)
                ws.wsDate = r.uk
                if r.bin == 0 { ws.truth = 0; continue }
                ws.truth = 1
                ws.batch.setInt("entered", Int64(r.bin))
                // batch-in
                ws.batch.setInt("ledger", 1)
                for f in ["batch-status", "cleared-status", "proofed", "posted", "stored", "actual-gross", "actual-vat"] { ws.batch.setInt(f, 0) }
                ws.batch.setInt("bcycle", s.sys.int("scycle"))
                ws.batch.setInt("batch-start", s.sys.int("postings") + 1)
                let sp = Cobol.x("", 44)
                c.display(sp, at: 1703); c.display(sp, at: 1803); c.display(sp, at: 1903)
                ws.d(ws.t("a_assigned"), 1701)
                ws.d(ws.t("a_cycle"), 1801)
                ws.d(ws.t("a_items"), 1901)
                ws.d(ws.t("a_gross"), 2001)
                ws.d(ws.t("a_vat"), 2101)
                ws.d(ws.t("a_desc"), 2201)
                ws.d("]", 2245)
                ws.d(Pic.edit("zzzz9", value: ws.batch.int("batch-nos"), scale: 0), 1720, 3)
                st = .cycleIn
            case .cycleIn:
                ws.d(Cobol.z(ws.batch.int("bcycle"), 2), 1820, 3)
                ws.batch.setInt("bcycle", try nAccept(ws, 1820, 2, ws.batch.int("bcycle")))
                if ws.status == esc { st = .defDate; continue }
                if ws.batch.int("bcycle") < s.sys.int("scycle") { ws.d(ws.t("gl108"), 1824, 4); continue }
                ws.y = Int(ws.batch.int("bcycle") - s.sys.int("scycle"))
                if ws.y > 1 { ws.d(ws.t("gl109"), 1824, 4); continue }
                c.display(Cobol.x("", 20), at: 1824)
                st = .itemsIn
            case .itemsIn:
                try GL.acceptRaw(s, &ws.batch, "items", at: 1920, numeric: true, color: 3)
                if ws.status == esc { st = .cycleIn; continue }
                if ws.batch.int("items") == 0 { ws.d(ws.t("gl110"), 1924) }
                st = .grossIn
            case .grossIn:
                ws.setCurs2(2020)
                let amt = try acceptMoney9(ws)
                if ws.status == esc { st = .itemsIn; continue }
                ws.batch.setInt("input-gross", amt)
                st = .vatIn
            case .vatIn:
                if ws.autoVat {
                    ws.setCurs2(2120)
                    let amt = try acceptMoney9(ws)
                    if ws.status == esc { st = .grossIn; continue }
                    ws.batch.setInt("input-vat", amt)
                }
                st = .descIn
            case .descIn:
                try GL.acceptRaw(s, &ws.batch, "description", at: 2220, numeric: false, color: 3)
                if ws.status != esc { break loop }
                st = ws.autoVat ? .vatIn : .grossIn
            }
        }
        ws.ledgerFile.close()
    }

    /// def-set-up thru dummy-return-1: 一時的な既定勘定 (33)
    static func defSetUp(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        ws.lin = 16; ws.cole = 2
        repeat { c.display(Cobol.x("", 44), at: ws.curs); ws.lin += 1 } while ws.lin < 23
        ws.d(ws.t("a_def_setup"), 1716)
        ws.d(ws.t("a_def_ac"), 1903)
        ws.d(ws.t("a_def_vat"), 2003)
        ws.d(ws.t("a_def_code"), 2103)
        getAc: while true {
            ws.truth = 0
            ws.setCurs2(1911)
            let acc = try acceptAccount(ws)
            GL.setDefAcs(s, 33, acc)
            if acc == 0 { return }
            ws.a = 33
            ws.batch.setInt("batch-def-pc", 0)
            getDescription(ws)
            if ws.truth == 0 { continue }
            ws.d(ws.ledger.str("ledger-name"), 1920, 3)
            getVat: while true {
                ws.d(ws.t("a_help_i"), 1851)
                ws.d(ws.t("a_help_o"), 1951)
                ws.d(ws.t("a_help_n"), 2051)
                var vat2 = GL.defVat(s, 33)
                ws.d(vat2, 2011, 3)
                vat2 = try c.accept(at: 2011, size: 1, initial: vat2, options: [.update], color: 3)
                let vat = Cobol.upper(vat2)
                if ws.status == esc { continue getAc }
                if !["I", "O", "N"].contains(vat) { continue }
                GL.setDefVat(s, 33, vat)
                // get-code
                for l in [1851, 1951, 2051] { c.display(" ", at: l, eraseEOL: true) }
                var codes2 = GL.defCodes(s, 33)
                ws.d(codes2, 2111, 3)
                codes2 = try c.accept(at: 2111, size: 2, initial: codes2, options: [.update], color: 3)
                if ws.status == esc { continue getVat }
                GL.setDefCodes(s, 33, Cobol.upper(codes2))
                if ws.preserveBatch { batchOutline(ws) }
                ws.truth = 1
                return
            }
        }
    }

    // MARK: gl050b — 仕訳入力

    static func regetVatRate(_ ws: WS) throws {
        while true {
            ws.v = 1
            ws.d(ws.t("b_vat_rate"), 401)
            ws.d(String(ws.v), 414, 3)
            ws.v = Int(try nAccept(ws, 414, 1, 1))
            if ws.v < 1 || ws.v > 3 { continue }
            ws.vatRate = ws.s.sys.int("vat-rate-\(ws.v)")
            ws.d(Pic.edit("z9.99", value: ws.vatRate, scale: 2), 417, 3)
            ws.d(ws.t("b_vat_ok"), 422)
            let r = try ws.c.accept(at: 437, size: 1, initial: "Y", options: [.update], color: 3)
            if r == "N" || r == "n" { continue }
            return
        }
    }

    static func amt(_ v: Int64) -> String { Cobol.z(abs(v) / 100 % 100_000_000, 8) + "." + Cobol.z(abs(v) % 100, 2) }

    static func gl050b(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        typealias A = PostingArray
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("b_title"), 126)
        ws.d(ws.wsDate, 171)
        // help-outline thru h-o-data (gl050b 側)
        ws.lin = 14; ws.cole = 54
        c.display(String(repeating: "+", count: 27), at: 1454)
        c.display(String(repeating: "+", count: 27), at: 2354)
        repeat {
            ws.lin += 1
            ws.cole = 54; ws.d("+", ws.curs)
            ws.cole = 80; ws.d("+", ws.curs)
        } while ws.lin < 22
        ws.d(ws.t("b_option"), 1656)
        ws.d(ws.t("b_opt_b"), 1856)
        ws.d(ws.t("b_opt_e"), 1956)
        ws.d(ws.t("b_opt_f"), 2056)
        ws.d(ws.t("b_opt_q"), 2156)
        ws.d(ws.t("b_opt_n"), 2256)
        ws.ledgerFile.open()
        ws.w = 0
        if ws.batch.str("batch-def-vat") == "O" { ws.w = 32 }
        if ws.batch.str("batch-def-vat") == "I" { ws.w = 31 }
        if ws.w != 0 { try regetVatRate(ws) }
        // jump-tag
        ws.d(ws.t("b_batch"), 456)
        ws.d(Pic.edit("zzzz9", value: ws.batch.int("batch-nos"), scale: 0), 469)
        ws.d("/", 474)
        ws.d(ws.t("b_default"), 656)
        ws.d(Cobol.z(ws.batch.int("bdefault"), 2), 669)
        ws.d(ws.t("b_contra"), 856)
        ws.d(Cobol.z(ws.batch.int("batch-def-ac"), 6), 869)
        if !ws.batch.raw("batch-def-pc").allSatisfy({ (0x30...0x39).contains($0) }) { ws.batch.setInt("batch-def-pc", 0) }
        if ws.batch.int("batch-def-pc") != 0 {
            ws.d("/", 875)
            ws.d(Cobol.z(ws.batch.int("batch-def-pc"), 2), 876, 3)
        }
        if ws.w != 0 {
            ws.d(ws.t("b_vat_ac"), 1056)
            let acs = GL.defAcs(s, ws.w)
            ws.d(Cobol.z(acs / 100, 4) + "." + Cobol.z(acs % 100, 2), 1069, 3)
        } else {
            ws.d(ws.t("b_no_vat"), 1056)
        }
        ws.d(ws.t("b_convention"), 1256)
        ws.d(ws.batch.str("convention"), 1269, 3)
        ws.d(ws.t("b_date"), 601)
        ws.d(ws.t("b_account"), 801)
        if s.sys.str("p-c") == "P" { ws.d(ws.t("b_pc"), 1001) }
        if s.sys.str("p-c") == "B" { ws.d(ws.t("b_branch"), 1001) }
        ws.d(ws.t("b_amount"), 1201)
        if ws.autoVat && ws.w != 0 { ws.d(ws.t("b_vat_code"), 1401) }
        ws.d(ws.t("b_vat_amount"), 1601)
        ws.d(ws.t("b_narrative"), 1801)
        ws.d("]", 1849)
        ws.saveA = 0
        ws.a = 1

        enum St { case mainLoop, getAccount, acceptPC, acceptAmount, acceptVat, vatAmountInput, narrative, loopEnd }
        var st = St.mainLoop
        let up = { ws.status == pgUp || ws.status == keyUp }
        let down = { ws.status == pgDn || ws.status == keyDown }
        loop: while true {
            switch st {
            case .mainLoop:
                ws.d(Cobol.z(ws.a, 2), 475, 3)
                ws.d(ws.wsDate, 617, 3)
                ws.wsDate = try c.accept(at: 617, size: 10, initial: ws.wsDate, options: [.update], color: 3)
                ws.arr.set(A.date, ws.a, ws.wsDate)
                if up() && ws.w != 0 { try regetVatRate(ws); continue }
                if up() || ws.status == esc || down() { continue }
                if ws.z > 0 { continue }
                let test = Maps04.normalized(ws.arr.str(A.date, ws.a))
                let r = GL.zz050(s, test)
                ws.wsDate = r.uk
                ws.arr.set(A.date, ws.a, test)
                if r.bin == 0 { ws.d(ws.t("b_invalid_date"), 636, 4); continue }
                c.display(Cobol.x("", 29), at: 626)
                st = .getAccount
            case .getAccount:
                ws.setCurs2(817)
                ws.accountIn = try acceptAccount(ws)
                if up() || down() || ws.z != 0 { st = .mainLoop; continue }
                if ws.status == esc { break loop }
                ws.weError = 0
                ws.ledger.setInt("ledger-nos", ws.accountIn)
                ws.ledger.setInt("ledger-pc", ws.arrayPc)
                switch ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) {
        case .ok(let r): ws.ledger = r
        case .miss: ws.weError = 255
        case .error: break
        }
                if ws.weError == 0 { ws.d(ws.ledger.str("ledger-name"), 826, 3) }
                else { ws.d(ws.t("b_invalid_ac"), 826, 4); continue }
                ws.vatFlag2 = (ws.vatFlag == 1 || ws.accountIn == GL.defAcs(s, 31) || ws.accountIn == GL.defAcs(s, 32)) ? 1 : 0
                st = .acceptPC
            case .acceptPC:
                ws.arrayPc = 0
                if ws.pcOn {
                    ws.d("00", 1017, 3)
                    ws.arrayPc = try nAccept(ws, 1017, 2, 0)
                    if down() || ws.z != 0 { st = .mainLoop; continue }
                    if up() { st = .getAccount; continue }
                    if ws.status == esc { break loop }
                }
                st = .acceptAmount
            case .acceptAmount:
                ws.setCurs2(1217)
                if ws.vatFlag2 == 0 {
                    ws.arr.setNum(A.amount, ws.a, try acceptMoney8s(ws), signed: true)
                } else {
                    ws.arr.setNum(A.amount, ws.a, 0, signed: true)
                }
                ws.d(amt(ws.arr.num(A.amount, ws.a)), 1217, 3)
                if down() || ws.z != 0 { st = .mainLoop; continue }
                if up() { st = ws.pcOn ? .acceptPC : .getAccount; continue }
                if ws.status == esc { break loop }
                st = .acceptVat
            case .acceptVat:
                if !ws.autoVat || ws.w == 0 { ws.arr.setNum(A.vatAmount, ws.a, 0, signed: true); st = .vatAmountInput; continue }
                ws.arrayVat = " "
                if ws.vatFlag2 == 1 { ws.arr.setNum(A.vatAmount, ws.a, 0, signed: true); st = .vatAmountInput; continue }
                ws.d(ws.arrayVat, 1417, 3)
                ws.arrayVat = Cobol.upper(try c.accept(at: 1417, size: 1, initial: ws.arrayVat, options: [.update], color: 3))
                if down() || ws.z != 0 { st = .mainLoop; continue }
                if up() { st = .acceptAmount; continue }
                if ws.status == esc { break loop }
                let amount = ws.arr.num(A.amount, ws.a)
                if ws.arrayVat == "P" {
                    // net: vat = amount * rate / 100 (rounded)
                    ws.arr.setNum(A.vatAmount, ws.a, Cobol.rescaleRounded(amount * ws.vatRate, from: 6, to: 2), signed: true)
                    ws.d(amt(ws.arr.num(A.vatAmount, ws.a)), 1617, 3)
                    st = .vatAmountInput; continue
                }
                if ws.arrayVat == "M" {
                    // gross: vat = amount - amount / ((rate + 100) / 100) (rounded)、amount から vat を引く
                    let den = ws.vatRate + 10000
                    let num = amount * ws.vatRate
                    let q = (2 * abs(num) + den) / (2 * den)
                    let vat = num < 0 ? -q : q
                    ws.arr.setNum(A.vatAmount, ws.a, vat, signed: true)
                    ws.arr.setNum(A.amount, ws.a, amount - ws.arr.num(A.vatAmount, ws.a), signed: true)
                    ws.d(amt(ws.arr.num(A.vatAmount, ws.a)), 1617, 3)
                    st = .vatAmountInput; continue
                }
                if ws.arrayVat == " " { ws.arr.setNum(A.vatAmount, ws.a, 0, signed: true); st = .narrative; continue }
                ws.d(ws.t("b_invalid_code"), 1439, 4)
            case .vatAmountInput:
                if ws.w == 0 { st = .narrative; continue }
                ws.setCurs2(1617)
                let old = ws.arr.num(A.vatAmount, ws.a)
                let new = try acceptMoney8s2(ws, abs(old))
                if new != old && ws.arr.num(A.amount, ws.a) != 0 && ws.arrayVat == "M" {
                    ws.arr.setNum(A.amount, ws.a, ws.arr.num(A.amount, ws.a) + old - new, signed: true)
                }
                ws.arr.setNum(A.vatAmount, ws.a, new, signed: true)
                if down() || ws.z != 0 { st = .mainLoop; continue }
                if up() { st = .acceptVat; continue }
                if ws.status == esc { break loop }
                st = .narrative
            case .narrative:
                if ws.arr.num(A.amount, ws.a) == 0 && ws.arr.num(A.vatAmount, ws.a) == 0 { st = .mainLoop; continue }
                c.display(Cobol.x("", 12), at: 1439)
                ws.arr.set(A.legend, ws.a, try c.accept(at: 1817, size: 32, initial: "", options: [.update], color: 3))
                if down() || ws.z != 0 { st = .mainLoop; continue }
                if up() { st = ws.autoVat ? .acceptVat : .acceptAmount; continue }
                if ws.status == esc { break loop }
                st = .loopEnd
            case .loopEnd:
                let dr = ws.batch.str("convention") == "DR"
                if dr {
                    ws.arr.setNum(A.dr, ws.a, ws.accountIn); ws.arr.setNum(A.drPc, ws.a, ws.arrayPc); ws.arr.set(A.vatSide, ws.a, "DR")
                    ws.arr.setNum(A.cr, ws.a, ws.batch.int("batch-def-ac")); ws.arr.setNum(A.crPc, ws.a, ws.batch.int("batch-def-pc"))
                } else {
                    ws.arr.setNum(A.cr, ws.a, ws.accountIn); ws.arr.setNum(A.crPc, ws.a, ws.arrayPc); ws.arr.set(A.vatSide, ws.a, "CR")
                    ws.arr.setNum(A.dr, ws.a, ws.batch.int("batch-def-ac")); ws.arr.setNum(A.drPc, ws.a, ws.batch.int("batch-def-pc"))
                    // batch-def-code の転記は else 側に含まれる (レガシーの終止符位置どおり)
                    ws.arr.set(A.code, ws.a, ws.batch.str("batch-def-code"))
                }
                ws.arr.setNum(A.vatAc, ws.a, ws.w != 0 ? GL.defAcs(s, ws.w) : 0)
                ws.arr.setNum(A.vatPc, ws.a, ws.batch.int("batch-def-pc"))
                ws.a += 1
                if ws.a > 12 { writeOut(ws) }
                st = .mainLoop
            }
        }
        // main-exit
        ws.ledgerFile.close()
        if ws.status == esc { quitBatch(ws) } else { s.sys.setInt("postings", s.sys.int("postings") + Int64(ws.saveA)) }
    }

    static func writeOut(_ ws: WS) {
        typealias A = PostingArray
        if ws.a < 1 { return }
        if ws.escapeCode != "F" { ws.a -= 1 }
        ws.y = 1
        while ws.y <= ws.a {
            let y = ws.y
            ws.post.setInt("batch", ws.batch.int("batch-nos"))
            ws.post.setInt("post-number", Int64(ws.saveA + y))
            ws.rrn = Int((ws.batch.int("batch-start") + ws.post.int("post-number")) % 100_000)
            ws.post.set("post-code", ws.batch.str("batch-def-code"))
            ws.post.set("post-date", ws.arr.str(A.date, y))
            ws.post.setInt("post-dr", ws.arr.num(A.dr, y))
            ws.post.setInt("dr-pc", ws.arr.num(A.drPc, y))
            ws.post.setInt("post-cr", ws.arr.num(A.cr, y))
            ws.post.setInt("cr-pc", ws.arr.num(A.crPc, y))
            ws.post.setInt("post-amount", ws.arr.num(A.amount, y))
            ws.post.set("post-legend", ws.arr.str(A.legend, y))
            ws.post.setInt("vat-ac", ws.arr.num(A.vatAc, y))
            ws.post.setInt("vat-pc", ws.arr.num(A.vatPc, y))
            ws.post.set("post-vat-side", ws.arr.str(A.vatSide, y))
            ws.post.setInt("vat-amount", ws.arr.num(A.vatAmount, y))
            GL.relWrite(ws.s, ws.rrn, ws.post.bytes)
            ws.y += 1
        }
        ws.saveA += ws.a
        ws.a = 1
    }

    /// quit-batch: このバッチの仕訳を posting.dat から削除し z = 9
    static func quitBatch(_ ws: WS) {
        ws.rrn = Int(ws.batch.int("batch-start"))
        var found = false
        if let d = GL.relRead(ws.s, ws.rrn) { ws.post = Record(GL.postingLayout, bytes: d); found = true }
        while true {
            if found && ws.post.int("batch") == ws.batch.int("batch-nos") { GL.relDelete(ws.s, ws.rrn) }
            guard let n = GL.relNext(ws.s, after: ws.rrn) else { break }
            ws.rrn = n.rrn
            ws.post = Record(GL.postingLayout, bytes: n.data)
            found = true
        }
        ws.z = 9
    }
}
