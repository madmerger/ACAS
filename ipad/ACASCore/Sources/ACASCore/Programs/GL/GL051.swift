import Foundation

/// general/gl051.cbl: Batch Amendment / Reporting Functions (バッチ修正・プルーフ帳票)
enum GL051 {
    static let progName = "gl051 (3.00.04)"
    static let esc = 2005, pgUp = 2001, pgDn = 2002, keyUp = 2003, keyDown = 2004

    final class WS {
        let s: Session
        let c: Console
        let dates: GLDates
        let batchFile: IndexedFile
        let ledgerFile: IndexedFile
        var batch = Record(GL.batchLayout, bytes: [UInt8](repeating: 0, count: GL.batchLayout.size))
        var ledger = Record(GL.ledgerLayout, bytes: [UInt8](repeating: 0, count: GL.ledgerLayout.size))
        var post = Record(GL.postingLayout, bytes: [UInt8](repeating: 0, count: GL.postingLayout.size))
        var rrn = 0
        var menu = 0, v = 0, y = 0, z = 0
        var firstTimeFlag = 0, saveBatch: Int64 = 0, truth = 0, weError = 0
        var lineCnt = 0, pageNos = 0
        var displayBatch = "    0"
        var accountIn: Int64 = 0, arrayPc: Int64 = 0, arrayVat = " "
        var vatRate: Int64 = 0
        var accOk: Int64 = 0
        var lin = 0, cole = 0, lin2 = 0, col2 = 0
        var scrAcc = Array("0000.00"), scr8 = Array("00000000.00"), scr9 = Array("000000000.00")
        var drError = Cobol.x("", 12), crError = Cobol.x("", 12)
        var l3Date = "", l3User = ""
        init(_ s: Session) {
            self.s = s; c = s.console; dates = GLDates(s)
            batchFile = GL.batchFile(s); ledgerFile = GL.ledgerFile(s)
        }
        var curs: Int { lin * 100 + cole }
        var curs2: Int { lin2 * 100 + col2 }
        func setCurs2(_ v: Int) { lin2 = (v / 100) % 100; col2 = v % 100 }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func t(_ k: String) -> String { s.t("gl051." + k) }
        var pcOn: Bool { ["P", "B"].contains(s.sys.str("p-c")) }
        var autoVat: Bool { s.sys.str("vat") == "Y" }
        var status: Int { c.crtStatus }
        var up: Bool { status == pgUp || status == keyUp }
        var down: Bool { status == pgDn || status == keyDown }
    }

    static func nAccept(_ ws: WS, _ at: Int, _ size: Int, _ v: Int64, update: Bool = true, color: UInt8 = 3) throws -> Int64 {
        Cobol.moveNumeric(try ws.c.accept(at: at, size: size, kind: .numeric, initial: Cobol.z(v, size), options: update ? [.update] : [], color: color), digits: size, scale: 0)
    }
    static func acceptAccount(_ ws: WS, _ v: Int64) throws -> Int64 {
        GL050.fill(&ws.scrAcc, 0..<4, v / 100); GL050.fill(&ws.scrAcc, 5..<7, v % 100)
        ws.d(String(ws.scrAcc), ws.curs2, 3)
        ws.scrAcc = Array(try ws.c.accept(at: ws.curs2, size: 7, initial: String(ws.scrAcc), options: [.update], color: 3))
        return GL050.digits(ws.scrAcc[0..<4]) * 100 + GL050.digits(ws.scrAcc[5..<7])
    }
    static func acceptMoney8s2(_ ws: WS, _ v: Int64) throws -> Int64 {
        GL050.fill(&ws.scr8, 9..<11, v % 100); GL050.fill(&ws.scr8, 0..<8, v / 100)
        ws.d(String(ws.scr8), ws.curs2, 3)
        ws.scr8 = Array(try ws.c.accept(at: ws.curs2, size: 11, initial: String(ws.scr8), options: [.update], color: 3))
        return GL050.digits(ws.scr8[0..<8]) * 100 + GL050.digits(ws.scr8[9..<11])
    }
    static func acceptMoney9(_ ws: WS, _ v: Int64) throws -> Int64 {
        GL050.fill(&ws.scr9, 0..<9, v / 100); GL050.fill(&ws.scr9, 10..<12, v % 100)
        ws.d(String(ws.scr9), ws.curs2, 3)
        ws.scr9 = Array(try ws.c.accept(at: ws.curs2, size: 12, initial: String(ws.scr9), options: [.update], color: 3))
        return GL050.digits(ws.scr9[0..<9]) * 100 + GL050.digits(ws.scr9[10..<12])
    }

    static func run(_ s: Session) throws {
        let ws = WS(s)
        let c = s.console
        while true {
            ws.dates.zz070()
            ws.l3Date = ws.dates.wsDate
            ws.l3User = s.sys.str("usera")
            ws.z = 0
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            ws.d(ws.t("title"), 123)
            ws.d(ws.dates.wsDate, 171)
            ws.d(s.sys.str("usera"), 301)
            ws.d(ws.t("select"), 801)
            ws.d(ws.t("opt1"), 1001)
            ws.d(ws.t("opt2"), 1101)
            ws.d(ws.t("opt3"), 1201)
            ws.d(ws.t("opt4"), 1301)
            ws.d(ws.t("opt9"), 1601)
            ws.menu = Int(try nAccept(ws, 843, 1, 0, update: false, color: 6))
            if ws.menu == 9 { return }
            ws.batchFile.open()
            if ws.menu == 1 || ws.menu == 3 {
                // get-batch
                while true {
                    ws.batch.setInt("ledger", 1)
                    ws.d(ws.t("enter_batch"), 1801)
                    try GL.acceptRaw(s, &ws.batch, "batch-nos", at: 1824, numeric: true, color: 6)
                    if ws.batch.int("batch-nos") == 0 { break }
                    switch ws.batchFile.glRead(key: ws.batch.raw("batch-key")) {
                    case .ok(let r): ws.batch = r
                    case .miss: continue
                    case .error: break
                    }
                    break
                }
                if ws.batch.int("batch-nos") == 0 { ws.batchFile.close(); continue }
            }
            if ws.menu == 1 { try gl050c(ws) }
            if ws.menu == 3 { try gl050d(ws) }
            if ws.menu == 2 {
                // proof-all
                proofAll: while true {
                    var notOpen = false
                    switch ws.batchFile.glNext() {
                    case .ok(let r): ws.batch = r
                    case .miss: break proofAll
                    case .error: notOpen = true
                    }
                    // 未オープンのまま読み続ける場合は同じレコード域で無限に繰り返す
                    if ws.batch.int("bcycle") != s.sys.int("scycle") { if notOpen { try GL.hang(s) }; continue }
                    if ws.batch.int("cleared-status") != 0 { if notOpen { try GL.hang(s) }; continue }
                    try gl050d(ws)
                    ws.batchFile.rewrite(ws.batch)
                    if notOpen { try GL.hang(s) }
                }
            }
            if ws.menu == 4 {
                ws.saveBatch = 0
                ws.batch.setInt("batch-start", 1)
                ws.z = 99
                try gl050d(ws)
            }
            if ws.menu != 1 { ws.batch.setInt("proofed", Int64(ws.dates.uBin)) }
            ws.batchFile.rewrite(ws.batch)
            ws.batchFile.close()
        }
    }

    // MARK: gl050c — バッチ修正

    static func helpOutline(_ ws: WS) {
        ws.lin = 14; ws.cole = 54
        ws.c.display(String(repeating: "+", count: 27), at: 1454)
        ws.c.display(String(repeating: "+", count: 27), at: 2354)
        repeat {
            ws.lin += 1
            ws.cole = 54; ws.d("+", ws.curs)
            ws.cole = 80; ws.d("+", ws.curs)
        } while ws.lin < 22
        ws.d(ws.t("c_option"), 1656)
        ws.d(ws.t("c_opt_b"), 1856)
        ws.d(ws.t("c_opt_e"), 1956)
    }

    /// batch-amendment section: バッチヘッダの修正。trutht = 1 なら明細は修正しない。
    static func batchAmendment(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        ws.d(ws.t("h_amend_header"), 801)
        var reply = Cobol.upper(try c.accept(at: 832, size: 1, initial: "N", options: [.update], color: 6))
        if reply == "N" {
            ws.truth = 0
            c.display(" ", at: 801, eraseEOL: true)
            return
        }
        // batch-outline
        ws.lin = 15
        c.display(String(repeating: "*", count: 46), at: 1501)
        c.display(String(repeating: "*", count: 46), at: 2301)
        repeat {
            ws.lin += 1
            ws.cole = 1; ws.d("*", ws.curs)
            ws.cole = 46; ws.d("*", ws.curs)
        } while ws.lin < 23
        ws.d(ws.t("h_batch_data"), 1618)
        ws.d(ws.t("h_batch"), 1702)
        ws.displayBatch = Pic.edit("zzzz9", value: ws.batch.int("batch-nos"), scale: 0)
        ws.d(ws.displayBatch, 1720)
        ws.d(ws.t("h_cycle"), 1802)
        ws.d(ws.t("h_items"), 1902)
        ws.d(ws.t("h_gross"), 2002)
        ws.d(ws.t("h_vat"), 2102)
        ws.d(ws.t("h_desc"), 2202)
        ws.d("]", 2244)
        enum St { case cycleIn, itemsIn, grossIn, vatIn, descIn }
        var st = St.cycleIn
        loop: while true {
            switch st {
            case .cycleIn:
                ws.d(GL.shown(ws.batch, "bcycle"), 1820, 3)
                try GL.acceptRaw(s, &ws.batch, "bcycle", at: 1820, numeric: true, color: 3)
                if ws.status == esc { ws.truth = 0; return }
                if ws.batch.int("bcycle") < s.sys.int("scycle") { ws.d(ws.t("gl108"), 1824); continue }
                ws.y = Int(ws.batch.int("bcycle") - s.sys.int("scycle"))
                if ws.y > 1 { ws.d(ws.t("gl109"), 1824); continue }
                c.display(Cobol.x("", 27), at: 1824)
                st = .itemsIn
            case .itemsIn:
                ws.d(GL.shown(ws.batch, "items"), 1920, 3)
                try GL.acceptRaw(s, &ws.batch, "items", at: 1920, numeric: true, color: 3)
                if ws.status == esc { st = .cycleIn; continue }
                if ws.batch.int("items") == 0 { ws.d(ws.t("gl110"), 1924) }
                st = .grossIn
            case .grossIn:
                ws.setCurs2(2020)
                ws.batch.setInt("input-gross", try acceptMoney9(ws, ws.batch.int("input-gross")))
                if ws.status == esc { st = .itemsIn; continue }
                st = .vatIn
            case .vatIn:
                if ws.autoVat {
                    ws.setCurs2(2120)
                    ws.batch.setInt("input-vat", try acceptMoney9(ws, ws.batch.int("input-vat")))
                    if ws.status == esc { st = .grossIn; continue }
                }
                st = .descIn
            case .descIn:
                ws.d(GL.shown(ws.batch, "description"), 2220, 3)
                try GL.acceptRaw(s, &ws.batch, "description", at: 2220, numeric: false, color: 3)
                if ws.status != esc { break loop }
                st = ws.autoVat ? .vatIn : .grossIn
            }
        }
        // detail-query
        ws.d(ws.t("h_amend_details"), 801)
        reply = Cobol.upper(try c.accept(at: 832, size: 1, initial: "N", options: [.update], color: 6))
        ws.truth = reply == "N" ? 1 : 0
        c.display(" ", at: 801, eraseEOL: true)
        ws.cole = 1; ws.lin = 15
        c.display(" ", at: ws.curs, eraseEOS: true)
        helpOutline(ws)
    }

    static func gl050c(_ ws: WS) throws {
        let c = ws.c, s = ws.s
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("c_title"), 126)
        ws.dates.zz070()
        ws.d(ws.dates.wsDate, 171)
        helpOutline(ws)
        try batchAmendment(ws)
        if ws.truth == 1 { return }
        ws.ledgerFile.open()
        while true {
            ws.v = 1
            ws.d(ws.t("c_vat_rate"), 401)
            ws.v = Int(try nAccept(ws, 414, 1, 1))
            if ws.v < 1 || ws.v > 3 { continue }
            ws.vatRate = s.sys.int("vat-rate-\(ws.v)")
            ws.d(Pic.edit("z9.99", value: ws.vatRate, scale: 2), 417)
            ws.d(ws.t("c_vat_ok"), 422, 6)
            let r = try c.accept(at: 437, size: 1, color: 3)
            if r == "N" || r == "n" { continue }
            break
        }
        ws.d(ws.t("c_batch"), 456)
        ws.d(ws.displayBatch, 469)
        ws.d("/", 474)
        ws.d(ws.t("c_default"), 656)
        ws.d(GL.shown(ws.batch, "bdefault"), 669)
        ws.d(ws.t("c_contra"), 856)
        ws.d(GL.shown(ws.batch, "batch-def-ac"), 869)
        if ws.batch.int("batch-def-pc") != 0 {
            ws.d("/", 875)
            ws.d(GL.shown(ws.batch, "batch-def-pc"), 876)
        }
        ws.d(ws.t("c_vat_ac"), 1056)
        ws.d(GL.shown(ws.batch, "batch-def-vat"), 1069)
        ws.d(ws.t("c_convention"), 1256)
        ws.d(GL.shown(ws.batch, "convention"), 1269)
        ws.rrn = 0
        let postOpen = GL.postingFile(s).exists
        let dr = { ws.batch.str("convention") == "DR" }

        enum St { case loop, acceptDate, getAccount, acceptPC, acceptAmount, acceptVat, vatAmountInput, narrative }
        var st = St.loop
        loop: while true {
            switch st {
            case .loop:
                ws.d(ws.t("c_date"), 601)
                ws.d(ws.t("c_account"), 801)
                if s.sys.str("p-c") == "P" { ws.d(ws.t("c_pc"), 1001) }
                if s.sys.str("p-c") == "B" { ws.d(ws.t("c_branch"), 1001) }
                ws.d(ws.t("c_amount"), 1201)
                if ws.autoVat { ws.d(ws.t("c_vat_code"), 1401) }
                ws.d(ws.t("c_vat_amount"), 1601)
                ws.d(ws.t("c_narrative"), 1801)
                ws.d("]", 1849)
                // read-loop
                while true {
                    // 未オープンの posting-file は at end にならず、batch が一致するまで読み続ける (無限ループ)
                    if !postOpen { try GL.hang(s) }
                    guard let n = GL.relNext(s, after: ws.rrn) else { break loop }
                    ws.rrn = n.rrn
                    ws.post = Record(GL.postingLayout, bytes: n.data)
                    if ws.post.int("batch") == ws.batch.int("batch-nos") { break }
                }
                st = .acceptDate
            case .acceptDate:
                ws.d(ws.post.str("post-date"), 617, 3)
                ws.post.set("post-date", try c.accept(at: 617, size: 8, initial: ws.post.str("post-date"), options: [.update], color: 3))
                if ws.status == esc { break loop }
                ws.post.set("post-date", ws.dates.zz050(ws.post.str("post-date")))
                if ws.dates.uBin == 0 {
                    ws.truth = 0
                    ws.d(ws.t("gl011"), 636, 4)
                    continue
                }
                c.display(Cobol.x("", 29), at: 626)
                ws.accOk = dr() ? ws.post.int("post-dr") : ws.post.int("post-cr")
                ws.arrayPc = dr() ? ws.post.int("dr-pc") : ws.post.int("cr-pc")
                st = .getAccount
            case .getAccount:
                ws.setCurs2(817)
                ws.accOk = try acceptAccount(ws, ws.accOk)
                ws.accountIn = ws.accOk
                if ws.up || ws.down || ws.z != 0 { st = .acceptDate; continue }
                if ws.status == esc { break loop }
                // get-description
                ws.weError = 0
                ws.ledger.setInt("ledger-nos", ws.accountIn)
                ws.ledger.setInt("ledger-pc", ws.arrayPc)
                switch ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) {
                case .ok(let r): ws.ledger = r
                case .miss: ws.weError = 255
                case .error: break
                }
                if ws.weError == 0 { ws.d(GL.shown(ws.ledger, "ledger-name"), 826, 3) }
                else { ws.truth = 0; ws.d(ws.t("c_invalid_ac"), 826); continue }
                st = .acceptPC
            case .acceptPC:
                if ws.pcOn {
                    ws.d(Cobol.z(ws.arrayPc, 2), 1017, 3)
                    ws.arrayPc = try nAccept(ws, 1017, 2, ws.arrayPc)
                    if ws.up { st = .getAccount; continue }
                    if ws.status == esc { break loop }
                }
                st = .acceptAmount
            case .acceptAmount:
                if dr() { ws.post.setInt("post-dr", ws.accountIn); ws.post.setInt("dr-pc", ws.arrayPc) }
                else { ws.post.setInt("post-cr", ws.accountIn); ws.post.setInt("cr-pc", ws.arrayPc) }
                ws.setCurs2(1217)
                ws.post.setInt("post-amount", try acceptMoney8s2(ws, abs(ws.post.int("post-amount"))))
                if ws.up { st = ws.pcOn ? .acceptPC : .getAccount; continue }
                if ws.status == esc { break loop }
                st = .acceptVat
            case .acceptVat:
                if !ws.autoVat { st = .vatAmountInput; continue }
                ws.arrayVat = " "
                ws.d(ws.arrayVat, 1417, 3)
                ws.arrayVat = Cobol.upper(try c.accept(at: 1417, size: 1, initial: " ", options: [.update], color: 3))
                c.display(Cobol.x("", 18), at: 1439)
                if ws.up { st = .acceptAmount; continue }
                if ws.status == esc { break loop }
                let amount = ws.post.int("post-amount")
                if ws.arrayVat == "P" {
                    ws.post.setInt("vat-amount", Cobol.rescaleRounded(amount * ws.vatRate, from: 6, to: 2))
                    st = .vatAmountInput; continue
                }
                if ws.arrayVat == "M" {
                    let den = ws.vatRate + 10000, num = amount * ws.vatRate
                    let q = (2 * abs(num) + den) / (2 * den)
                    ws.post.setInt("vat-amount", num < 0 ? -q : q)
                    ws.post.setInt("post-amount", amount - ws.post.int("vat-amount"))
                    st = .vatAmountInput; continue
                }
                if ws.arrayVat == " " { ws.post.setInt("vat-amount", 0); st = .narrative; continue }
                ws.d(ws.t("gl111"), 1439)
            case .vatAmountInput:
                ws.setCurs2(1617)
                let old = ws.post.int("vat-amount")
                let new = try acceptMoney8s2(ws, abs(old))
                if new != old && ws.post.int("post-amount") != 0 && ws.arrayVat == "M" {
                    ws.post.setInt("post-amount", ws.post.int("post-amount") + old - new)
                }
                ws.post.setInt("vat-amount", new)
                if ws.up { st = .acceptVat; continue }
                if ws.status == esc { break loop }
                st = .narrative
            case .narrative:
                c.display(Cobol.x("", 18), at: 1439)
                ws.d(ws.post.str("post-legend"), 1817, 3)
                ws.post.set("post-legend", try c.accept(at: 1817, size: 32, initial: ws.post.str("post-legend"), options: [.update], color: 3))
                if ws.up { st = ws.autoVat ? .acceptVat : .acceptAmount; continue }
                if ws.status == esc { break loop }
                GL.relRewrite(s, ws.rrn, ws.post.bytes)
                st = .loop
            }
        }
        ws.ledgerFile.close()
    }

    // MARK: gl050d — プルーフ帳票

    static func headings(_ ws: WS) {
        let s = ws.s
        ws.pageNos = Int(Int8(truncatingIfNeeded: ws.pageNos + 1))
        let line1 = Cobol.x(progName, 14) + Cobol.x("", 41) + Cobol.x(ws.t("p_title"), 24) + Cobol.x("", 45)
            + Cobol.x(ws.t("p_page"), 6) + Pic.edit("z9", value: Int64(ws.pageNos), scale: 0)
        ws.dates.uBin = Int(ws.batch.int("entered"))
        ws.dates.zz060()
        GLPrint.write(s, line1, after: 1)
        GLPrint.write(s, Cobol.x(ws.l3User, 32) + Cobol.x("", 90) + Cobol.x(ws.l3Date, 10), after: 1)
        ws.lineCnt = 6
        if ws.z != 99 {
            GLPrint.write(s, line4(ws, ws.batch.int("batch-nos")), after: 2)
            ws.lineCnt += 2
        }
        GLPrint.write(s, Cobol.x(ws.t("p_head1"), 110) + Cobol.x(ws.t("p_head2"), 22), after: 2)
        GLPrint.write(s, Cobol.x(ws.t("p_head3"), 97), after: 1)
        GLPrint.write(s, "", after: 1)
    }

    static func line4(_ ws: WS, _ batch: Int64) -> String {
        Cobol.x(ws.t("p_batch"), 8) + Pic.edit("zzzz9", value: batch, scale: 0) + Cobol.x("", 8)
            + Cobol.x(ws.batch.str("description"), 24) + Cobol.x(ws.t("p_date_entered"), 20) + Cobol.x(ws.dates.wsDate, 10)
    }

    static func bwz(_ pic: String, _ v: Int64, _ scale: Int) -> String {
        v == 0 ? Cobol.x("", Pic.size(pic)) : Pic.edit(pic, value: v, scale: scale)
    }

    static func gl050d(_ ws: WS) throws {
        let s = ws.s
        GLPrint.open(s)
        ws.pageNos = 0
        ws.truth = 1
        if ws.firstTimeFlag == 0 {
            ws.c.display(progName, at: 101, color: 2, eraseEOS: true)
            ws.d(ws.t("d_title"), 127)
            ws.dates.zz070()
            ws.d(ws.dates.wsDate, 171)
            ws.d(ws.t("d_printing"), 1212)
            if ws.menu == 2 { ws.firstTimeFlag = 1 }
        }
        ws.ledgerFile.open()
        ws.batch.setInt("actual-gross", 0); ws.batch.setInt("actual-vat", 0)
        // batch-print
        headings(ws)
        ws.batch.setInt("ledger", 1)
        ws.rrn = 0
        // 未オープンの posting-file は at end にならず、同じレコード域を処理し続ける (無限ループ)
        if !GL.postingFile(s).exists { try GL.hang(s) }
        while let n = GL.relNext(s, after: ws.rrn) {
            ws.rrn = n.rrn
            ws.post = Record(GL.postingLayout, bytes: n.data)
            let p = ws.post
            if p.int("batch") == 0 { continue }
            if ws.z == 99 && ws.saveBatch != p.int("batch") {
                ws.saveBatch = p.int("batch")
                ws.batch.setInt("batch-nos", p.int("batch"))
                // get-a-batch
                switch ws.batchFile.glRead(key: ws.batch.raw("batch-key")) {
                case .ok(let r): ws.batch = r
                case .miss: ws.batch.setInt("batch-nos", 99999)
                case .error: break
                }
                ws.dates.uBin = Int(ws.batch.int("entered"))
                ws.dates.zz060()
                GLPrint.write(s, line4(ws, p.int("batch")), after: 2)
                ws.lineCnt += 2
            } else if ws.z != 99 && p.int("batch") != ws.batch.int("batch-nos") {
                continue
            }
            var side = Cobol.x("", 8)
            if p.int("vat-ac") != 0 { side = Cobol.x(p.str("post-vat-side"), 8) }
            let line7 = Pic.edit("zzzz9bbbb", value: p.int("post-number"), scale: 0) + Cobol.x(p.str("post-code"), 5) + Cobol.x(p.str("post-date"), 12)
                + Pic.edit("zzz9.99b", value: p.int("post-dr"), scale: 2) + Pic.edit("99bb", value: p.int("dr-pc"), scale: 0)
                + Pic.edit("zzz9.99b", value: p.int("post-cr"), scale: 2) + Pic.edit("99bb", value: p.int("cr-pc"), scale: 0)
                + Pic.edit("zzzzzzzz9.99bb", value: abs(p.int("post-amount")), scale: 2)
                + Pic.edit("zzzzzzzz9.99bb", value: abs(p.int("vat-amount")), scale: 2)
                + bwz("zzz9.99", p.int("vat-ac"), 2) + bwz("bz9bbbbbb", p.int("vat-pc"), 0) + side + Cobol.x(p.str("post-legend"), 32)
            GLPrint.write(s, line7, after: 1)
            ws.lineCnt += 1
            // get-description
            func check(_ nos: String, _ pc: String) -> Bool {
                ws.ledger.setInt("ledger-nos", p.int(nos)); ws.ledger.setInt("ledger-pc", p.int(pc))
                switch ws.ledgerFile.glRead(key: ws.ledger.raw("ledger-key")) {
                case .ok(let r): ws.ledger = r; return true
                case .error: return true
                case .miss: ws.truth = 0; return false
                }
            }
            ws.drError = check("post-dr", "dr-pc") ? Cobol.x("", 12) : Cobol.x(ws.t("p_error_mark"), 12)
            ws.crError = check("post-cr", "cr-pc") ? Cobol.x("", 12) : Cobol.x(ws.t("p_error_mark"), 12)
            if ws.drError != Cobol.x("", 12) || ws.crError != Cobol.x("", 12) {
                GLPrint.write(s, Cobol.x("", 24) + ws.drError + ws.crError, after: 1)
                ws.lineCnt += 1
            }
            if ws.lineCnt > Int(s.sys.int("page-lines")) - 6 { headings(ws) }
            ws.batch.setInt("actual-gross", abs(ws.batch.int("actual-gross") + p.int("post-amount")))
            ws.batch.setInt("actual-vat", abs(ws.batch.int("actual-vat") + p.int("vat-amount")))
        }
        // end-batch
        if ws.z != 99 {
            if ws.truth != 1 {
                ws.batch.setInt("batch-status", 0)
            } else {
                let b = ws.batch
                let l9 = Pic.edit("zzzzzzzzz9.99bb", value: abs(b.int("input-gross") - b.int("input-vat")), scale: 2)
                    + Pic.edit("zzzzzzzzz9.99bb", value: b.int("input-vat"), scale: 2)
                let l10 = Pic.edit("zzzzzzzzz9.99bb", value: b.int("actual-gross"), scale: 2)
                    + Pic.edit("zzzzzzzzz9.99bb", value: b.int("actual-vat"), scale: 2)
                ws.batch.setInt("actual-gross", b.int("actual-gross") + b.int("actual-vat"))
                if ws.lineCnt > Int(s.sys.int("page-lines")) - 12 { headings(ws) }
                let pad = Cobol.x("", 20)
                GLPrint.write(s, pad + Cobol.x(ws.t("p_batch_head"), 45), after: 3)
                GLPrint.write(s, pad + Cobol.x(ws.t("p_header"), 17) + l9, after: 2)
                GLPrint.write(s, pad + Cobol.x(ws.t("p_actual"), 17) + l10, after: 2)
                let ok = ws.batch.int("input-gross") == ws.batch.int("actual-gross") && ws.batch.int("input-vat") == ws.batch.int("actual-vat")
                ws.batch.setInt("batch-status", ok ? 1 : 0)
                GLPrint.write(s, pad + Cobol.x(ws.t("p_stars"), 30), after: 3)
                GLPrint.write(s, pad + Cobol.x(ws.t(ok ? "p_verified" : "p_in_error"), 30), after: 1)
                GLPrint.write(s, pad + Cobol.x(ws.t("p_stars"), 30), after: 1)
            }
        }
        ws.ledgerFile.close()
        GLPrint.close(s)
    }
}
