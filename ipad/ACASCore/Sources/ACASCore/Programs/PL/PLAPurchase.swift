import Foundation

/// 買掛元帳 前半 (purchase.cbl, pl000〜pl095) の名前空間
enum PLA {
    /// common/maps99.cbl 呼び出し。エラーコードは shared["error-code"] で渡す。
    /// maps99 が未登録の間はレガシーの maps99 と同じ処理をここで行う。
    static func maps99(_ s: Session, _ code: Int) throws {
        s.shared["error-code"] = code
        if try s.call("maps99") { return }
        let c = s.console
        var lin = 23
        s.termCode = 0
        var serv = "T", mess = s.t("pl.maps99_not_found"), wait = true
        if let raw = s.store.readRaw("error.txt") {
            for l in String(decoding: raw, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
                let a = Array(Cobol.x(String(l), 57))
                guard Int(String(a[0..<3])) == code else { continue }
                serv = String(a[3]); let response = String(a[4])
                let errorLine = Int(String(a[5..<7])) ?? 0
                mess = String(a[7..<57])
                if errorLine != 0 { lin = errorLine > 19 ? 24 - (24 - errorLine) : errorLine }
                wait = response == "T" || (serv == "S" && response == "S")
                if !wait && serv == "T" { s.termCode = 9 }
                break
            }
        }
        c.display(serv + "-" + Cobol.z(Int64(code), 3) + " " + Cobol.x(mess, 50), at: lin * 100 + 1, color: 4)
        if wait { _ = try c.accept(at: 2479, size: 1) }
    }
}

/// purchase/purchase.cbl: 買掛元帳メニュー
enum PLAPurchase {
    static let progName = "Purchase (3.01.19)"

    static func run(_ s: Session) throws {
        let c = s.console
        var menuReply = "A"   // 起動直後は日付入力 (pl000) を強制
        while true {
            // Open-System
            if s.readSystem() == nil { try ACASMenu.setupLevel1(s) }
            _ = Common.loadSystemRecords(s)
            if s.sys.int("scycle") == 0 {
                try callSystemSetup(s)
                continue
            }
            s.toDay = Maps04.toDate(Int(s.sys.int("run-date")))
            if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
            if s.sys.int("level-2") != 1 {
                try PLA.maps99(s, 1)
                try PLA.maps99(s, 15)
                return
            }
            var opDisplay = ""
            let os = s.sys.int("op-system")
            if os == 0 { opDisplay = "O/S" }
            switch os {
            case 6: opDisplay = "Linux"
            case 2: opDisplay = "Windows"
            case 3: opDisplay = "Mac"
            case 4: opDisplay = "OS/2"
            case 5: opDisplay = "Unix"
            case 1: opDisplay = "Dos"
            default: break
            }
            var scriptName = ""
            switch os {
            case 1, 2: scriptName = "acasbkup.bat"
            case 4: scriptName = "acasbkup.cmd"
            case 6, 5, 3: scriptName = "acasbkup.sh"
            default: break
            }
            // CBL_CHECK_FILE_EXIST: iPad 版はバックアップ機能をアプリに内蔵する (bin のスクリプトは常に在るものとして扱う)。
            // s.shared["backup-script"] = false で「無し」を再現できる。
            let backupFound = (s.shared["backup-script"] as? Bool) ?? true
            let batchText = backupFound ? s.l10n.raw("purchase.using") + scriptName : s.t("purchase.no_backup")
            s.processFunc = 0; s.subFunction = 0

            var first = menuReply == "A"
            menu: while true {
                if first {
                    first = false; menuReply = " "
                    if try load(s, "pl000") { return }
                    continue
                }
                displayMenu(s)
                c.display(Common.convDate(s, s.toDay), at: 171, color: 3)
                c.display(progName, at: 301, color: 2)
                c.display(s.t("purchase.menu_title"), at: 326, color: 2)
                Common.displayTime(s, labelAt: 355, timeAt: 358)
                Common.displayShortDate(s, labelAt: 367, dateAt: 370)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                let left = "abcdefghijklm", right = "nopqrstuv"
                for (i, ch) in left.enumerated() { c.display(s.t("purchase.item_\(ch)"), at: (10 + i) * 100 + 4, color: 2) }
                for (i, ch) in right.enumerated() { c.display(s.t("purchase.item_\(ch)"), at: (10 + i) * 100 + 44, color: 2) }
                c.display(s.t("purchase.item_x"), at: 1944, color: 2)
                c.display(Cobol.x(opDisplay, 6), at: 1957, color: 2)
                c.display(Cobol.x(batchText, 28), at: 2049, color: 2)
                c.display(s.t("purchase.item_z"), at: 2244, color: 2)

                accept: while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
                        Common.rewriteSystemRecords(s)
                        if backupFound { try s.call("acasbkup") }
                        return
                    case "A": if try load(s, "pl000") { return }
                    case "B": if try load(s, "pl010") { return }
                    case "C": if try load(s, "pl015") { return }
                    case "D": if try load(s, "pl020") { return }
                    case "E": if try load(s, "pl030") { return }
                    case "F": if try load(s, "pl040") { return }
                    case "G":
                        if s.sys.int("p-flag-i") != 1 || fileStatus(s, 26) == 0 { try messageRun(s, 14); continue menu }
                        if try load(s, "pl050") { return }
                    case "H":
                        if s.sys.int("p-flag-i") != 1 || fileStatus(s, 26) == 0 { try messageRun(s, 14); continue menu }
                        if try load(s, "pl055") { return }
                        if try load(s, "pl060") { return }
                    case "I":
                        if s.sys.int("p-flag-i") == 1 { try messageRun(s, 28); continue menu }
                        if fileStatus(s, 29) == 0 { try messageRun(s, 25); continue menu }
                        if try load(s, "pl080") { return }
                    case "J": if try load(s, "pl085") { return }
                    case "K":
                        if try load(s, "pl090") { return }
                        if try load(s, "pl095") { return }
                    case "L": if try load(s, "pl100") { return }
                    case "M": if try load(s, "pl070") { return }
                    case "N": if try load(s, "pl130") { return }
                    case "O": if try load(s, "pl140") { return }
                    case "P":
                        if try load(s, "pl165") { return }
                        s.sys.set("oi-5-flag", "Y")
                        if try load(s, "pl115") { return }
                        if try load(s, "pl120") { return }
                    case "Q":
                        if try load(s, "pl165") { return }
                        if try load(s, "pl160") { return }
                    case "R": if try load(s, "pl170") { return }
                    case "S": if try load(s, "pl900") { return }
                    case "T":
                        if try load(s, "pl140") { return }
                        while true {
                            if try load(s, "xl150") { return }
                            if s.termCode != 1 { break }
                            if try load(s, "pl130") { return }
                            s.termCode = 0
                        }
                    case "U": if try load(s, "pl180") { return }
                    case "V": if try load(s, "pl190") { return }
                    case "Y":
                        c.display(s.t("purchase.not_yet_available"), at: 2331, color: 2)
                        continue accept
                    case "Z":
                        try callSystemSetup(s)
                        break menu
                    case "W": break
                    default: continue accept
                    }
                    continue menu
                }
            }
        }
    }

    /// display-menu 段落 (Conv-date の手前まで)
    static func displayMenu(_ s: Session) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        s.caller = "purchase"; s.called = ""; s.delLink = ""; s.termCode = 0
        c.display(s.sys.str("maps-ser-xx"), at: 2474, color: 3)
        c.display(Cobol.z(s.sys.int("maps-ser-nn"), 4), at: 2476, color: 3)
        c.display(s.t("sys.copyright_prefix"), at: 2401, color: 3)
        c.display(Cobol.z(s.today.year, 4), at: 2420, color: 3)
        c.display(s.t("sys.copyright_owner"), at: 2424, color: 3)
        c.display(s.sys.str("usera"), at: 101, color: 3)
    }

    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        let a = Array(s.sys.str("file-statuses").utf8)
        return n <= a.count ? Int(a[n - 1]) - 48 : 0
    }

    static func messageRun(_ s: Session, _ code: Int) throws {
        displayMenu(s)
        try PLA.maps99(s, code)
        try PLA.maps99(s, 15)
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
}
