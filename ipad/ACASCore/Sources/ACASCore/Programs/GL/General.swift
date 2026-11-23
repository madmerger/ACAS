import Foundation

/// general/general.cbl: 総勘定元帳メニュー
enum General {
    static let progName = "General (3.00.11)"

    static func run(_ s: Session) throws {
        let c = s.console
        var menuReply = "A"   // 起動直後は日付入力 (gl000) を強制
        while true {
            // Open-System / get-system-recs
            if s.readSystem() == nil { try ACASMenu.setupLevel1(s) }
            if let bad = Common.loadSystemRecords(s) {
                let key = [4: "gl.gl003", 2: "gl.gl002", 1: "gl.gl001"][bad]!
                c.display(s.t(key) + "23" + s.t("gl.hit_return"), at: 101)
                _ = try c.accept(at: 201, size: 1)
                throw StopRun()
            }
            if s.sys.int("scycle") == 0 {
                try callSystemSetup(s)
                continue
            }
            s.toDay = Maps04.toDate(Int(s.sys.int("run-date")))
            if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
            if s.sys.int("level-1") != 1 {
                s.shared["error-code"] = 1
                try s.call("maps99")
                s.shared["error-code"] = 15
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

            var first = menuReply == "A"
            menu: while true {
                if first {
                    first = false; menuReply = " "
                    if try load(s, "gl000") { return }
                    continue
                }
                // display-menu
                s.caller = "General"; s.called = ""; s.delLink = ""; s.termCode = 0
                Common.menuFrame(s, progName: progName, titleKey: "gl.menu_title", titleAt: 328)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                c.display(s.t("gl.item_a"), at: 1004, color: 2)
                c.display(s.t("gl.item_b"), at: 1104, color: 2)
                c.display(s.t("gl.item_c"), at: 1204, color: 2)
                c.display(s.t("gl.item_d"), at: 1304, color: 2)
                c.display(s.t("gl.item_e"), at: 1404, color: 2)
                c.display(s.t("gl.item_f"), at: 1504, color: 2)
                c.display(s.t("gl.item_g"), at: 1604, color: 2)
                c.display(s.t("gl.item_h"), at: 1704, color: 2)
                c.display(s.t("gl.item_i"), at: 1804, color: 2)
                c.display(s.t("gl.item_j"), at: 1144, color: 2)
                c.display(s.t("gl.item_k"), at: 1244, color: 2)
                c.display(s.t("gl.item_l"), at: 1344, color: 2)
                c.display(s.t("gl.item_m"), at: 1444, color: 2)
                c.display(s.t("gl.item_x"), at: 1544, color: 2)
                c.display(Cobol.x(opDisplay, 7), at: 1557, color: 2)
                c.display(s.t("gl.item_z"), at: 1744, color: 2)

                // accept-loop
                accept: while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
                        Common.rewriteSystemRecords(s)
                        return
                    case "A": if try load(s, "gl000") { return }
                    case "B": if try load(s, "gl030") { return }
                    case "C", "E", "F":
                        if try load(s, ["C": "gl020", "E": "gl050", "F": "gl051"][reply]!) { return }
                        Common.rewriteSystemRecords(s)
                        _ = Common.loadSystemRecords(s)
                    case "G": if try load(s, "gl060") { return }
                    case "H":
                        if try load(s, "gl070") { return }
                        if s.termCode == 5 { continue menu }
                        if try load(s, "gl071") { return }
                        if try load(s, "gl072") { return }
                    case "I": if try load(s, "gl080") { return }
                    case "J": if try load(s, "gl090") { return }
                    case "K": if try load(s, "gl120") { return }
                    case "L":
                        if try load(s, "gl100") { return }
                        if s.termCode == 5 { continue accept }
                        if s.termCode == 4 {
                            s.shared["error-code"] = 31
                            try s.call("maps99")
                            s.shared["error-code"] = 15
                            try s.call("maps99")
                            continue menu
                        }
                        if try load(s, "gl105") { return }
                    case "D", "Y":
                        c.display(s.t("gl.not_yet_available"), at: 2327, color: 2)
                        continue accept
                    case "Z":
                        Common.rewriteSystemRecords(s)
                        try callSystemSetup(s)
                        break menu
                    default:
                        if let ch = reply.first, ch.isASCII, ch.isLetter { continue menu }
                        continue accept
                    }
                    continue menu
                }
            }
        }
    }

    /// load00: プログラムを呼び、ws-term-code > 7 なら書き戻して終了 (true)
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
}
