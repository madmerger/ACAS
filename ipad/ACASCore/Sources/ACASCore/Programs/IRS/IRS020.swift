import Foundation

/// incomplete_records_system/irs020.cbl: デフォルト科目ファイルの保守と決算書見出しの設定
enum IRS020 {
    static let progName = "irs020 (3.01.10)"

    final class State {
        var menuReply = 0
        var wsReply = " "
        var w = 0
        var y = 0
        var lin = 0
        var cole = 0
        var wsCodes = "  "
        var wsCodes2 = "  "
        var wsVat = " "
        var wsVat2 = " "
        var nl = IRS.newNL()
        var final = [UInt8](repeating: 0x20, count: IRS.finalSize)
        var curs: Int { lin * 100 + cole }
    }

    static func setupAmendScreen3(_ s: Session, _ st: State) {
        let c = s.console
        IRS.clientLine(s)
        c.display(s.t("irs020.col_ac"), at: 504, color: 2)
        c.display(s.t("irs020.col_desc"), at: 514, color: 2)
        c.display(s.t("irs020.col_code_vat_ac"), at: 533, color: 2)
        c.display(s.t("irs020.col_desc"), at: 554, color: 2)
        c.display(s.t("irs020.col_code_vat"), at: 573, color: 2)
        c.display(" ", at: 601, color: 2, eraseEOL: true)
        // occurs 16 / line plus 1 は実機では 1 行 (7 行目) だけ表示される
        c.display("01 [00000]                      [AB] [C]17 [00000]                      [DE] [F", at: 701, color: 2)
        for w in 1...16 {
            c.display(Cobol.z(w, 2), at: (6 + w) * 100 + 1, color: 2)
            c.display(Cobol.z(w + 16, 2), at: (6 + w) * 100 + 41, color: 2)
        }
    }

    // MARK: set-up section

    static func setUp(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        while true {
            IRS.heading(s, prog: progName, titleKey: "irs020.setup_title", col: 29)
            IRS.clientLine(s)
            c.display(s.t("irs020.add_existing"), at: 501)
            c.display("]", at: 538)
            c.display(s.t("irs010.nb1"), at: 701, color: 7)
            c.display(s.t("irs010.nb2"), at: 806, color: 7)
            c.display(s.t("irs010.nb2_destroys"), at: 827, color: 7, reverse: true)
            c.display(s.t("irs020.nb2_defaults"), at: 836, color: 7)
            c.display(s.t("irs010.setup_footer"), at: 2301, color: 7, highlight: true)
            st.wsReply = try c.accept(at: 537, size: 1, options: [.auto, .prompt], color: 6)
            if c.crtStatus == 2005 { return }
            if st.wsReply.uppercased() == "N" { try fileInit(s, st) }
            if ["Y", "N"].contains(st.wsReply.uppercased()) { break }
        }
        IRS.heading(s, prog: progName, titleKey: "irs020.setup_title", col: 29)
        setupAmendScreen3(s, st)
        try inputHeadings(s, st)
        input: while true {
            c.display(Cobol.z(st.w, 2), at: st.curs, color: 2)
            let acs = IRS.num(try c.accept(at: st.curs + 4, size: 5, kind: .numeric, initial: IRS.defAcRaw(ctx.dflt, st.w),
                                           options: [.update], color: 3))
            IRS.setDefAc(&ctx.dflt, st.w, acs)
            if acs == 0 {
                st.cole = 41; st.w = 30; st.lin = 20
                continue input
            }
            st.nl.setInt("owning", Int64(acs)); st.nl.setInt("sub-nominal", 0)
            if IRSub1.readIndexed(s, &st.nl) == 2 { continue input }
            c.display(st.nl.str("name"), at: st.curs + 10, color: 3)
            c.display("[  ]", at: st.curs + 32, color: 2)
            st.wsCodes = IRS.defCode(ctx.dflt, st.w)
            if st.w < 30 {
                st.wsCodes = try c.accept(at: st.curs + 33, size: 2, initial: st.wsCodes, options: [.update], color: 3)
            } else if st.w == 30 { st.wsCodes = "OB" } else if st.w == 31 { st.wsCodes = "VI" } else { st.wsCodes = "VO" }
            IRS.setDefCode(&ctx.dflt, st.w, st.wsCodes.uppercased())
            c.display(st.wsCodes, at: st.curs + 33, color: 3)
            while true {
                st.wsVat2 = IRS.defVat(ctx.dflt, st.w)
                if st.w < 30 {
                    st.wsVat2 = try c.accept(at: st.curs + 38, size: 1, color: 3)
                } else {
                    st.wsVat2 = "N"
                    c.display(st.wsVat2, at: st.curs + 38, color: 3)
                }
                st.wsVat = st.wsVat2.uppercased()
                IRS.setDefVat(&ctx.dflt, st.w, st.wsVat)
                if ["I", "N", "O"].contains(st.wsVat) { break }
            }
            st.w += 1
            if st.w > 32 { break input }
            if st.w == 17 { st.cole = 41; st.lin = 6 }
            st.lin += 1
        }
        IRSub1.close(s)
        IRSub3.write(s)
        try amend(s, st)
    }

    // MARK: amend section

    static func amend(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        IRS.heading(s, prog: progName, titleKey: "irs020.amend_title", col: 28)
        setupAmendScreen3(s, st)
        try inputHeadings(s, st)
        input: while true {
            st.y = 0
            c.display(s.t("irs020.give_default"), at: 2420, color: 2)
            st.y = IRS.num(try c.accept(at: 2445, size: 2, kind: .numeric, initial: "00", options: [.update], color: 6))
            if st.y == 0 { break input }
            if st.y < 1 || st.y > 32 { continue input }
            st.w = st.y
            if st.y > 16 { st.y -= 16; st.cole = 41 } else { st.cole = 1 }
            st.lin = st.y + 6
            c.display(Cobol.z(st.w, 2), at: st.curs, color: 2)
            let acs = IRS.num(try c.accept(at: st.curs + 4, size: 5, kind: .numeric, initial: IRS.defAcRaw(ctx.dflt, st.w),
                                           options: [.update], color: 3))
            IRS.setDefAc(&ctx.dflt, st.w, acs)
            if acs == 0 { break input }
            st.nl.setInt("owning", Int64(acs)); st.nl.setInt("sub-nominal", 0)
            if IRSub1.readIndexed(s, &st.nl) == 2 { continue input }
            c.display(st.nl.str("name"), at: st.curs + 10, color: 3)
            c.display("[  ]", at: st.curs + 32, color: 2)
            st.wsCodes = IRS.defCode(ctx.dflt, st.w)
            st.wsCodes2 = try c.accept(at: st.curs + 33, size: 2, initial: st.wsCodes2, options: [.update], color: 3)
            st.wsCodes = st.wsCodes2.uppercased()
            IRS.setDefCode(&ctx.dflt, st.w, st.wsCodes)
            c.display("[", at: st.curs + 32, color: 2)
            c.display(st.wsCodes, at: st.curs + 33, color: 3)
            c.display("]", at: st.curs + 35, color: 2)
            while true {
                st.wsVat2 = IRS.defVat(ctx.dflt, st.w)
                st.wsVat2 = try c.accept(at: st.curs + 38, size: 1, initial: st.wsVat2, options: [.update], color: 3)
                st.wsVat = st.wsVat2.uppercased()
                IRS.setDefVat(&ctx.dflt, st.w, st.wsVat)
                if ["I", "N", "O"].contains(st.wsVat) { break }
            }
        }
        IRSub1.close(s)
        IRSub3.write(s)
    }

    struct ExitProgram: Error {}

    static func run(_ s: Session) throws {
        let ctx = IRS.context(s)
        let c = s.console
        let st = State()
        ctx.fileNames = ctx.sys.str("system-files")
        do {
            while true {
                st.menuReply = 0
                IRS.heading(s, prog: progName, titleKey: "irs020.title", col: 29)
                IRS.clientLine(s, clientSize: 29)
                c.display(s.t("irs010.select"), at: 501, color: 2)
                c.display("]", at: 545, color: 2)
                for (k, at) in [("irs020.item_1", 806), ("irs020.item_2", 1006), ("irs020.item_3", 1206), ("irs020.item_4", 1406),
                                ("irs020.item_5", 1706), ("irs010.item_9", 2006)] {
                    c.display(s.t(k), at: at, color: 2)
                }
                c.display(s.t("irs020.menu_footer"), at: 2301, color: 7, highlight: true)
                let r = try c.accept(at: 544, size: 1, kind: .numeric, initial: "0", options: [.update, .auto, .prompt], color: 6)
                st.menuReply = IRS.num(r)
                let f = c.crtStatus
                if st.menuReply == 1 || f == 1001 { try setUp(s, st) }
                else if st.menuReply == 2 || f == 1002 { try amend(s, st) }
                else if st.menuReply == 3 || f == 1003 { try show(s, st) }
                else if st.menuReply == 4 || f == 1004 { try listing(s, st) }
                else if st.menuReply == 5 || f == 1005 { try setUpFinished(s, st) }
                else if st.menuReply == 9 || f == 2005 { return }
            }
        } catch is ExitProgram { return }
    }

    // MARK: Input-Headings section

    static func inputHeadings(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        if try IRSub1.open(s, .input) != 0 {
            c.display(s.t("irs020.need_chart"), at: 2301)
            c.display(s.t("irs020.hit_return_main"), at: 2401, color: 7)
            st.wsReply = try c.accept(at: 2443, size: 1)
            throw ExitProgram()
        }
        st.w = 1; st.cole = 1; st.lin = 7
        try IRSub3.read(s)
        while true {
            c.display(Cobol.z(st.w, 2), at: st.curs, color: 2)
            let acs = IRS.defAc(ctx.dflt, st.w)
            c.display(Cobol.z(acs, 5), at: st.curs + 4, color: 3)
            st.nl.setInt("owning", Int64(acs)); st.nl.setInt("sub-nominal", 0)
            if acs != 0 {
                _ = IRSub1.readIndexed(s, &st.nl)
                c.display(Cobol.x(st.nl.str("name"), 22), at: st.curs + 10, color: 3)
            }
            st.wsCodes = IRS.defCode(ctx.dflt, st.w)
            c.display(st.wsCodes, at: st.curs + 33, color: 3)
            st.wsVat = IRS.defVat(ctx.dflt, st.w)
            c.display(st.wsVat, at: st.curs + 38, color: 3)
            c.display("]", at: st.curs + 39, color: 2)
            st.w += 1
            if st.w > 32 { break }
            if st.w == 17 { st.cole = 41; st.lin = 6 }
            st.lin += 1
        }
        st.w = 1; st.cole = 1; st.lin = 7
    }

    // MARK: file-init section

    static func fileInit(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        c.display(s.t("irs020.enter_password"), at: 551, color: 2)
        let pass = try c.accept(at: 570, size: 4, options: [.update, .secure])
        if pass != ctx.sys.str("pass-word") { st.wsReply = "Z"; return }
        ctx.dflt = [UInt8](repeating: 0x30, count: IRS.defaultSize)
        IRSub3.write(s)
    }

    // MARK: Show section

    static func show(_ s: Session, _ st: State) throws {
        let c = s.console
        IRS.heading(s, prog: progName, titleKey: "irs020.display_title", col: 27)
        setupAmendScreen3(s, st)
        try inputHeadings(s, st)
        c.display(" ", at: 2301, eraseEOL: true)
        c.display(s.t("irs020.end_listing"), at: 2401, color: 7)
        st.wsReply = try c.accept(at: 2479, size: 1)
        IRSub1.close(s)
    }

    // MARK: listing section

    static func listing(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        let sys = ctx.sys
        c.display(" ", at: 101, eraseEOS: true)
        let p = IRS.Printer(s, "prt-1")
        try IRSub1.open(s, .input)
        p.write(Cobol.x(sys.str("suser"), 24) + Cobol.x("", 5) + Cobol.x(s.t("report.irs.system_name"), 25) + Cobol.x("", 17)
            + sys.str("run-date"), after: 1)
        p.write(Cobol.x(sys.str("client"), 24) + Cobol.x("", 9) + Cobol.x(s.t("report.irs020.posting_defaults"), 16), after: 2)
        p.write(Cobol.x(s.t("report.irs020.columns"), 64), after: 2)
        p.write("", after: 2)
        try IRSub3.read(s)
        for w in 1...32 {
            let acs = IRS.defAc(ctx.dflt, w)
            st.nl.setInt("owning", Int64(acs)); st.nl.setInt("sub-nominal", 0)
            var desc = Cobol.x("", 25), code = "  ", vat = " "
            if acs != 0 {
                _ = IRSub1.readIndexed(s, &st.nl)
                desc = Cobol.x(st.nl.str("name"), 25)
                code = IRS.defCode(ctx.dflt, w)
                vat = IRS.defVat(ctx.dflt, w)
            }
            let pAc = acs == 0 ? "      " : Pic.edit("zzzz9", value: Int64(acs), scale: 0) + " "
            p.write(Cobol.x("", 10) + Pic.edit("z9", value: Int64(w), scale: 0) + "  " + pAc + Cobol.x("", 5) + desc
                + "   " + code + Cobol.x("", 5) + vat, after: 1)
        }
        IRSub1.close(s)
        p.spool()
    }

    // MARK: Set-Up-Finished section

    static let finishedRows: [(left: Int, line: Int, right: Int?)] = [
        (1, 6, 15), (2, 7, 16), (3, 8, 17), (4, 9, nil), (5, 11, 18), (6, 12, 19), (7, 13, 20), (8, 14, nil),
        (9, 16, 21), (10, 17, 22), (11, 19, 23), (12, 20, 24), (13, 21, 25), (14, 22, 26),
    ]

    static func setUpFinished(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        IRSub5.read(s, &st.final)
        try IRSub1.open(s, .input)
        func ar1(_ i: Int) -> String { SJIS.decode(st.final[((i - 1) * 24)..<(i * 24)]) }
        func ar2(_ i: Int) -> String { SJIS.decode(st.final[(624 + i - 1)..<(624 + i)]) }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        retry: while true {
            if ctx.sys.str("pl-app-created") != "1" {
                ctx.sys["pl-app-created"] = "0"
                ctx.sys.setInt("pl-approp-ac", 0)
            }
            c.eraseScreen()
            c.display(s.t("irs020.fin_client"), at: 101, color: 2)
            c.display(ctx.sys.str("client"), at: 108, color: 3)
            c.display(s.t("irs020.fin_title"), at: 134, color: 7, reverse: true)
            c.display(ctx.sys.str("run-date"), at: 173, color: 2)
            c.display(s.t("irs020.fin_head_1"), at: 304, color: 2)
            c.display(s.t("irs020.fin_head_2"), at: 410, color: 2)
            for (k, at) in [("irs020.fin_income", 501), ("irs020.fin_fixed", 541), ("irs020.fin_direct", 1001),
                            ("irs020.fin_current_assets", 1041), ("irs020.fin_sundry", 1501), ("irs020.fin_current_liab", 1541),
                            ("irs020.fin_indirect", 1801), ("irs020.fin_capital", 1841), ("irs020.fin_approp", 2301)] {
                c.display(s.t(k), at: at, color: 2)
            }
            var fields: [ScreenField] = []
            var bind: [(ScreenField, Int, Bool)] = []
            for row in finishedRows {
                let l = row.line * 100
                c.display("<\(letters[row.left - 1])>   [", at: l + 3, color: 2)
                c.display("] [", at: l + 34, color: 2)
                let f1 = ScreenField(line: row.line, col: 10, size: 24, value: ar1(row.left), color: 3)
                let f2 = ScreenField(line: row.line, col: 37, size: 1, value: ar2(row.left), color: 3)
                fields += [f1, f2]; bind += [(f1, row.left, true), (f2, row.left, false)]
                if let r = row.right {
                    c.display("]    <\(letters[r - 1])>   [", at: l + 38, color: 2)
                    c.display("] [", at: l + 74, color: 2)
                    c.display("]", at: l + 78, color: 2)
                    let f3 = ScreenField(line: row.line, col: 50, size: 24, value: ar1(r), color: 3)
                    let f4 = ScreenField(line: row.line, col: 77, size: 1, value: ar2(r), color: 3)
                    fields += [f3, f4]; bind += [(f3, r, true), (f4, r, false)]
                } else {
                    c.display("]", at: l + 38, color: 2)
                }
            }
            let fAc = ScreenField(line: 23, col: 30, size: 5, kind: .numeric, pic: "9(5)",
                                  value: Cobol.z(ctx.sys.int("pl-approp-ac"), 5), color: 3)
            c.display("]", at: 2335, color: 2)
            fields.append(fAc)
            c.displayFields(fields)
            try c.acceptScreen(fields)
            for (f, i, isName) in bind {
                if isName { st.final.replaceSubrange(((i - 1) * 24)..<(i * 24), with: SJIS.encode(f.value, size: 24)) }
                else { st.final.replaceSubrange((624 + i - 1)..<(624 + i), with: SJIS.encode(f.value, size: 1)) }
            }
            ctx.sys.setInt("pl-approp-ac", Int64(IRS.num(fAc.value)))
            if ctx.sys.int("pl-approp-ac") != 0 {
                ctx.sys["pl-app-created"] = "1"
                st.nl.setInt("owning", ctx.sys.int("pl-approp-ac")); st.nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &st.nl) == 2 {
                    c.display(s.t("irs020.account_not_found"), at: 2401, color: 4)
                    c.display(s.t("irs.hit_return"), at: 2431, color: 2)
                    st.wsReply = try c.accept(at: 2455, size: 1)
                    continue retry
                }
            }
            break
        }
        IRSub5.write(s, st.final)
        IRSub1.close(s)
    }
}
