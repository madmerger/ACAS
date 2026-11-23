import Foundation

/// 検証用の最小実装: purchase.cbl (買掛元帳メニュー) と pl000 (Start Of Day)。
/// PLA 版が未登録の場合のみ登録する (親がマージ時に PLA 版へ差し替える)。
enum PLBDevMenu {
    static let progName = "Purchase (3.01.19)"

    static func registerIfMissing(_ s: Session) {
        if s.programs["purchase"] == nil { s.programs["purchase"] = run }
        if s.programs["pl000"] == nil { s.programs["pl000"] = pl000 }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        var menuReply = "A"
        while true {
            if s.readSystem() == nil { try ACASMenu.setupLevel1(s) }
            _ = Common.loadSystemRecords(s)
            if s.sys.int("scycle") == 0 {
                try callSystemSetup(s)
                continue
            }
            s.toDay = Maps04.toDate(Int(s.sys.int("run-date")))
            if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
            if s.sys.int("level-2") != 1 {
                try PLB.maps99(s, 1)
                try PLB.maps99(s, 15)
                return
            }
            let opDisplay: String
            switch s.sys.int("op-system") {
            case 6: opDisplay = "Linux"
            case 2: opDisplay = "Windows"
            case 3: opDisplay = "Mac"
            case 4: opDisplay = "OS/2"
            case 5: opDisplay = "Unix"
            case 1: opDisplay = "Dos"
            default: opDisplay = "O/S"
            }
            s.processFunc = 0; s.subFunction = 0
            var first = menuReply == "A"
            menu: while true {
                if first {
                    first = false; menuReply = " "
                    if try load(s, "pl000") { return }
                    continue
                }
                s.caller = "purchase"; s.called = ""; s.delLink = ""; s.termCode = 0
                Common.menuFrame(s, progName: progName, titleKey: "plbdev.menu_title", titleAt: 326)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                let items: [(String, Int)] = [("a", 1004), ("b", 1104), ("c", 1204), ("d", 1304), ("e", 1404), ("f", 1504),
                    ("g", 1604), ("h", 1704), ("i", 1804), ("j", 1904), ("k", 2004), ("l", 2104), ("m", 2204),
                    ("n", 1044), ("o", 1144), ("p", 1244), ("q", 1344), ("r", 1444), ("s", 1544), ("t", 1644),
                    ("u", 1744), ("v", 1844), ("x", 1944)]
                for (k, at) in items { c.display(s.t("plbdev.item_" + k), at: at, color: 2) }
                c.display(Cobol.x(opDisplay, 6), at: 1957, color: 2)
                c.display(s.t("plbdev.using") + "acasbkup.sh", at: 2049, color: 2)
                c.display(s.t("plbdev.item_z"), at: 2244, color: 2)
                accept: while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
                        Common.rewriteSystemRecords(s)
                        return
                    case "A": if try load(s, "pl000") { return }
                    case "B": if try load(s, "pl010") { return }
                    case "C": if try load(s, "pl015") { return }
                    case "D": if try load(s, "pl020") { return }
                    case "E": if try load(s, "pl030") { return }
                    case "F": if try load(s, "pl040") { return }
                    case "G", "H":
                        if s.sys.int("p-flag-i") != 1 || fileStatus(s, 26) == 0 {
                            try messageRun(s, 14)
                            continue menu
                        }
                        if reply == "G" {
                            if try load(s, "pl050") { return }
                        } else {
                            if try load(s, "pl055") { return }
                            if try load(s, "pl060") { return }
                        }
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
                        // load16: error-code (メニュー側の作業域) は常に 0 のため pl120 まで進む
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
                        // load20: ws-term-code は直前に 0 へ初期化済みなので常に pl140 から
                        if try load(s, "pl140") { return }
                        while true {
                            if try load(s, "xl150") { return }
                            if s.termCode == 2 || s.termCode == 3 { break }
                            if s.termCode == 1 {
                                if try load(s, "pl130") { return }
                                s.termCode = 0
                                continue
                            }
                            break
                        }
                    case "U": if try load(s, "pl180") { return }
                    case "V": if try load(s, "pl190") { return }
                    case "W": break
                    case "Y":
                        c.display(s.t("plbdev.sorry"), at: 2331, color: 2)
                        continue accept
                    case "Z":
                        s.termCode = 0
                        Common.rewriteSystemRecords(s)
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

    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        Int(Cobol.numval(String(Array(s.sys.str("file-statuses"))[n - 1])).0)
    }

    /// message-run: display-menu 段落 (枠のみ) を表示して maps99
    static func messageRun(_ s: Session, _ code: Int) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        s.caller = "purchase"; s.called = ""; s.delLink = ""; s.termCode = 0
        c.display(s.sys.str("maps-ser-xx"), at: 2474, color: 3)
        c.display(Cobol.z(s.sys.int("maps-ser-nn"), 4), at: 2476, color: 3)
        c.display(s.t("sys.copyright_prefix"), at: 2401, color: 3)
        c.display(Cobol.z(s.today.year, 4), at: 2420, color: 3)
        c.display(s.t("sys.copyright_owner"), at: 2424, color: 3)
        c.display(s.sys.str("usera"), at: 101, color: 3)
        try PLB.maps99(s, code)
        try PLB.maps99(s, 15)
    }

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
        s.called = "sys002"
        if try !s.call("sys002") { throw StopRun(code: 1) }
        if s.termCode > 7 { throw StopRun() }
    }

    /// pl000.cbl: Start Of Day
    static func pl000(_ s: Session) throws {
        let c = s.console
        let d = s.today
        var uDate = "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/20\(Cobol.z(d.year % 100, 2))"
        s.toDay = uDate
        c.display(s.t("plbdev.client"), at: 101, color: 2, eraseEOS: true)
        c.display(s.sys.str("usera"), at: 110, color: 3)
        c.display("PL000 (3.01.01)", at: 301, color: 2)
        c.display(s.t("plbdev.pl000_title"), at: 328, color: 2)
        Common.displaySerial(s)
        Common.displayTime(s, labelAt: 360, timeAt: 363)
        var bin = 0
        while true {
            let form = Int(s.sys.int("date-form"))
            if !(1...3).contains(form) { s.sys.setInt("date-form", 1) }
            uDate = Common.convDate(s, uDate)
            c.display(s.t(["plbdev.enter_date_uk", "plbdev.enter_date_usa", "plbdev.enter_date_intl"][Int(s.sys.int("date-form")) - 1]), at: 812, color: 2)
            c.display(uDate, at: 847, color: 3)
            uDate = try c.accept(at: 847, size: 10, initial: uDate, options: [.update], color: 3)
            uDate = Common.toUK(s, uDate)
            bin = Maps04.toBinary(uDate)
            if bin == 0 {
                c.display(s.t("plbdev.pl005"), at: 860, color: 4)
            } else {
                c.display(" ", at: 860, eraseEOL: true)
                break
            }
        }
        s.sys.setInt("run-date", Int64(bin))
        s.toDay = uDate
        s.termCode = 0
    }
}
