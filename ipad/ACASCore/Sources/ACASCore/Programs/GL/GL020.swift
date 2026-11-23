import Foundation

/// general/gl020.cbl: Default File Utilities (デフォルト勘定の登録・修正・表示)
enum GL020 {
    static let progName = "GL020 (3.00.02)"

    final class WS {
        var w = 1, lin = 7, cole = 1, lin2 = 0, col2 = 0
        var reply = " "
        var ledger = Record(GL.ledgerLayout)
        var weError = 0
        var file: IndexedFile
        init(_ s: Session) { file = GL.ledgerFile(s) }
        var curs: Int { lin * 100 + cole }
        func setCurs2(_ v: Int) { lin2 = (v / 100) % 100; col2 = v % 100 }
        var curs2: Int { lin2 * 100 + col2 }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let ws = WS(s)
        while true {
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(s.t("gl020.title"), at: 129, color: 2)
            c.display(GL.zz070(s), at: 171, color: 2)
            c.display(s.sys.str("usera"), at: 301, color: 2)
            if ws.file.open() != "00" {
                c.display(s.t("gl020.gl100"), at: 2301, color: 4)
                c.display(s.t("gl020.gl010"), at: 2401, color: 2)
                _ = try c.accept(at: 2420, size: 1, color: 2)
                return
            }
            c.display(s.t("gl020.select"), at: 501, color: 2)
            c.display(s.t("gl020.opt1"), at: 806, color: 2)
            c.display(s.t("gl020.opt2"), at: 1006, color: 2)
            c.display(s.t("gl020.opt3"), at: 1206, color: 2)
            c.display(s.t("gl020.opt9"), at: 2006, color: 2)
            let r = Cobol.moveNumeric(try c.accept(at: 544, size: 1, kind: .numeric, options: [.auto], color: 6), digits: 1, scale: 0)
            if r == 1 { try setUp(s, ws) }
            if r == 2 { try amend(s, ws) }
            if r == 3 { try show(s, ws) }
            if r == 9 { return }
        }
    }

    /// accept-money: 9(4).99 形式で amt-ok を入力
    static func acceptMoney(_ s: Session, _ ws: WS, _ amt: Int64) throws -> Int64 {
        let c = s.console
        let shown = Cobol.z(amt / 100, 4) + "." + Cobol.z(amt % 100, 2)
        c.display(shown, at: ws.curs2, color: 3)
        let a = Array(try c.accept(at: ws.curs2, size: 7, initial: shown, options: [.update], color: 3))
        return Cobol.moveNumeric(String(a[0..<4]), digits: 4, scale: 0) * 100 + Cobol.moveNumeric(String(a[5..<7]), digits: 2, scale: 0)
    }

    static func setUp(_ s: Session, _ ws: WS) throws {
        let c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(GL.zz070(s), at: 171, color: 2)
        c.display(s.t("gl020.setup_title"), at: 129, color: 2)
        c.display(s.sys.str("usera"), at: 301, color: 2)
        while true {
            c.display(s.t("gl020.add_existing"), at: 501, color: 2)
            c.display(s.t("gl020.nb1"), at: 701, color: 2)
            c.display(s.t("gl020.nb2"), at: 806, color: 2)
            c.display(s.t("gl020.destroys"), at: 827, color: 0x74, highlight: true)
            c.display(s.t("gl020.existing_defaults"), at: 836, color: 2)
            ws.reply = Cobol.upper(try c.accept(at: 537, size: 1, color: 4))
            if ws.reply == "N" { try fileInit(s, ws) }
            if ws.reply == "Y" || ws.reply == "N" { break }
        }
        for l in [501, 601, 701, 801] { c.display(" ", at: l, eraseEOL: true) }
        inputHeadings(s, ws)
        let autoVat = s.sys.str("auto-vat") == "Y"
        func jump(_ w: Int) { ws.cole = 41; ws.w = w; ws.lin = w - 10 }
        input: while true {
            // get-input
            c.display(Cobol.z(ws.w, 2), at: ws.curs, color: 2)
            ws.setCurs2(ws.curs + 3)
            GL.setDefAcs(s, ws.w, try acceptMoney(s, ws, GL.defAcs(s, ws.w)))
            if c.crtStatus == 2005 && ws.w < 30 { jump(30); continue }
            if c.crtStatus == 2005 {
                if ws.w < 31 && autoVat { jump(31); continue }
                break
            }
            if GL.defAcs(s, ws.w) == 0 && ws.w < 30 { jump(30); continue }
            if GL.defAcs(s, ws.w) == 0 && autoVat { jump(31); continue }
            getDescription(s, ws)
            if ws.weError == 255 { continue }
            ws.setCurs2(ws.curs + 12)
            c.display(ws.ledger.str("ledger-name"), at: ws.curs2, color: 3)
            ws.col2 += 20
            c.display("[  ] ", at: ws.curs2, color: 2)
            ws.col2 += 1
            var codes = GL.defCodes(s, ws.w)
            c.display(codes, at: ws.curs2, color: 3)
            if ws.w < 30 {
                codes = Cobol.upper(try c.accept(at: ws.curs2, size: 2, initial: codes, options: [.update], color: 3))
            } else {
                codes = ws.w == 30 ? "OB" : (ws.w == 31 ? "VI" : "VO")
            }
            c.display(codes, at: ws.curs2, color: 2)
            if c.crtStatus == 2005 && ws.w < 30 { jump(30); continue }
            if c.crtStatus == 2005 {
                if autoVat && ws.w < 31 { jump(31); continue }
                break
            }
            GL.setDefCodes(s, ws.w, codes)
            // vat-check
            while true {
                ws.setCurs2(ws.curs + 38)
                var vat = GL.defVat(s, ws.w)
                c.display(vat, at: ws.curs2, color: 3)
                if ws.w < 30 {
                    vat = Cobol.upper(try c.accept(at: ws.curs2, size: 1, initial: vat, options: [.update], color: 3))
                } else {
                    vat = "N"
                    c.display(vat, at: ws.curs2, color: 3)
                }
                if c.crtStatus == 2005 {
                    if autoVat && ws.w < 31 { jump(31); continue input }
                    break input
                }
                GL.setDefVat(s, ws.w, vat)
                if ["I", "N", "O"].contains(vat) { break }
            }
            ws.w += 1
            if ws.w > 32 { break }
            if ws.w == 17 { ws.cole = 41; ws.lin = 6 }
            ws.lin += 1
        }
        try amend(s, ws)
    }

    static func amend(_ s: Session, _ ws: WS) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("gl020.amend_title"), at: 127, color: 2)
        c.display(s.toDay, at: 171, color: 2)
        c.display(s.sys.str("usera"), at: 301, color: 2)
        inputHeadings(s, ws)
        while true {
            c.display(s.t("gl020.enter_number"), at: 2401, color: 2)
            var y = Int(Cobol.moveNumeric(try c.accept(at: 2445, size: 2, kind: .numeric, initial: "00", options: [.update], color: 6), digits: 2, scale: 0))
            if y == 0 { break }
            if y < 1 || y > 32 { continue }
            ws.w = y
            if y > 16 { y -= 16; ws.cole = 41 } else { ws.cole = 1 }
            ws.lin = y + 6
            c.display(Cobol.z(ws.w, 2), at: ws.curs, color: 2)
            ws.setCurs2(ws.curs + 3)
            GL.setDefAcs(s, ws.w, try acceptMoney(s, ws, GL.defAcs(s, ws.w)))
            getDescription(s, ws)
            if ws.weError == 255 { continue }
            ws.setCurs2(ws.curs + 12)
            c.display(ws.ledger.str("ledger-name"), at: ws.curs2, color: 3)
            ws.col2 += 20
            c.display("[  ] ", at: ws.curs2, color: 2)
            ws.col2 += 1
            let codes = try c.accept(at: ws.curs2, size: 2, initial: GL.defCodes(s, ws.w), options: [.update], color: 3)
            GL.setDefCodes(s, ws.w, codes)
            ws.setCurs2(ws.curs + 33)
            c.display(codes, at: ws.curs2, color: 3)
            while true {
                ws.setCurs2(ws.curs + 38)
                let vat = try c.accept(at: ws.curs2, size: 1, initial: GL.defVat(s, ws.w), options: [.update], color: 3)
                if ["I", "N", "O"].contains(vat) { GL.setDefVat(s, ws.w, vat); break }
            }
        }
        ws.file.close()
    }

    static func show(_ s: Session, _ ws: WS) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("gl020.show_title"), at: 126, color: 2)
        c.display(s.toDay, at: 171, color: 2)
        c.display(s.sys.str("usera"), at: 301, color: 2)
        inputHeadings(s, ws)
        c.display(s.t("gl020.end_listing"), at: 2301, color: 2)
        _ = try c.accept(at: 2379, size: 1, color: 6)
        ws.file.close()
    }

    static func fileInit(_ s: Session, _ ws: WS) throws {
        let c = s.console
        c.display(s.t("gl020.enter_password"), at: 551, color: 2)
        let pw = try c.accept(at: 570, size: 4, color: 6)
        c.display("****", at: 570, color: 2)
        if Maps01.encodePassword(pw) != s.sys.str("pass-word") { ws.reply = "Z"; return }
        GL.initDefaults(s)
    }

    static func inputHeadings(_ s: Session, _ ws: WS) {
        let c = s.console
        c.display(s.t("gl020.h_acnos"), at: 504, color: 2)
        c.display(s.t("gl020.h_codevat"), at: 533, color: 2)
        c.display(s.t("gl020.h_acnos"), at: 544, color: 2)
        c.display(s.t("gl020.h_codevat"), at: 573, color: 2)
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
            c.display(Cobol.z(ws.w, 2), at: ws.curs, color: 2)
            ws.setCurs2(ws.curs + 2)
            c.display("[       ]", at: ws.curs2, color: 2)
            ws.col2 += 30
            c.display("[  ] [ ]", at: ws.curs2, color: 2)
        }
        each {
            ws.setCurs2(ws.curs + 3)
            let acs = GL.defAcs(s, ws.w)
            c.display(Cobol.z(acs / 100, 4) + "." + Cobol.z(acs % 100, 2), at: ws.curs2, color: 3)
            if acs != 0 {
                getDescription(s, ws)
                if ws.weError != 255 {
                    ws.setCurs2(ws.curs + 12)
                    c.display(ws.ledger.str("ledger-name"), at: ws.curs2, color: 3)
                    ws.col2 += 20
                    c.display("[  ] ", at: ws.curs2, color: 2)
                }
            }
            ws.setCurs2(ws.curs + 33)
            c.display(GL.defCodes(s, ws.w), at: ws.curs2, color: 3)
            ws.col2 += 5
            c.display(GL.defVat(s, ws.w), at: ws.curs2, color: 3)
        }
        ws.w = 1; ws.cole = 1; ws.lin = 7
    }

    static func getDescription(_ s: Session, _ ws: WS) {
        ws.ledger.setInt("ledger-nos", GL.defAcs(s, ws.w))
        ws.ledger.set("ledger-pc", "00")
        ws.weError = 0
        if let r = ws.file.read(key: ws.ledger.raw("ledger-key")) { ws.ledger = r } else { ws.weError = 255 }
    }
}
