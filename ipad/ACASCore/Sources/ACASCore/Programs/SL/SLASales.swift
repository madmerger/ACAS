import Foundation

/// sales/sales.cbl: 売掛元帳メニュー
enum SLASales {
    static let progName = "Sales (3.01.18)"

    static func run(_ s: Session) throws {
        let c = s.console
        var menuReply = "A"   // 起動直後は日付入力 (sl000) を強制
        while true {
            // Open-System
            if s.readSystem() == nil { try mapser(s) }
            _ = Common.loadSystemRecords(s)
            if s.sys.int("scycle") == 0 {
                try callSystemSetup(s)
                continue
            }
            s.toDay = Maps04.toDate(Int(s.sys.int("run-date")))
            if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
            if s.sys.int("level-3") != 1 {
                try s.call("maps99")
                try s.call("maps99")
                return
            }
            var opDisplay = ""
            switch s.sys.int("op-system") {
            case 0: opDisplay = "O/S"
            case 6: opDisplay = "Linux"
            case 2: opDisplay = "Windows"
            case 3: opDisplay = "Mac"
            case 4: opDisplay = "OS/2"
            case 5: opDisplay = "Unix"
            case 1: opDisplay = "Dos"
            default: break
            }
            var scriptName = ""
            switch s.sys.int("op-system") {
            case 1, 2: scriptName = "acasbkup.bat"
            case 4: scriptName = "acasbkup.cmd"
            case 3, 5, 6: scriptName = "acasbkup.sh"
            default: break
            }
            // CBL_CHECK_FILE_EXIST (ACAS_BIN/スクリプト): iPad 版は ACAS_BIN が設定されていれば存在とみなす
            let backupFound = !(s.environment["ACAS_BIN"] ?? "").isEmpty
            let batchText = backupFound ? s.l10n.raw("sl.using") + scriptName : s.l10n.raw("sl.no_backup_script")
            s.processFunc = 0; s.subFunction = 0

            var first = menuReply == "A"
            menu: while true {
                if first {
                    first = false; menuReply = " "
                    if try load(s, "sl000") { return }
                    continue
                }
                // display-menu
                s.caller = "sales"; s.called = ""; s.delLink = ""; s.termCode = 0
                Common.menuFrame(s, progName: progName, titleKey: "sl.menu_title", titleAt: 329)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                let left = "abcdefghijklm", right = "nopqrstuv"
                for (i, ch) in left.enumerated() { c.display(s.t("sl.item_\(ch)"), at: (10 + i) * 100 + 4, color: 2) }
                for (i, ch) in right.enumerated() { c.display(s.t("sl.item_\(ch)"), at: (10 + i) * 100 + 44, color: 2) }
                c.display(s.t("sl.item_x"), at: 2044, color: 2)
                c.display(Cobol.x(opDisplay, 6), at: 2057, color: 2)
                c.display(Cobol.x(batchText, 28), at: 2149, color: 2)
                c.display(s.t("sl.item_z"), at: 2344, color: 2)

                // accept-loop
                accept: while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
                        // pre-overrewrite: バックアップスクリプトの起動 (CALL "SYSTEM") は iPad 版では行わない
                        Common.rewriteSystemRecords(s)
                        return
                    case "A": if try load(s, "sl000") { return }
                    case "B": if try load(s, "sl010") { return }
                    case "C": if try load(s, "sl020") { return }
                    case "D":
                        s.sys.setInt("pass-value", 2)
                        if try load(s, "sl910") { return }
                    case "E":
                        s.sys.setInt("pass-value", 4)
                        if try load(s, "sl920") { return }
                    case "F": if try load(s, "sl050") { return }
                    case "G":
                        if try load(s, "sl055") { return }
                        if s.termCode != 0 { continue menu }
                        if try load(s, "sl060") { return }
                    case "H": if try load(s, "sl080") { return }
                    case "I": if try load(s, "sl085") { return }
                    case "J":
                        if try load(s, "sl090") { return }
                        if try load(s, "sl095") { return }
                    case "K": if try load(s, "sl100") { return }
                    case "L": if try load(s, "sl070") { return }
                    case "M": if try load(s, "sl130") { return }
                    case "N": if try load(s, "sl140") { return }
                    case "O", "P", "Q":
                        if try load(s, "sl115") { return }
                        if try load(s, ["O": "sl110", "P": "sl190", "Q": "sl120"][reply]!) { return }
                    case "R":
                        if try load(s, "sl165") { return }
                        if try load(s, "sl160") { return }
                    case "S": if try load(s, "sl180") { return }
                    case "T": if try load(s, "sl900") { return }
                    case "U":
                        // load21: ws-term-code は display-menu で 0 になっているため常に sl140 から
                        if s.termCode != 3 {
                            if try load(s, "sl140") { return }
                        }
                        while true {
                            if try load(s, "xl150") { return }
                            if s.termCode == 2 || s.termCode == 3 { break }
                            if s.termCode == 1 {
                                if try load(s, "sl130") { return }
                                s.termCode = 0
                                continue
                            }
                            break
                        }
                    case "V": if try load(s, "sl170") { return }
                    case "W", "Y": break
                    case "Z":
                        s.termCode = 0
                        s.systemFile.write(1, s.sys.bytes)
                        try callSystemSetup(s)
                        break menu
                    default:
                        continue accept
                    }
                    continue menu
                }
            }
        }
    }

    /// load00 / load000: プログラムを呼び、ws-term-code > 7 なら書き戻して終了 (true)
    static func load(_ s: Session, _ name: String) throws -> Bool {
        s.termCode = 0
        s.called = name
        try s.call(name)
        if s.termCode > 7 {
            Common.rewriteSystemRecords(s)
            return true
        }
        return false
    }

    static func callSystemSetup(_ s: Session) throws {
        s.termCode = 0
        s.systemFile.write(1, s.sys.bytes)
        s.called = "sys002"
        if try !s.call("sys002") { throw StopRun(code: 1) }
        if s.termCode > 7 { throw StopRun() }
    }

    /// mapser: システムファイル新規作成
    static func mapser(_ s: Session) throws {
        let c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("acas.setup_title"), at: 122, color: 2)
        var sys = Record(SystemLayout.layout)
        sys.setInt("system-record-version-prime", 1)
        sys.setInt("system-record-version-secondary", 1)
        sys.setInt("date-form", 1)
        var usera = sys.str("usera")
        while true {
            c.display(s.t("acas.enter_company"), at: 1101, color: 2)
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
        try ACASMenu.levelSetup(s, &sys)
        sys.setInt("op-system", 1); sys.setInt("sales-range", 1); sys.setInt("purchase-range", 2)
        sys.setInt("next-batch", 1); sys.setInt("sl-dunning", 1); sys.setInt("sl-charges", 1)
        sys.setInt("sl-credit", 30); sys.setInt("invoicer", 2); sys["sl-delim"] = "\\"
        let f = s.systemFile
        f.write(1, sys.bytes)
        f.write(2, SystemAuxRecords.initialDefault())
        f.write(3, [UInt8](repeating: 0x20, count: 1024))
        f.write(4, SystemAuxRecords.initialRecord4())
    }
}
