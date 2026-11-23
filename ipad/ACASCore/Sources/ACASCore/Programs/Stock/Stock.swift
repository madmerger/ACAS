import Foundation

/// stock/stock.cbl: 在庫管理メニュー
enum Stock {
    static let progName = "Stock (3.01.19)"

    static func run(_ s: Session) throws {
        let c = s.console
        var menuReply = "A"   // 起動直後は日付入力 (st000) を強制
        while true {
            // aa005-Open-System
            if s.readSystem() == nil { try mapser(s) }
            // aa010-get-system-recs
            guard let sys = s.readSystem() else {
                c.display(s.t("st.st001") + Cobol.z(s.systemFile.status == "00" ? 23 : Int(s.systemFile.status) ?? 23, 2), at: c.term.cursorLine, c.term.cursorCol)
                try s.call("maps99")
                throw StopRun()
            }
            s.sys = sys
            if s.sys.int("scycle") == 0 {
                try callSystemSetup(s)
                continue
            }
            // file-status (15) = zero: 分析ファイル未作成なら sl070 で既定値を作る
            if Array(s.sys.raw("file-statuses"))[14] == 0x30 {
                s.processFunc = 1
                try s.call("sl070")
            }
            s.toDay = Maps04.toDate(Int(s.sys.int("run-date")))
            if s.sys.int("level-4") != 1 {
                try s.call("maps99")
                return
            }
            var opDisplay = ""
            let os = s.sys.int("op-system")
            if os == 0 { opDisplay = "O/S" }
            if os == 2 { opDisplay = "Windows" }
            if os == 1 { opDisplay = "Dos" }
            if os == 4 { opDisplay = "OS/2" }
            if os == 3 { opDisplay = "Mac" }
            if os == 5 { opDisplay = "Unix" }
            if os == 6 { opDisplay = "Linux" }
            // バックアップスクリプト (ACAS_BIN/acasbkup.*) の有無。端末内では常に同梱扱い (レガシー実測と同じ表示)。
            var scriptName = ""
            if os == 1 || os == 2 { scriptName = "acasbkup.bat" }
            else if os == 4 { scriptName = "acasbkup.cmd" }
            else if os == 6 || os == 5 || os == 3 { scriptName = "acasbkup.sh" }
            let backupFound = s.environment["ACAS_BACKUP_SCRIPT"] != "N"
            let batchText = backupFound ? s.l10n.raw("st.using") + scriptName : s.l10n.raw("st.no_backup_script")

            var first = menuReply == "A"
            menu: while true {
                if first {
                    first = false; menuReply = " "
                    if try load(s, "st000") { return }
                    continue
                }
                // aa030-display-menu
                c.display(" ", at: 101, eraseEOS: true)
                s.caller = "stock"; s.called = ""; s.delLink = ""; s.termCode = 0
                c.display(s.sys.str("maps-ser-xx"), at: 2474, color: 3)
                c.display(Cobol.z(s.sys.int("maps-ser-nn"), 4), at: 2476, color: 3)
                c.display(s.t("sys.copyright_prefix"), at: 2401, color: 3)
                c.display(Cobol.z(s.today.year, 4), at: 2420, color: 3)
                c.display(s.t("sys.copyright_owner"), at: 2424, color: 3)
                c.display(s.sys.str("usera"), at: 101, color: 3)
                if !(1...3).contains(Int(s.sys.int("date-form"))) { s.sys.setInt("date-form", 1) }
                c.display(Common.convDate(s, s.toDay), at: 171, color: 3)
                // aa040-Display-Go
                c.display(progName, at: 301, color: 2)
                c.display(s.t("st.menu_title"), at: 328, color: 2)
                Common.displayTime(s, labelAt: 355, timeAt: 358)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                c.display(s.t("st.item_a"), at: 1004, color: 2)
                c.display(s.t("st.item_b"), at: 1104, color: 2)
                c.display(s.t("st.item_c"), at: 1204, color: 2)
                c.display(s.t("st.item_d"), at: 1304, color: 2)
                c.display(s.t("st.item_e"), at: 1044, color: 2)
                c.display(s.t("st.item_x"), at: 1244, color: 2)
                c.display(Cobol.x(opDisplay, 7), at: 1257, color: 2)
                c.display(Cobol.x(batchText, 28), at: 1249, color: 2)
                c.display(s.t("st.item_y"), at: 1344, color: 2)
                c.display(s.t("st.item_z"), at: 1444, color: 2)

                // aa050-Accept-Loop
                while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
                        s.writeSystem(s.sys)   // aa070 (バックアップスクリプトの起動は端末内では行わない)
                        return
                    case "A": if try load(s, "st000") { return }
                    case "B": if try load(s, "st010") { return }
                    case "C": if try load(s, "st020") { return }
                    case "D": if try load(s, "st030") { return }
                    case "E": if try load(s, "st040") { return }
                    case "Y": if try load(s, "st050") { return }
                    case "Z":
                        try callSystemSetup(s)
                        break menu
                    default:
                        if let ch = reply.first, ch.isASCII, ch.isLetter { continue menu }
                        continue
                    }
                    continue menu
                }
            }
        }
    }

    /// load00: プログラムを呼び、ws-term-code > 7 なら書き戻して終了 (true)
    static func load(_ s: Session, _ name: String) throws -> Bool {
        s.called = name
        s.termCode = 0
        try s.call(name)
        if s.termCode > 7 {
            s.writeSystem(s.sys)
            return true
        }
        return false
    }

    /// aa060-Call-System-Setup
    static func callSystemSetup(_ s: Session) throws {
        s.termCode = 0
        s.writeSystem(s.sys)
        s.called = "sys002"
        if try !s.call("sys002") { throw StopRun(code: 1) }
        if s.termCode > 7 { throw StopRun() }
    }

    /// ba000-mapser: システムファイル新規作成
    static func mapser(_ s: Session) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("acas.setup_title"), at: 122, color: 2)
        var sys = Record(SystemLayout.layout)
        sys.setInt("system-record-version-prime", 1)
        sys.setInt("system-record-version-secondary", 1)
        sys.setInt("date-form", 1)
        var usera = sys.str("usera")
        while true {
            // ba010-Capture-Data
            c.display(s.t("st.enter_company"), at: 1101, color: 2)
            c.display("]", at: 1160, color: 2)
            usera = try c.accept(at: 1128, size: 32, initial: usera, options: [.update], color: 3)
            c.display(s.t("acas.verify_name"), at: 1301, color: 2)
            let r = try c.accept(at: 1346, size: 1, initial: "Y", options: [.update], color: 6)
            if r == "Y" || r == "y" { break }
        }
        sys["usera"] = usera
        sys["user-code"] = Maps01.encodeName(usera)
        sys["pass-word"] = Maps01.encodePassword("pass")
        sys["sl-own-nos"] = "N"
        let d = s.today
        s.toDay = "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/\(Cobol.z(d.year, 4))"
        sys.setInt("run-date", Int64(Maps04.integerOfDate(year: d.year, month: d.month, day: d.day)))
        try levelSetup(s, &sys)
        sys.setInt("op-system", 1); sys.setInt("sales-range", 1); sys.setInt("purchase-range", 2)
        sys.setInt("next-batch", 1); sys.setInt("sl-dunning", 1); sys.setInt("sl-charges", 1)
        sys.setInt("invoicer", 2); sys.setInt("sl-credit", 30); sys["sl-delim"] = "\\"
        let f = s.systemFile
        s.store.writeRaw(f.path, [])
        f.write(1, sys.bytes)
        f.write(2, SystemAuxRecords.initialDefault())
        f.write(3, [UInt8](repeating: 0x20, count: 1024))
        f.write(4, SystemAuxRecords.initialRecord4())
    }

    /// ca000-level-setup
    static func levelSetup(_ s: Session, _ sys: inout Record) throws {
        let c = s.console
        var reply = "Y"   // ws-reply は直前の確認入力の値を引き継ぐ
        func yn(_ at: Int) throws -> Bool {
            reply = try c.accept(at: at, size: 1, initial: reply, options: [.update], color: 6)
            return reply == "Y" || reply == "y"
        }
        while true {
            sys["maps-ser-xx"] = "mp"; sys.setInt("maps-ser-nn", 9999)
            c.display(s.t("acas.using_gl"), at: 1901, color: 2)
            c.display(s.t("acas.using_pl"), at: 2001, color: 2)
            c.display(s.t("acas.using_sl"), at: 2101, color: 2)
            c.display(s.t("acas.using_inv"), at: 1941, color: 2)
            c.display(s.t("acas.using_stock"), at: 2041, color: 2)
            c.display(s.t("acas.using_oe"), at: 2141, color: 2)
            sys.setInt("level-1", try yn(1935) ? 1 : 0)
            sys.setInt("level-2", try yn(2035) ? 1 : 0)
            sys.setInt("level-3", try yn(2135) ? 1 : 0)
            sys.setInt("full-invoicing", try yn(1975) ? 1 : 0)
            sys.setInt("level-4", try yn(2075) ? 1 : 0)
            sys.setInt("level-5", try yn(2175) ? 1 : 0)
            c.display(s.t("acas.please_confirm"), at: 2301, color: 2)
            let gl = sys.int("level-1") == 1, pl = sys.int("level-2") == 1, sl = sys.int("level-3") == 1
            var list = ""
            if gl { list += s.l10n.raw("acas.opt_general") }
            if pl && gl { list += "/ " }
            if pl { list += s.l10n.raw("acas.opt_purchase") }
            if (sl && gl) || (sl && pl) { list += "/ " }
            if sl { list += s.l10n.raw("acas.opt_sales") }
            if sl && sys.int("full-invoicing") == 1 { list += s.l10n.raw("acas.opt_invoicing") + " " }
            if sys.int("level-4") == 1 { list += s.l10n.raw("acas.opt_stock") }
            if sys.int("level-5") == 1 { list += s.l10n.raw("acas.opt_oe") }
            c.display(Cobol.x(list, 60), at: 2401, color: 2)
            reply = try c.accept(at: 2326, size: 1, color: 6)
            if reply == "Y" || reply == "y" { break }
        }
    }
}
// 
