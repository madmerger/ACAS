import Foundation

/// ACAS.cbl: システムメニュー。メニュー階層・選択キー・表示位置はレガシーと同一。
public enum ACASMenu {
    static let progName = "ACAS (3.00.05)"

    public static func run(_ s: Session) throws {
        let c = s.console
        // zz010-Get-Env-Set-Files
        for name in ["ACAS_IRS", "ACAS_LEDGERS", "ACAS_BIN"] where (s.environment[name] ?? "").isEmpty {
            c.display(s.t("sys.sy009"), at: 505, highlight: true, eraseEOS: true)
            c.display(s.t("sys.sy008"), at: 1210, color: 3, highlight: true)
            _ = try c.accept(at: 1243, size: 1)
            throw StopRun()
        }
        // zz020-Get-Program-Args
        if s.arguments.count > 2 {
            c.display(s.t("sys.sy006"), at: 101, color: 3, eraseEOS: true)
            c.display(Cobol.z(s.arguments.count, 2), at: 164, color: 3)
            c.display(s.t("sys.sy008"), at: 1210, color: 3, highlight: true)
            _ = try c.accept(at: 1243, size: 1)
            throw StopRun()
        }
        for a in s.arguments {
            if a.hasPrefix("ACAS_LEDGERS=") { s.ledgers = String(a.dropFirst(13)).trimmingCharacters(in: ["/"]) + "/" }
            else if a.hasPrefix("ACAS_IRS=") { s.irsDir = String(a.dropFirst(9)).trimmingCharacters(in: ["/"]) + "/" }
            else {
                c.display(s.t("sys.sy007"), at: 101, color: 3, eraseEOS: true)
                c.display(s.t("sys.sy008"), at: 1210, color: 3, highlight: true)
                _ = try c.accept(at: 1243, size: 1)
                throw StopRun()
            }
        }

        while true {
            // Open-System
            if s.readSystem() == nil { try setupLevel1(s) }
            guard var sys = s.readSystem() else { throw StopRun(code: 1) }
            if sys.int("scycle") == 0 {
                try callSystemSetup(s)
                continue
            }
            let toDay = Maps04.toDate(Int(sys.int("run-date")))
            if sys.int("date-form") == 0 { sys.setInt("date-form", 1) }
            let dateForm = Int(sys.int("date-form"))

            menu: while true {
                // display-menu
                c.display(" ", at: 101, eraseEOS: true)
                c.display(sys.str("maps-ser-xx"), at: 2474, color: 3)
                c.display(Cobol.z(sys.int("maps-ser-nn"), 4), at: 2476, color: 3)
                c.display(s.t("sys.copyright_prefix"), at: 2401, color: 3)
                c.display(Cobol.z(s.today.year, 4), at: 2420, color: 3)
                c.display(s.t("sys.copyright_owner"), at: 2424, color: 3)
                c.display(sys.str("usera"), at: 101, color: 3)
                c.display(Maps04.format(toDay, dateForm: dateForm), at: 171, color: 3)
                c.display(progName, at: 301, color: 2)
                c.display(s.t("acas.menu_title"), at: 333, color: 2)
                c.display(s.t("sys.at"), at: 355, color: 2)
                c.display(s.timeHHMMSS, at: 358, color: 2)
                c.display(s.t("sys.on"), at: 367, color: 2)
                let d = s.today
                let short = "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/\(Cobol.z(d.year % 100, 2))"
                c.display(Maps04.formatShort(short, dateForm: dateForm), at: 370, color: 2)
                c.display(s.t("acas.select_prompt"), at: 601, color: 2)
                c.display(s.t("acas.item_a"), at: 1004, color: 2)
                c.display(s.t("acas.item_b"), at: 1104, color: 2)
                c.display(s.t("acas.item_c"), at: 1204, color: 2)
                c.display(s.t("acas.item_d"), at: 1304, color: 2)
                c.display(s.t("acas.item_e"), at: 1404, color: 2)
                c.display(s.t("acas.item_f"), at: 1504, color: 2)
                c.display(s.t("acas.item_g"), at: 1604, color: 2)
                c.display(s.t("acas.item_x"), at: 1444, color: 2)
                c.display(s.t("acas.item_z"), at: 1644, color: 2)

                // accept-loop
                while true {
                    let reply = try c.accept(at: 644, size: 1, options: [.auto], color: 6).uppercased()
                    var called: String?
                    switch reply {
                    case "X":
                        c.display(" ", at: 101, eraseEOS: true)
                        throw StopRun()
                    case "A": called = "general"
                    case "B": called = "sales"
                    case "C": called = "purchase"
                    case "D": called = "stock"
                    case "E", "F", "G":
                        c.display(s.t("acas.not_available"), at: 2331, color: 2)
                        continue
                    case "H":
                        c.display(s.t("acas.not_yet_available"), at: 2331, color: 2)
                        continue
                    case "Z":
                        try callSystemSetup(s)
                        break menu
                    default:
                        if let ch = reply.first, ch.isASCII, ch.isLetter { continue menu }
                        continue
                    }
                    if let name = called {
                        s.termCode = 0
                        s.caller = "ACAS"
                        s.called = name
                        try s.call(name)
                        if s.termCode > 7 { throw StopRun() }
                        break menu
                    }
                }
            }
        }
    }

    static func callSystemSetup(_ s: Session) throws {
        s.termCode = 0
        s.called = "sys002"
        if try !s.call("sys002") { throw StopRun(code: 1) }
        if s.termCode > 7 { throw StopRun() }
    }

    /// mapser: システムファイル新規作成 (会社名と利用サブシステムの入力)
    static func setupLevel1(_ s: Session) throws {
        let c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("acas.setup_title"), at: 122, color: 2)
        var sys = Record(SystemLayout.layout)
        sys.setInt("system-record-version-prime", 1)
        sys.setInt("system-record-version-secondary", 3)
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
        sys.setInt("run-date", Int64(Maps04.integerOfDate(year: d.year, month: d.month, day: d.day)))
        try levelSetup(s, &sys)
        sys.setInt("op-system", 1); sys.setInt("sales-range", 1); sys.setInt("purchase-range", 2)
        sys.setInt("next-batch", 1); sys.setInt("sl-dunning", 1); sys.setInt("sl-charges", 1)
        sys.setInt("sl-credit", 30); sys.setInt("invoicer", 2); sys["sl-delim"] = "\\"
        let f = s.systemFile
        f.write(1, sys.bytes)
        f.write(2, SystemAuxRecords.initialDefault())
        f.write(3, [UInt8](repeating: 0x20, count: 1024))
        f.write(4, SystemAuxRecords.initialRecord4())
    }

    static func levelSetup(_ s: Session, _ sys: inout Record) throws {
        let c = s.console
        sys["maps-ser-xx"] = "mp"; sys.setInt("maps-ser-nn", 9999)
        func yn(_ at: Int) throws -> Bool {
            let r = try c.accept(at: at, size: 1, initial: " ", options: [.update], color: 6)
            return r == "Y" || r == "y"
        }
        while true {
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
            if sl && sys.int("full-invoicing") == 1 { list += s.l10n.raw("acas.opt_invoicing") }
            if sys.int("level-4") == 1 { list += s.l10n.raw("acas.opt_stock") }
            if sys.int("level-5") == 1 { list += s.l10n.raw("acas.opt_oe") }
            c.display(Cobol.x(list, 64), at: 2401, color: 2)
            if try c.accept(at: 2326, size: 1, color: 6).uppercased() == "Y" { break }
        }
    }
}

extension Maps04 {
    /// dd/mm/yy を Date-Form に合わせる (ACAS メニューの "on" 表示)
    static func formatShort(_ uk: String, dateForm: Int) -> String {
        let a = Array(Cobol.x(uk, 8))
        switch dateForm {
        case 2: return String(a[3..<5]) + "/" + String(a[0..<2]) + "/" + String(a[6..<8])
        default: return String(a)
        }
    }
}

/// common/maps01.cbl: 会社名・パスワードの符号化 (オープンソース版は符号化処理が除去されている)
public enum Maps01 {
    public static func encodeName(_ name: String) -> String { name }
    public static func encodePassword(_ pw: String) -> String { pw }
}

/// system.dat の RRN 2-4 (既定値 / 決算 / 拡張) の初期値
public enum SystemAuxRecords {
    static func initialDefault() -> [UInt8] { [UInt8](repeating: 0x20, count: 1024) }
    static func initialRecord4() -> [UInt8] { [UInt8](repeating: 0x20, count: 1024) }
}
