import Foundation

/// incomplete_records_system/irs010.cbl: 勘定科目ファイルの保守 (登録・変更・表示・印刷・エクスポート・インポート)
enum IRS010 {
    static let progName = "irs010 (3.01.11)"
    static let wsLines = 24

    final class State {
        var menuReply = " "
        var wsReply = " "
        var inputType = " "
        var inputType2 = " "
        var nlAc2 = " "
        var counter = 0
        var archiveName = Cobol.x("coa-archived.txt", 32)
        var exportFormat = "T"
        var lin = 0
        var acceptLines = 0
        var nl = IRS.newNL()
        var subInput: Bool { inputType == "y" || inputType == "Y" }
    }

    static func run(_ s: Session) throws {
        let ctx = IRS.context(s)
        let c = s.console
        let st = State()
        ctx.fileNames = ctx.sys.str("system-files")
        while true {
            if ctx.sys.int("first-time-flag") == 0 {
                try clearNL(s, st)
                if st.menuReply == "0" { ctx.sys.setInt("first-time-flag", 1) }
            }
            st.menuReply = "0"
            IRS.heading(s, prog: progName, titleKey: "irs010.title", col: 29)
            IRS.clientLine(s)
            c.display(s.t("irs010.select"), at: 501, color: 2)
            c.display("]", at: 545, color: 2)
            for (k, at) in [("irs010.item_1", 806), ("irs010.item_2", 1006), ("irs010.item_3", 1206), ("irs010.item_4", 1406),
                            ("irs010.item_5", 1506), ("irs010.item_6", 1606), ("irs010.item_9", 1806)] {
                c.display(s.t(k), at: at, color: 2)
            }
            c.display(s.t("irs010.menu_footer"), at: 2301, color: 7, highlight: true)
            st.menuReply = try c.accept(at: 544, size: 1, initial: st.menuReply, options: [.update, .auto, .prompt], color: 6)
            let f = c.crtStatus
            if st.menuReply == "1" || f == 1001 { try setUp(s, st); continue }
            if st.menuReply == "2" || f == 1002 { try amend(s, st); continue }
            if st.menuReply == "3" || f == 1003 { try show(s, st); continue }
            if st.menuReply == "4" || f == 1004 { try listing(s, st); continue }
            if st.menuReply == "5" || f == 1005 { try exportCoA(s, st); continue }
            if st.menuReply == "6" || f == 1006 { try importCoA(s, st); continue }
            if st.menuReply == "9" || f == 2005 { return }
        }
    }

    // MARK: 画面部品

    static func rowTemplate(_ s: Session) -> String { "[     ]           [ ]             [     ]   [                        ]   [ ]" }

    static func setupAmendScreen3(_ s: Session) {
        let c = s.console
        IRS.clientLine(s)
        c.display(s.t("irs010.columns"), at: 402, color: 2, highlight: true)
        c.display(" ", at: 501, color: 2, eraseEOL: true)
        // occurs 16 / line plus 1 は実機では 1 行 (6 行目) だけ表示される
        c.display(rowTemplate(s), at: 602, color: 2)
    }

    static func setupDisplay(_ s: Session, _ st: State) {
        var lin = 22
        while lin <= st.acceptLines {
            s.console.display(rowTemplate(s), at: lin * 100 + 2, color: 2)
            lin += 1
        }
    }

    static func acceptNum(_ s: Session, _ at: Int, _ initial: Int) throws -> Int {
        IRS.num(try s.console.accept(at: at, size: 5, kind: .numeric, initial: Cobol.z(initial, 5), options: [.update], color: 6))
    }

    static func acceptAc(_ s: Session, _ st: State) throws {
        let c = s.console
        while true {
            st.nlAc2 = try c.accept(at: st.lin * 100 + 76, size: 1, initial: st.nlAc2, options: [.update], color: 6)
            st.nl["ac"] = st.nlAc2.uppercased()
            let ac = st.nl.str("ac")
            if ac >= "A" && ac <= "Z" { break }
        }
    }

    // MARK: set-up section

    static func setUp(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        while true {
            IRS.heading(s, prog: progName, titleKey: "irs010.setup_title", col: 30)
            IRS.clientLine(s)
            c.display(s.t("irs010.add_existing"), at: 501)
            c.display("]", at: 535)
            c.display(s.t("irs010.nb1"), at: 701, color: 7)
            c.display(s.t("irs010.nb2"), at: 806, color: 7)
            c.display(s.t("irs010.nb2_destroys"), at: 827, color: 7, reverse: true)
            c.display(s.t("irs010.nb2_chart"), at: 836, color: 7)
            c.display(s.t("irs010.setup_footer"), at: 2301, color: 7, highlight: true)
            st.menuReply = try c.accept(at: 534, size: 1, options: [.auto, .prompt], color: 6)
            st.acceptLines = wsLines - 1
            if c.crtStatus == 2005 { return }
            if st.menuReply.uppercased() == "N" { try fileInit(s, st) }
            if ["Y", "N"].contains(st.menuReply.uppercased()) { break }
        }
        try IRSub1.open(s, .io)
        IRS.heading(s, prog: progName, titleKey: "irs010.setup_title", col: 30)
        setupAmendScreen3(s)
        setupDisplay(s, st)
        st.lin = 6
        input: while true {
            c.display(" " + rowTemplate(s), at: st.lin * 100 + 1, color: 2)
            var gotoReturn = false
            if !st.subInput {
                st.nl.setInt("owning", 0); st.nl.setInt("sub-nominal", 0)
                st.nl.setInt("owning", Int64(try acceptNum(s, st.lin * 100 + 3, 0)))
                if st.nl.int("owning") == 0 { break input }
                if IRSub1.readIndexed(s, &st.nl) != 2 {
                    c.display(st.nl.str("name"), at: st.lin * 100 + 47, color: 6)
                    c.display(s.t("irs010.exists"), at: wsLines * 100 + 1, reverse: true)
                    continue input
                }
                c.display(Cobol.x("", 78), at: wsLines * 100 + 1)
                while true {
                    st.inputType2 = try c.accept(at: st.lin * 100 + 21, size: 1, initial: st.inputType2, options: [.update], color: 6)
                    st.inputType = st.inputType2.uppercased()
                    if st.inputType == "N" || st.inputType == "Y" { break }
                }
                st.nl["name"] = ""
                st.nl["name"] = try c.accept(at: st.lin * 100 + 47, size: 24, initial: "", options: [.update], color: 6)
                try acceptAc(s, st)
                st.nl["type"] = "O"
                ctx.sys.setInt("first-time-flag", 1)
            } else {
                sub: while true {
                    st.nl.setInt("sub-nominal", 0)
                    st.nl.setInt("sub-nominal", Int64(try acceptNum(s, st.lin * 100 + 37, 0)))
                    if st.nl.int("sub-nominal") == 0 {
                        st.inputType = "N"
                        st.lin -= 1
                        gotoReturn = true
                        break sub
                    }
                    if IRSub1.readIndexed(s, &st.nl) == 2 {
                        c.display(Cobol.x("", 78), at: wsLines * 100 + 1)
                        break sub
                    }
                    c.display(st.nl.str("name"), at: st.lin * 100 + 37)
                    c.display(s.t("irs010.exists_key"), at: wsLines * 100 + 1, reverse: true)
                    c.display(st.nl.str("key"), at: wsLines * 100 + 45, color: 3)
                }
                if !gotoReturn {
                    st.nl["name"] = ""
                    st.nl["name"] = try c.accept(at: st.lin * 100 + 47, size: 24, initial: "", options: [.update], color: 6)
                    st.nl["type"] = "S"
                }
            }
            if !gotoReturn {
                IRS.zeroAmounts(&st.nl)
                try IRSub1.write(s, &st.nl)
            }
            // main02-return
            st.lin += 1
            c.display(Cobol.x("", 80), at: st.lin * 100 + 1)
            if st.lin < st.acceptLines { continue input }
            st.lin = 6
            repeat {
                c.display(Cobol.x("", 80), at: st.lin * 100 + 1)
                st.lin += 1
            } while st.lin < st.acceptLines
            st.lin = 6
        }
        IRSub1.close(s)
    }

    // MARK: amend section

    static func amend(_ s: Session, _ st: State) throws {
        let c = s.console
        func main03() {
            IRS.heading(s, prog: progName, titleKey: "irs010.amend_title", col: 28)
            setupAmendScreen3(s)
            st.acceptLines = wsLines - 1
        }
        main03()
        setupDisplay(s, st)
        try IRSub1.open(s, .io)
        st.lin = 6
        input: while true {
            st.inputType = " "
            st.nl.setInt("owning", 0); st.nl.setInt("sub-nominal", 0)
            st.nl.setInt("owning", Int64(try acceptNum(s, st.lin * 100 + 3, 0)))
            if st.nl.int("owning") == 0 { break input }
            if IRSub1.readIndexed(s, &st.nl) == 2 { continue input }
            c.display(st.nl.str("name"), at: st.lin * 100 + 47, color: 6)
            var gotoReturn = false
            var toSub = false
            jump: while true {
                st.inputType2 = try c.accept(at: st.lin * 100 + 21, size: 1, initial: st.inputType2, options: [.update], color: 6)
                st.inputType = st.inputType2.uppercased()
                if st.inputType == "D" {
                    try deleteRecord(s, st)
                    continue input
                }
                if st.inputType == "N" { break jump }
                if st.inputType == "Y" { toSub = true; break jump }
            }
            if !toSub {
                st.nl["name"] = try c.accept(at: st.lin * 100 + 47, size: 24, initial: st.nl.str("name"), options: [.update], color: 6)
                try acceptAc(s, st)
                st.nl["type"] = "O"; st.inputType = "O"
            } else {
                st.nl.setInt("sub-nominal", 0)
                st.nl.setInt("sub-nominal", Int64(try acceptNum(s, st.lin * 100 + 37, 0)))
                if st.nl.int("sub-nominal") == 0 {
                    st.inputType = "N"
                    st.lin -= 1
                    gotoReturn = true
                } else if IRSub1.readIndexed(s, &st.nl) != 2 {
                    c.display(st.nl.str("name"), at: st.lin * 100 + 47, color: 6)
                    st.inputType = "O"
                    st.nl["type"] = "O"
                    st.nl["name"] = try c.accept(at: st.lin * 100 + 47, size: 24, initial: st.nl.str("name"), options: [.update], color: 6)
                    try acceptAc(s, st)
                } else {
                    st.nl["name"] = try c.accept(at: st.lin * 100 + 47, size: 24, initial: st.nl.str("name"), options: [.update], color: 6)
                    st.nl["type"] = "S"; st.inputType = "S"
                    IRS.zeroAmounts(&st.nl)
                }
            }
            if !gotoReturn {
                if st.inputType == "S" { try IRSub1.write(s, &st.nl) } else { IRSub1.rewrite(s, st.nl) }
            }
            st.lin += 1
            if st.lin < st.acceptLines { continue input }
            st.lin = 6
            main03()
        }
        IRSub1.close(s)
    }

    // MARK: show section

    static func show(_ s: Session, _ st: State) throws {
        let c = s.console
        let sys = IRS.context(s).sys
        func display1() {
            st.counter += 1
            c.eraseScreen()
            c.display(sys.str("suser"), at: 101, color: 2)
            c.display(s.t("irs.system_name"), at: 128, color: 7, reverse: true)
            c.display(sys.str("run-date"), at: 173, color: 2)
            c.display(s.t("irs.client"), at: 301, color: 2)
            c.display(sys.str("client"), at: 310, color: 3)
            c.display(s.t("irs010.directory"), at: 332, color: 2)
            c.display(s.t("irs010.page"), at: 373, color: 2)
            c.display(Pic.edit("zz9", value: Int64(st.counter % 1000), scale: 0), at: 378, color: 3)
            c.display(s.t("irs010.show_columns"), at: 511, color: 7)
        }
        st.counter = 0
        st.lin = 7
        st.acceptLines = wsLines - 2
        let err = try IRSub1.open(s, .input)
        display1()
        var quit = false
        if err != 1 {
            while true {
                if IRSub1.readNext(s, &st.nl) == 3 { break }
                var owning = st.nl.int("owning")
                let sub = st.nl.int("sub-nominal")
                if sub != 0 { owning = 0 }
                func bwz(_ v: Int64) -> String { v == 0 ? "     " : Pic.edit("zzzzz", value: v, scale: 0) }
                c.display(bwz(owning), at: st.lin * 100 + 12, color: 3)
                c.display(bwz(sub), at: st.lin * 100 + 23, color: 3)
                c.display(st.nl.str("name"), at: st.lin * 100 + 36, color: 3)
                c.display(st.nl.str("ac"), at: st.lin * 100 + 66, color: 3)
                st.lin += 1
                if st.lin < st.acceptLines { continue }
                c.display(s.t("irs010.next_or_quit"), at: wsLines * 100 + 18, color: 6)
                let r = try c.accept(at: wsLines * 100 + 66, size: 1, options: [.auto], color: 6)
                st.wsReply = r.uppercased()
                if st.wsReply == "X" { quit = true; break }
                c.display(" ", at: 101, eraseEOS: true)
                st.lin = 7
                display1()
            }
        }
        if !quit {
            c.display(s.t("irs010.end_display"), at: wsLines * 100 + 18, color: 6, eraseEOL: true)
            st.wsReply = try c.accept(at: wsLines * 100 + 56, size: 1, color: 6)
        }
        IRSub1.close(s)
    }

    // MARK: listing section

    static func listing(_ s: Session, _ st: State) throws {
        let sys = IRS.context(s).sys
        st.counter = 0
        try IRSub1.open(s, .input)
        let p = IRS.Printer(s, "prt-1")
        var lineCnt = 85
        while true {
            if IRSub1.readNext(s, &st.nl) == 3 { break }
            if lineCnt > 80 {
                st.counter += 1
                let line1 = Cobol.x(sys.str("suser"), 24) + "    " + Cobol.x(s.t("report.irs.system_name"), 26)
                    + Cobol.x("", 18) + sys.str("run-date")
                if st.counter != 1 { p.writePage(line1) } else { p.write(line1, after: 1) }
                p.write(Cobol.x(sys.str("client"), 24) + Cobol.x("", 7) + Cobol.x(s.t("report.irs010.directory"), 18)
                    + Cobol.x("", 22) + Cobol.x(s.t("report.irs010.page"), 6)
                    + Pic.edit("zz9", value: Int64(st.counter % 1000), scale: 0), after: 2)
                p.write(Cobol.x("", 11) + Cobol.x(s.t("report.irs010.columns"), 56) + Cobol.x(s.t("report.irs010.ac_type"), 12), after: 2)
                p.write("", after: 1)
                lineCnt = 6
            }
            var owning = st.nl.int("owning")
            let sub = st.nl.int("sub-nominal")
            if sub != 0 { owning = 0 }
            func bwz(_ v: Int64) -> String { v == 0 ? "     " : Pic.edit("zzzz9", value: v, scale: 0) }
            p.write(Cobol.x("", 14) + bwz(owning) + Cobol.x("", 12) + bwz(sub) + Cobol.x("", 8)
                + Cobol.x(st.nl.str("name"), 24) + Cobol.x("", 7) + st.nl.str("ac"), after: 1)
            lineCnt += 1
        }
        IRSub1.close(s)
        p.spool()
    }

    // MARK: file-init section

    static func fileInit(_ s: Session, _ st: State) throws {
        let c = s.console
        c.display(s.t("irs010.enter_password"), at: 551, color: 2)
        let pass = try c.accept(at: 570, size: 4, options: [.secure])
        if pass == IRS.context(s).sys.str("pass-word") {
            try IRSub1.open(s, .output)
            IRSub1.close(s)
        } else {
            st.wsReply = "Z"
        }
    }

    // MARK: delete-record section

    static func deleteRecord(_ s: Session, _ st: State) throws {
        if IRSub1.readIndexed(s, &st.nl) == 2 { return }
        IRSub1.delete(s, &st.nl)
        var saveOwning = st.nl.int("owning")
        var err = IRSub1.start(s, &st.nl, .notLess)
        // レガシーは START 失敗時の we-error を見ずに loop06 へ入る
        repeat {
            if st.nl.int("owning") != saveOwning { return }
            IRSub1.delete(s, &st.nl)
            saveOwning = st.nl.int("owning")
            if st.nl.int("sub-nominal") != 0 {
                // レガシーは副科目ポインタの削除を試みるが、FD 側のキーが更新されないため何も削除されない
                st.nl.setInt("owning", st.nl.int("sub-nominal"))
                st.nl.setInt("sub-nominal", 0)
                st.nl.setInt("owning", saveOwning)
            }
            IRSub1.close(s)
            try IRSub1.open(s, .io)
            st.nl.setInt("sub-nominal", 0)
            err = IRSub1.start(s, &st.nl, .notLess)
        } while err == 0
    }

    // MARK: ea-Export-CoA section

    static func exportCoA(_ s: Session, _ st: State) throws {
        let c = s.console
        c.display(s.t("irs010.export_1"), at: 101, color: 6, eraseEOS: true)
        c.display(s.t("irs010.export_2"), at: 221, color: 6)
        c.display(s.t("irs010.continue"), at: 401, color: 7)
        st.menuReply = try c.accept(at: 415, size: 1)
        if st.menuReply == "N" || st.menuReply == "n" { st.menuReply = "1"; return }
        c.display(s.t("irs010.export_name"), at: 601, color: 6)
        st.archiveName = try c.accept(at: 626, size: 32, initial: st.archiveName, options: [.update])
        if Cobol.rtrim(st.archiveName).isEmpty || c.crtStatus == 2005 {
            c.display(s.t("irs010.quitting"), at: 1001, eraseEOL: true)
            return
        }
        c.display(s.t("irs010.export_format"), at: 801, color: 6)
        st.exportFormat = try c.accept(at: 839, size: 1, initial: st.exportFormat, options: [.update]).uppercased()
        if st.exportFormat != "T" && st.exportFormat != "C" { return }
        let path = s.irsDir + Cobol.rtrim(st.archiveName)
        s.store.writeRaw(path, [])
        st.counter = 0
        try IRSub1.open(s, .input)
        while true {
            if IRSub1.readNext(s, &st.nl) == 3 { break }
            if st.nl.int("sub-nominal") != 0 { st.nl["type"] = "S" }
            let owning = Cobol.z(st.nl.int("owning"), 5), sub = Cobol.z(st.nl.int("sub-nominal"), 5)
            let line: String
            if st.exportFormat == "T" {
                line = "T" + owning + sub + st.nl.str("type") + Cobol.x(st.nl.str("name"), 24) + st.nl.str("ac")
            } else {
                line = "C" + owning + "," + sub + ",\"" + Cobol.x(st.nl.str("name"), 24) + "\"," + st.nl.str("ac") + ","
                    + st.nl.str("type") + " "
            }
            let t = Cobol.rtrim(line)
            s.store.appendRaw(path, SJIS.encode(t, size: CellWidth.of(t)) + [0x0a])
            st.counter += 1
        }
        c.display(s.t("irs010.export_total"), at: 2001)
        c.display(Cobol.z(st.counter % 10000, 4), at: 2034)
        c.display(s.t("irs010.note_count"), at: 2201)
        st.wsReply = try c.accept(at: 2237, size: 1)
        IRSub1.close(s)
    }

    // MARK: fa-Import-CoA section

    static func importCoA(_ s: Session, _ st: State) throws {
        let c = s.console
        c.display(s.t("irs010.import_1"), at: 101, color: 6, eraseEOS: true)
        c.display(s.t("irs010.import_2"), at: 201, color: 6)
        c.display(s.t("irs010.import_3"), at: 301, color: 6)
        c.display(s.t("irs010.import_4"), at: 401, color: 6)
        c.display(s.t("irs010.warning"), at: 714, color: 4)
        c.display(s.t("irs010.before_yes"), at: 901, color: 6)
        c.display(s.t("irs010.otherwise_no"), at: 1001, color: 6)
        c.display(s.t("irs010.continue"), at: 1201, color: 7)
        st.menuReply = try c.accept(at: 1215, size: 1)
        if st.menuReply == "N" || st.menuReply == "n" { st.menuReply = "1"; return }
        c.display(s.t("irs010.import_name"), at: 1501, color: 6)
        st.archiveName = try c.accept(at: 1527, size: 32, initial: st.archiveName, options: [.update], color: 6)
        if Cobol.rtrim(st.archiveName).isEmpty || c.crtStatus == 2005 {
            c.display(s.t("irs010.quitting"), at: 1501, eraseEOL: true)
            return
        }
        guard let raw = s.store.readRaw(s.irsDir + Cobol.rtrim(st.archiveName)) else {
            c.display(s.t("irs010.import_open_fail"), at: 2301)
            st.wsReply = try c.accept(at: 2360, size: 1)
            return
        }
        if try IRSub1.open(s, .output) == 1 {
            c.display(s.t("irs010.accounts_open_fail"), at: 2301)
            st.wsReply = try c.accept(at: 2365, size: 1)
            return
        }
        IRSub1.close(s)
        if try IRSub1.open(s, .io) != 0 {
            c.display(s.t("irs010.accounts_open_fail"), at: 2301)
            st.wsReply = try c.accept(at: 2365, size: 1)
            return
        }
        st.counter = 0
        IRS.zeroAmounts(&st.nl)
        var lines = raw.split(separator: 0x0a, omittingEmptySubsequences: false).map { Array($0) }
        if let l = lines.last, l.isEmpty { lines.removeLast() }
        for l in lines {
            var b = Array(l.prefix(44))
            while b.count < 44 { b.append(0x20) }
            if b[0] != UInt8(ascii: "T") {
                c.display(s.t("irs010.import_text_only"), at: 2001, highlight: true)
                c.display(s.t("irs010.hit_return_menu"), at: 2101)
                st.wsReply = try c.accept(at: 2122, size: 1)
                return
            }
            let sub = IRS.num(SJIS.decode(b[6..<11]))
            st.nl.setInt("owning", Int64(IRS.num(SJIS.decode(b[1..<6]))))
            st.nl.setInt("sub-nominal", Int64(sub))
            st.nl["type"] = sub == 0 ? "O" : "S"
            st.nl.setRaw("name", Array(b[12..<36]))
            st.nl.setRaw("ac", [b[36]])
            try IRSub1.write(s, &st.nl)
            st.counter += 1
        }
        c.display(s.t("irs010.import_total"), at: 2001)
        c.display(Cobol.z(st.counter % 10000, 4), at: 2026)
        c.display(s.t("irs010.note_count"), at: 2201)
        st.wsReply = try c.accept(at: 2237, size: 1)
        IRSub1.close(s)
    }

    // MARK: zz000-clear-NL section

    static func clearNL(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        if !s.store.exists(s.irsDir + Cobol.rtrim(ctx.sys.str("fn-1"))) { st.menuReply = "0"; return }
        if s.store.exists(s.irsDir + Cobol.rtrim(ctx.sys.str("fn-4"))) { st.menuReply = "0"; return }
        c.display(" ", at: 101, eraseEOS: true)
        c.display(s.t("irs010.first_1"), at: 101, color: 6)
        c.display(s.t("irs010.first_2"), at: 221, color: 6)
        c.display(s.t("irs010.first_3"), at: 401, color: 6)
        c.display(s.t("irs010.first_4"), at: 533, color: 6)
        c.display(s.t("irs010.warning"), at: 714, color: 4)
        c.display(s.t("irs010.before_yes"), at: 901, color: 6)
        c.display(s.t("irs010.otherwise_no"), at: 1001, color: 6)
        c.display(s.t("irs010.continue"), at: 1201, color: 7)
        st.menuReply = try c.accept(at: 1215, size: 1)
        if st.menuReply == "N" || st.menuReply == "n" { st.menuReply = "1"; return }
        c.display(s.t("irs010.wait_clear"), at: 1501, color: 6)
        if try IRSub1.open(s, .io) != 0 {
            IRSub1.close(s)
            st.menuReply = "1"
            return
        }
        while true {
            if IRSub1.readNext(s, &st.nl) == 3 {
                IRSub1.close(s)
                st.menuReply = "0"
                return
            }
            IRS.zeroAmounts(&st.nl)
            IRSub1.rewrite(s, st.nl)
        }
    }
}
