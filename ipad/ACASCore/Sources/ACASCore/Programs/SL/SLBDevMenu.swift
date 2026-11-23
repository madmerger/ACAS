import Foundation

/// 検証用の最小実装: sales.cbl (売掛元帳メニュー) と sl000 (Start Of Day)。
/// SLA 版が未登録の場合のみ登録する (親がマージ時に SLA 版へ差し替える)。
enum SLBDevMenu {
    static let progName = "Sales (3.01.18)"

    static func registerIfMissing(_ s: Session) {
        if s.programs["sales"] == nil { s.programs["sales"] = run }
        if s.programs["sl000"] == nil { s.programs["sl000"] = sl000 }
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
            if s.sys.int("level-3") != 1 {
                try s.call("maps99")
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
                    if try load(s, "sl000") { return }
                    continue
                }
                s.caller = "sales"; s.called = ""; s.delLink = ""; s.termCode = 0
                Common.menuFrame(s, progName: progName, titleKey: "slbdev.menu_title", titleAt: 329)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                let items: [(String, Int)] = [("a", 1004), ("b", 1104), ("c", 1204), ("d", 1304), ("e", 1404), ("f", 1504),
                    ("g", 1604), ("h", 1704), ("i", 1804), ("j", 1904), ("k", 2004), ("l", 2104), ("m", 2204),
                    ("n", 1044), ("o", 1144), ("p", 1244), ("q", 1344), ("r", 1444), ("s", 1544), ("t", 1644),
                    ("u", 1744), ("v", 1844), ("x", 2044)]
                for (k, at) in items { c.display(s.t("slbdev.item_" + k), at: at, color: 2) }
                c.display(Cobol.x(opDisplay, 7), at: 2057, color: 2)
                c.display(s.t("slbdev.using") + "acasbkup.sh", at: 2149, color: 2)
                c.display(s.t("slbdev.item_z"), at: 2344, color: 2)
                accept: while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
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
                    case "O":
                        if try load(s, "sl115") { return }
                        if try load(s, "sl110") { return }
                    case "P":
                        if try load(s, "sl115") { return }
                        if try load(s, "sl190") { return }
                    case "Q":
                        if try load(s, "sl115") { return }
                        if try load(s, "sl120") { return }
                    case "R":
                        if try load(s, "sl165") { return }
                        if try load(s, "sl160") { return }
                    case "S": if try load(s, "sl180") { return }
                    case "T": if try load(s, "sl900") { return }
                    case "U":
                        // load21: ws-term-code は直前に 0 へ初期化済みなので常に sl140 から
                        if try load(s, "sl140") { return }
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
                    case "W", "Y":
                        if reply == "Y" {
                            c.display(s.t("slbdev.sorry"), at: 2331, color: 2)
                            continue accept
                        }
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

    /// sl000.cbl: Start Of Day
    static func sl000(_ s: Session) throws {
        let c = s.console
        let d = s.today
        var uDate = "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/20\(Cobol.z(d.year % 100, 2))"
        s.toDay = uDate
        c.display(s.t("slbdev.client"), at: 101, color: 2, eraseEOS: true)
        c.display(s.sys.str("usera"), at: 110, color: 3)
        c.display("SL000 (3.01.02)", at: 301, color: 2)
        c.display(s.t("slbdev.sl000_title"), at: 328, color: 2)
        Common.displaySerial(s)
        Common.displayTime(s, labelAt: 360, timeAt: 363)
        var bin = 0
        while true {
            let form = Int(s.sys.int("date-form"))
            if !(1...3).contains(form) { s.sys.setInt("date-form", 1) }
            uDate = Common.convDate(s, uDate)
            c.display(s.t(["slbdev.enter_date_uk", "slbdev.enter_date_usa", "slbdev.enter_date_intl"][Int(s.sys.int("date-form")) - 1]), at: 812, color: 2)
            c.display(uDate, at: 847, color: 3)
            uDate = try c.accept(at: 847, size: 10, initial: uDate, options: [.update], color: 3)
            uDate = Common.toUK(s, uDate)
            bin = Maps04.toBinary(uDate)
            if bin == 0 {
                c.display(s.t("slbdev.sl005"), at: 860, color: 4)
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
