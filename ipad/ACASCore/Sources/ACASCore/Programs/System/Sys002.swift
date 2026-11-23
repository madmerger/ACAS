import Foundation

/// common/sys002.cbl: システム設定 (System Set-Up)。
/// 基本情報 → 運用設定 → GL → SL → PL → 在庫 の各画面を順に入力し、system.dat の RRN 1 を書き戻す。
enum Sys002 {
    static let progName = "SYS002 (3.01.39)"
    static let esc = 2005

    final class State {
        var sys = Record(SystemLayout.layout)
        var open = true
        var lineDate = ""          // line-1-date / ws-test-date
        var uBin: Int64 = 0        // maps03-ws u-bin
        var uDate = Cobol.x("", 10)
        var wsDate = Cobol.x("", 10)
        var temps: [String: String] = ["@p-start": "", "@p-end": "", "@pass": "", "@num-6": "00000"]
        var psn = "HPLJ4TCP "
    }

    struct FSpec {
        let line: Int, col: Int, name: String, pic: String
        init(_ line: Int, _ col: Int, _ name: String, _ pic: String) { self.line = line; self.col = col; self.name = name; self.pic = pic }
        var alphaSize: Int? { pic.hasPrefix("x") ? Int(pic.dropFirst()) : nil }
        var intDigits: Int { pic.split(separator: ".", omittingEmptySubsequences: false)[0].count }
        var scale: Int { pic.contains(".") ? pic.split(separator: ".")[1].count : 0 }
    }

    private enum Lab { case key(Int, Int, String), lit(Int, Int, String) }

    static func t(_ s: Session, _ key: String) -> String { s.t("sys002." + key) }

    // MARK: 画面共通

    private static func show(_ s: Session, _ labs: [Lab], color: UInt8 = 2) {
        for l in labs {
            switch l {
            case .key(let line, let col, let k): s.console.display(t(s, k), at: line, col, color: color)
            case .lit(let line, let col, let text): s.console.display(text, at: line, col, color: color)
            }
        }
    }

    private static func fields(_ st: State, _ specs: [FSpec], color: UInt8 = 2) -> [ScreenField] {
        specs.map { sp in
            if let n = sp.alphaSize {
                let v = sp.name.hasPrefix("@") ? (st.temps[sp.name] ?? "") : st.sys.str(sp.name)
                return ScreenField(line: sp.line, col: sp.col, size: n, value: v, color: color)
            }
            var text: String
            if sp.name.hasPrefix("@") {
                text = st.temps[sp.name] ?? ""
            } else {
                let v = abs(st.sys.int(sp.name))
                let p = Cobol.pow10(sp.scale)
                text = Cobol.z((v / p) % Cobol.pow10(sp.intDigits), sp.intDigits)
                if sp.scale > 0 { text += "." + Cobol.z(v % p, sp.scale) }
            }
            return ScreenField(line: sp.line, col: sp.col, size: sp.pic.count, kind: sp.scale > 0 ? .numericEdited : .numeric,
                               pic: sp.pic, value: text, color: color)
        }
    }

    private static func store(_ st: State, _ specs: [FSpec], _ flds: [ScreenField]) {
        for (sp, f) in zip(specs, flds) {
            if sp.name.hasPrefix("@") { st.temps[sp.name] = f.value; continue }
            if sp.alphaSize != nil { st.sys[sp.name] = f.value; continue }
            let (v, sc) = Cobol.numval(f.value)
            st.sys.setInt(sp.name, Cobol.rescale(v, from: sc, to: sp.scale) % Cobol.pow10(sp.intDigits + sp.scale))
        }
    }

    /// display screen / accept screen with update
    private static func acceptScreen(_ s: Session, _ st: State, _ specs: [FSpec], color: UInt8 = 2) throws {
        let f = fields(st, specs, color: color)
        try s.console.acceptScreen(f)
        store(st, specs, f)
    }

    private static func banner(_ s: Session, _ st: State, _ screenNo: Int, _ headKey: String) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 1, 1, color: 2)
        c.display(t(s, "banner"), at: 1, 28, color: 2)
        c.display(Cobol.x(st.lineDate, 10), at: 1, 71, color: 2)
        c.display("++++++++++", at: 3, 1, color: 2)
        c.display(t(s, "screen"), at: 4, 1, color: 2)
        c.display(String(screenNo), at: 4, 9, color: 2)
        c.display("+", at: 4, 10, color: 2)
        c.display("++++++++++", at: 5, 1, color: 2)
        c.display(t(s, headKey), at: 436, color: 2)
    }

    /// verify-screen。戻り値 true = "N" (画面をやり直す)
    private static func verify(_ s: Session, _ key: String, replyColor: UInt8 = 6) throws -> Bool {
        let c = s.console
        c.display("**************************", at: 11, 54, color: 2)
        c.display("*", at: 12, 54, color: 2); c.display("*", at: 12, 79, color: 2)
        c.display("*", at: 13, 54, color: 2)
        c.display(Cobol.x(t(s, key), 24), at: 13, 55, color: 2)
        c.display("*", at: 13, 79, color: 2)
        c.display("*", at: 14, 54, color: 2); c.display("*", at: 14, 79, color: 2)
        c.display(t(s, "v.ok"), at: 15, 54, color: 2)
        c.display("] *", at: 15, 77, color: 2)
        c.display("*", at: 16, 54, color: 2); c.display(" ", at: 16, 55, color: 2); c.display("*", at: 16, 79, color: 2)
        c.display("**************************", at: 17, 54, color: 2)
        c.display("Y", at: 1576, color: replyColor)
        let r = try c.accept(at: 1576, size: 1, initial: "Y", options: [.update], color: 6)
        return r == "N" || r == "n"
    }

    // MARK: 日付 (maps04 / zz050 / zz060)

    static func maps04(_ st: State) {
        if st.uBin > 0 {
            st.uDate = Maps04.toDate(Int(st.uBin))
        } else {
            st.uDate = String(Cobol.x(st.uDate, 10).map { ".,-".contains($0) ? Character("/") : $0 })
            let b = Maps04.toBinary(st.uDate)
            if b != 0 { st.uBin = Int64(b) }
        }
    }

    /// zz050-Validate-Date
    static func validateDate(_ st: State, _ test: String) {
        let a = Array(Cobol.x(test, 10).map { ".,-".contains($0) ? Character("/") : $0 })
        if st.sys.int("date-form") == 0 { st.sys.setInt("date-form", 1) }
        var d = a
        switch st.sys.int("date-form") {
        case 1: break
        case 2: d.replaceSubrange(0..<2, with: a[3..<5]); d.replaceSubrange(3..<5, with: a[0..<2])
        default:
            d = Array("dd/mm/ccyy")
            d.replaceSubrange(6..<10, with: a[0..<4]); d.replaceSubrange(3..<5, with: a[5..<7]); d.replaceSubrange(0..<2, with: a[8..<10])
        }
        st.wsDate = String(d)
        st.uDate = st.wsDate
        st.uBin = 0
        maps04(st)
    }

    /// zz060-Convert-Date
    static func convertDate(_ st: State) {
        maps04(st)
        if st.uDate.allSatisfy({ $0 == " " }) { st.wsDate = Cobol.x("", 10); return }
        let u = Array(Cobol.x(st.uDate, 10))
        let df = st.sys.int("date-form")
        if df == 0 || df > 3 { st.sys.setInt("date-form", 1) }
        switch st.sys.int("date-form") {
        case 1: st.wsDate = String(u)
        case 2: st.wsDate = String(u[3..<5]) + String(u[2]) + String(u[0..<2]) + String(u[5..<10])
        default: st.wsDate = String(u[6..<10]) + "/" + String(u[3..<5]) + "/" + String(u[0..<2])
        }
    }

    // MARK: init01

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State()
        try getEnv(s)
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(t(s, "title"), at: 130, color: 2)
        let f = s.systemFile
        st.open = s.store.exists(s.ledgers + SystemLayout.path)
        try diskError(s, "sy101", st.open ? "00" : "35")
        if st.open {
            if f.read(4) == nil { f.write(4, SystemAuxRecords.initialRecord4()) }
            if f.read(3) == nil { f.write(3, SystemAuxRecords.initialFinal()) }
            if f.read(2) == nil { f.write(2, SystemAuxRecords.initialDefault()) }
        }
        var status = "00"
        if st.open, let b = f.read(1) {
            st.sys = Record(SystemLayout.layout, bytes: b)
        } else {
            st.sys = Record(SystemLayout.layout)
            st.sys.setInt("system-record-version-prime", 1)
            st.sys.setInt("system-record-version-secondary", 1)
            st.sys.setInt("date-form", 1)
            if st.open { f.write(1, st.sys.bytes) } else { status = "47" }
        }
        try diskError(s, "sy102", status)
        st.uBin = st.sys.int("run-date")
        convertDate(st)
        st.lineDate = st.wsDate
        try userParams(s, st)
        if c.crtStatus == esc { return }
        try systemParams(s, st)
        if st.sys.int("level-1") == 1 { try glParams(s, st) }
        if st.sys.int("level-3") == 1 { try slParams(s, st) }
        if st.sys.int("level-2") == 1 { try plParams(s, st) }
        if st.sys.int("level-4") == 1 { try stockParams(s, st) }
        try Sys002Print.run(s, st)
        // Menu-Option
        c.display(" ", at: 101, eraseEOS: true)
        if st.open { f.write(1, st.sys.bytes) }
        try diskError(s, "sy103", st.open ? "00" : "49")
        s.termCode = 0
    }

    /// zz010-Get-Env-Set-Files (端末内では既定値が常に設定されている)
    private static func getEnv(_ s: Session) throws {
        let c = s.console
        let unset = ["ACAS_IRS", "ACAS_LEDGERS", "ACAS_BIN"].contains { (s.environment[$0] ?? "").first.map { $0 == " " } ?? true }
        if unset {
            c.display(t(s, "sy009"), at: 505, highlight: true, eraseEOS: true)
            c.display(t(s, "sy008"), at: 1210, color: 3, highlight: true)
            _ = try c.accept(at: 1243, size: 1)
            throw StopRun()
        }
    }

    /// Disk-Error-Display / Disk-Error
    private static func diskError(_ s: Session, _ actionKey: String, _ status: String) throws {
        guard status != "00" else { return }
        let c = s.console
        c.display(t(s, actionKey), at: 310)
        c.display(status, at: 330)
        c.display(" ", at: 410)
        c.display(t(s, "sy104"), at: 2401)
        _ = try c.accept(at: 2420, size: 2)
    }

    // MARK: User-Params

    private static let userLabels: [Lab] = [
        .key(7, 1, "u.name"), .lit(7, 9, "- {"), .lit(7, 44, "}"),
        .key(8, 1, "u.address"), .lit(8, 36, "]"),
        .lit(9, 11, "["), .lit(9, 36, "]"), .lit(10, 11, "["), .lit(10, 36, "]"), .lit(11, 11, "["), .lit(11, 36, "]"),
        .key(12, 1, "u.postcode"), .lit(12, 24, "]"),
        .key(13, 1, "u.country"), .lit(13, 36, "]"),
        .key(14, 1, "u.dateform"), .lit(14, 15, "- ["), .lit(14, 19, "]"), .key(14, 20, "u.dateform_hint"),
        .key(15, 1, "u.period_start"), .lit(15, 35, "]"),
        .key(16, 11, "u.period_end"), .lit(16, 35, "]"),
        .key(17, 1, "u.print_lines"), .lit(17, 24, "["), .lit(17, 28, "]"), .key(17, 30, "u.laser"),
        .key(18, 1, "u.vat1"), .lit(18, 22, "- ["), .lit(18, 30, "]"), .key(18, 40, "u.tax4"), .lit(18, 57, "- ["), .lit(18, 65, "]"),
        .lit(19, 13, "(2)"), .lit(19, 22, "- ["), .lit(19, 30, "]"), .key(19, 40, "u.tax5"), .lit(19, 57, "- ["), .lit(19, 65, "]"),
        .lit(20, 13, "(3)"), .lit(20, 22, "- ["), .lit(20, 30, "]"), .key(20, 40, "u.cycle"), .lit(20, 58, "- ["), .lit(20, 63, "]"),
        .key(21, 1, "u.vatreg"), .lit(21, 26, "]"), .key(21, 27, "u.printed"), .lit(21, 38, "]"),
        .key(21, 40, "u.quarter"), .lit(21, 58, "- ["), .lit(21, 63, "]"),
        .key(22, 1, "u.password"), .lit(22, 20, "- ["), .lit(22, 27, "]"), .key(22, 40, "u.cycle_period"), .lit(22, 58, "- ["), .lit(22, 63, "]"),
        .key(23, 1, "u.file_handling"), .lit(23, 22, "- ["), .lit(23, 26, "]"), .key(23, 28, "u.range01"),
        .key(23, 40, "u.dual"), .lit(23, 61, "- ["), .lit(23, 65, "]"), .key(23, 67, "u.range01b"),
    ]

    private static let userFields: [FSpec] = [
        FSpec(8, 12, "address-1", "x24"), FSpec(9, 12, "address-2", "x24"), FSpec(10, 12, "address-3", "x24"),
        FSpec(11, 12, "address-4", "x24"), FSpec(12, 12, "post-code", "x12"), FSpec(13, 12, "country", "x24"),
        FSpec(14, 18, "date-form", "9"), FSpec(15, 25, "@p-start", "x10"), FSpec(16, 25, "@p-end", "x10"),
        FSpec(17, 25, "page-lines", "999"),
        FSpec(18, 25, "vat-rate-1", "99.99"), FSpec(18, 60, "vat-rate-4", "99.99"),
        FSpec(19, 25, "vat-rate-2", "99.99"), FSpec(19, 60, "vat-rate-5", "99.99"),
        FSpec(20, 25, "vat-rate-3", "99.99"), FSpec(20, 61, "scycle", "99"),
        FSpec(21, 15, "vat-reg-number", "x11"), FSpec(21, 37, "sl-vat-printed", "x1"), FSpec(21, 61, "current-quarter", "99"),
        FSpec(22, 23, "@pass", "x4"), FSpec(22, 61, "period", "99"),
        FSpec(23, 25, "file-system-used", "9"), FSpec(23, 64, "file-duplicates-in-use", "9"),
    ]

    private static func userParams(_ s: Session, _ st: State) throws {
        let c = s.console
        mainUser: while true {
            banner(s, st, 1, "hd.user")
            for (name, key) in [("start-date", "@p-start"), ("end-date", "@p-end")] {
                if st.sys.int(name) != 0 {
                    st.uBin = st.sys.int(name)
                    convertDate(st)
                    st.temps[key] = st.wsDate
                } else { st.temps[key] = "" }
            }
            st.temps["@pass"] = ""
            show(s, userLabels)
            c.display(Cobol.x(st.sys.str("usera"), 32), at: 7, 12, color: 2)
            c.displayFields(fields(st, userFields))
            while true {
                // ACCEPT user-data は画面定義の固定文言も再表示する
                show(s, userLabels)
                c.display(Cobol.x(st.sys.str("usera"), 32), at: 7, 12, color: 2)
                try acceptScreen(s, st, userFields)
                if c.crtStatus == esc { return }
                switch st.sys.int("date-form") {
                case 1: c.display(t(s, "u.fmt_uk"), at: 1420, color: 3, eraseEOL: true)
                case 2: c.display(t(s, "u.fmt_usa"), at: 1420, color: 3, eraseEOL: true)
                case 3: c.display(t(s, "u.fmt_intl"), at: 1420, color: 3, eraseEOL: true)
                default:
                    c.display(t(s, "u.fmt_bad"), at: 1420, color: 4, highlight: true, eraseEOL: true)
                    st.sys.setInt("date-form", 1)
                }
                var again = false
                for (key, name, at) in [("@p-start", "start-date", 1540), ("@p-end", "end-date", 1640)] {
                    let p = Cobol.x(st.temps[key] ?? "", 10)
                    if !p.allSatisfy({ $0 == " " }) {
                        validateDate(st, p)
                        st.temps[key] = st.uDate
                    }
                    if st.uBin == 0 {
                        c.display(t(s, "sy005"), at: at, color: 3)
                        again = true
                        break
                    }
                    c.display(" ", at: at, eraseEOL: true)
                    st.sys.setInt(name, st.uBin)
                }
                if again { continue }
                let pw = Cobol.x(st.temps["@pass"] ?? "", 4)
                if !pw.allSatisfy({ $0 == " " }) { st.sys["pass-word"] = Maps01.password(s, pw) }
                if st.sys.int("period") == 13 {
                    c.display(t(s, "u.weekly"), at: 2270, color: 3)
                } else if st.sys.int("period") == 6 {
                    c.display(t(s, "u.fortnightly"), at: 2270, color: 3)
                } else {
                    st.sys.setInt("period", 3)
                    c.display(t(s, "u.monthly"), at: 2270, color: 3)
                }
                if st.sys.int("page-lines") <= 28 {
                    st.sys.setInt("page-lines", 48)
                    c.display(t(s, "sy105"), at: 1750, color: 3)
                    continue
                }
                c.display(" ", at: 1750, eraseEOL: true)
                break
            }
            let fsu = st.sys.int("file-system-used")
            if fsu != 0 && fsu != 1 {
                st.sys.setInt("file-system-used", 0)
                c.display(t(s, "u.range_only"), at: 2410, color: 3)
            } else if fsu == 0 {
                c.display(t(s, "u.cobol_files"), at: 2410, color: 3)
            } else {
                c.display(t(s, "u.rdbms"), at: 2410, color: 3)
            }
            let dup = st.sys.int("file-duplicates-in-use")
            if dup != 0 && dup != 1 {
                st.sys.setInt("file-duplicates-in-use", 0)
                c.display(t(s, "u.range_only"), at: 2450, color: 3)
            } else if dup == 1 {
                c.display(t(s, "u.dup_used"), at: 2441, color: 3)
            } else {
                c.display(t(s, "u.dup_not_used"), at: 2441, color: 3)
            }
            upper(st, "sl-vat-printed")
            if st.sys.str("sl-vat-printed") != "Y" && st.sys.str("sl-vat-printed") != "N" {
                st.sys["sl-vat-printed"] = "N"
                c.display("N", at: 2137, color: 3)
            }
            if try verify(s, "v.user") { continue mainUser }
            return
        }
    }

    private static func upper(_ st: State, _ name: String) { st.sys[name] = st.sys.str(name).uppercased() }
    private static func blank(_ st: State, _ name: String) -> Bool { st.sys.str(name).allSatisfy { $0 == " " } }

    // MARK: system-params

    private static let opsLabels: [Lab] = [
        .key(17, 2, "o.host"), .key(17, 24, "o.host_hint"),
        .key(19, 2, "o.opsys"), .lit(19, 20, "- ["), .lit(19, 24, "]"), .key(19, 27, "o.opsys_hint"),
        .key(21, 2, "o.capture"), .lit(21, 22, "- ["), .key(21, 26, "o.capture_hint"),
    ]
    private static let opsFields = [FSpec(17, 23, "host", "9"), FSpec(19, 23, "op-system", "9"), FSpec(21, 25, "data-capture-used", "9")]
    private static let ops2Labels: [Lab] = [
        .key(21, 2, "o.spool1"), .lit(21, 79, "]"), .key(22, 2, "o.spool2"), .lit(22, 79, "]"), .key(23, 2, "o.spool3"), .lit(23, 79, "]"),
    ]
    private static let ops2Fields = [
        FSpec(21, 31, "print-spool-name", "x48"), FSpec(22, 31, "print-spool-name2", "x48"), FSpec(23, 31, "print-spool-name3", "x48"),
    ]
    private static let ops3Labels: [Lab] = [
        .key(7, 2, "o.schema"), .key(7, 33, "o.schema_hint"), .key(8, 2, "o.dbuser"), .lit(8, 29, "]"),
        .key(9, 2, "o.dbpass"), .lit(9, 34, "] "),
    ]
    private static let ops3Fields = [
        FSpec(7, 21, "rdbms-db-name", "x12"), FSpec(8, 17, "rdbms-user", "x12"), FSpec(9, 22, "rdbms-passwd", "x12"),
    ]

    private static func systemParams(_ s: Session, _ st: State) throws {
        let c = s.console
        while true {
            banner(s, st, 2, "hd.ops1")
            show(s, opsLabels)
            c.displayFields(fields(st, opsFields))
            try acceptScreen(s, st, opsFields)
            let host = st.sys.int("host")
            if host != 0 && host != 1 {
                st.sys.setInt("host", 1)
                c.display(t(s, "o.multi_assumed"), at: 1823, color: 3)
            } else if host == 0 {
                c.display(t(s, "o.single"), at: 1823, color: 3)
            } else {
                c.display(t(s, "o.multi"), at: 1823, color: 3)
            }
            c.display(String(repeating: " ", count: 51), at: 20, 1)
            let os = st.sys.int("op-system")
            if st.sys.int("host") == 0 && (os < 1 || os > 6) {
                st.sys.setInt("op-system", 1)
                c.display(t(s, "o.msdos_assumed"), at: 2023, color: 3)
            } else if st.sys.int("host") == 1 && (os < 2 || os > 6) {
                st.sys.setInt("op-system", 6)
                c.display(t(s, "o.linux_assumed"), at: 2023, color: 3)
            } else if (1...6).contains(os) {
                c.display(["DOS", "Windows", "Mac OSX", "OS/2", "Unix", "Linux"][Int(os) - 1], at: 2023, color: 3)
            }
            let os2 = st.sys.int("op-system")
            if os2 == 3 || os2 == 5 || os2 == 6 {
                if blank(st, "print-spool-name2") { st.sys["print-spool-name2"] = st.sys.str("print-spool-name") }
                if blank(st, "print-spool-name3") { st.sys["print-spool-name3"] = st.sys.str("print-spool-name") }
                show(s, ops2Labels)
                c.displayFields(fields(st, ops2Fields))
                try acceptScreen(s, st, ops2Fields)
                if Cobol.x(st.sys.str("print-spool-name"), 48).first == " " {
                    c.display(t(s, "o.spool_required"), at: 2402, color: 3, highlight: true)
                } else {
                    st.psn = st.sys.str("print-spool-name")
                }
            }
            switch st.sys.int("data-capture-used") {
            case 0: c.display(t(s, "o.dc_std"), at: 2054, color: 3)
            case 1: c.display(t(s, "o.dc_gui"), at: 2054, color: 3)
            case 2: c.display(t(s, "o.dc_widget"), at: 2054, color: 3)
            default:
                c.display(t(s, "o.dc_invalid"), at: 2054, color: 3, highlight: true)
                st.sys.setInt("data-capture-used", 0)
            }
            if st.sys.str("maps-ser-xx") == "mp" && st.sys.int("maps-ser-nn") == 9999 {
                c.display(t(s, "o.free"), at: 1501, color: 3, highlight: true)
            } else {
                c.display(t(s, "o.commercial"), at: 1501, color: 3, highlight: true)
            }
            if try !verify(s, "v.ops1") { break }
        }
        if st.sys.int("file-system-used") == 0 { return }
        while true {
            banner(s, st, 3, "hd.ops2")
            show(s, ops3Labels)
            c.displayFields(fields(st, ops3Fields))
            try acceptScreen(s, st, ops3Fields)
            if !blank(st, "rdbms-db-name") { c.display(t(s, "o.db_set"), at: 746, color: 3) }
            if !blank(st, "rdbms-user") { c.display(t(s, "o.user_set"), at: 846, color: 3) }
            if !blank(st, "rdbms-passwd") {
                c.display(t(s, "o.pwd_set"), at: 946, color: 3)
                c.display("************", at: 922)
            }
            if try !verify(s, "v.ops2") { break }
        }
    }

    // MARK: gl-params

    private static let glLabels: [Lab] = [
        .key(7, 1, "g.pc"), .lit(7, 29, "]"), .key(7, 30, "g.pc_hint"),
        .key(8, 1, "g.level"), .lit(8, 25, "- ["), .lit(8, 29, "]"), .key(8, 30, "g.level_hint"),
        .key(9, 1, "g.grouped"), .lit(9, 29, "]"), .key(9, 30, "g.grouped_hint"),
        .key(10, 1, "g.comps"), .lit(10, 25, "- ["), .lit(10, 29, "]"), .key(10, 30, "g.yes_space"),
        .key(11, 1, "g.index"), .lit(11, 25, "- ["), .lit(11, 29, "]"), .key(11, 30, "g.yes_space"),
        .key(12, 1, "g.mv"), .lit(12, 25, "- ["), .lit(12, 29, "]"), .key(12, 30, "g.yes_space"),
        .key(13, 1, "g.arch"), .lit(13, 25, "- ["), .lit(13, 29, "]"), .key(13, 30, "g.yes_space"),
        .key(14, 1, "g.sales_range"), .lit(14, 25, "- ["), .lit(14, 29, "]"),
        .key(15, 1, "g.purch_range"), .lit(15, 25, "- ["), .lit(15, 29, "]"),
        .key(16, 1, "g.autovat"), .lit(16, 29, "]"), .key(16, 30, "g.yes_space"),
        .key(17, 1, "g.next_batch"), .lit(17, 21, "- ["), .lit(17, 29, "]"),
        .key(18, 1, "g.irs"), .lit(18, 29, "]"), .key(18, 30, "g.yes_no"),
    ]
    private static let glFields = [
        FSpec(7, 28, "p-c", "x1"), FSpec(8, 28, "p-c-level", "x1"), FSpec(9, 28, "p-c-grouped", "x1"), FSpec(10, 28, "comps", "x1"),
        FSpec(11, 28, "ledger-2nd-index", "x1"), FSpec(12, 28, "m-v", "x1"), FSpec(13, 28, "arch", "x1"),
        FSpec(14, 28, "sales-range", "9"), FSpec(15, 28, "purchase-range", "9"), FSpec(16, 28, "vat", "x1"),
        FSpec(17, 24, "@num-6", "99999"), FSpec(18, 28, "irs-instead", "x1"),
    ]

    private static func glParams(_ s: Session, _ st: State) throws {
        let c = s.console
        while true {
            banner(s, st, 4, "hd.gl")
            st.temps["@num-6"] = Cobol.z(abs(st.sys.int("next-batch")) % 100000, 5)
            show(s, glLabels)
            c.displayFields(fields(st, glFields))
            try acceptScreen(s, st, glFields, color: 3)
            st.sys.setInt("next-batch", Cobol.numval(st.temps["@num-6"] ?? "").0)
            upper(st, "p-c")
            if st.sys.str("p-c") == "P" {
                c.display(t(s, "g.pc_selected"), at: 732, color: 2)
            } else if st.sys.str("p-c") == "B" {
                c.display(t(s, "g.br_selected"), at: 732, color: 2)
            } else {
                st.sys["p-c"] = " "
                c.display(t(s, "g.not_selected"), at: 732, color: 2)
                upper(st, "p-c-level")
            }
            if blank(st, "p-c") && !blank(st, "p-c-level") { st.sys["p-c-level"] = " " }
            if !blank(st, "p-c") && st.sys.str("p-c-level") == "R" { c.display(t(s, "g.rev_only"), at: 832, color: 2) }
            if !blank(st, "p-c") && st.sys.str("p-c-level") != "R" {
                st.sys["p-c-level"] = " "
                c.display(t(s, "g.all_acs"), at: 832, color: 2)
            }
            upper(st, "p-c-grouped")
            c.display(t(s, "g.first_digit"), at: 932, color: 2)
            if st.sys.str("p-c-grouped") == "Y" {
                c.display(t(s, "g.is_group"), at: 957, color: 2)
            } else {
                c.display(t(s, "g.not_signif"), at: 957, color: 2)
                st.sys["p-c-grouped"] = " "
            }
            for (name, at, reset) in [("comps", 1032, true), ("ledger-2nd-index", 1132, true), ("m-v", 1232, true),
                                      ("arch", 1332, true), ("vat", 1632, true), ("irs-instead", 1832, false)] {
                upper(st, name)
                if st.sys.str(name) == "Y" {
                    c.display(t(s, "g.selected"), at: at, color: 2)
                } else {
                    if reset { st.sys[name] = " " }
                    c.display(t(s, "g.not_selected16"), at: at, color: 2)
                }
            }
            if try !verify(s, "v.gl", replyColor: 2) { return }
        }
    }

    // MARK: sl-params

    private static let slLabels: [Lab] = [
        .key(7, 1, "s.dunning"), .lit(7, 15, "- ["), .lit(7, 19, "]"), .key(7, 20, "s.yes0"),
        .key(8, 1, "s.charges"), .lit(8, 15, "- ["), .lit(8, 19, "]"), .key(8, 20, "s.yes0"),
        .key(9, 1, "s.credit"), .lit(9, 20, "]"),
        .key(10, 1, "s.disc"), .lit(10, 15, "- ["), .lit(10, 23, "]"),
        .key(11, 1, "s.min"), .lit(11, 15, "- ["), .lit(11, 22, "]"),
        .key(12, 1, "s.max"), .lit(12, 22, "]"),
        .key(13, 1, "s.limit"), .lit(13, 15, "- ["), .lit(13, 25, "]"),
        .key(14, 1, "s.delim"), .lit(14, 15, "- ["), .lit(14, 19, "]"), .key(14, 20, "s.delim_hint"),
        .key(15, 1, "s.own_nos"), .lit(15, 15, "- ["), .lit(15, 19, "]"),
        .key(16, 1, "s.late_per"), .lit(16, 22, "]"),
        .key(17, 1, "s.next_batch"), .lit(17, 25, "]"),
        .key(18, 1, "s.stock_link"), .lit(18, 21, "]"),
        .key(19, 1, "s.pay_ac"), .lit(19, 26, "]"),
        .key(20, 1, "s.ledger_ac"), .lit(20, 26, "]"),
        .key(21, 1, "s.debtors_ac"), .lit(21, 26, "]"),
    ]
    private static let slFields = [
        FSpec(7, 18, "sl-dunning", "9"), FSpec(8, 18, "sl-charges", "9"), FSpec(9, 18, "sl-credit", "99"),
        FSpec(10, 18, "sl-disc", "99.99"), FSpec(11, 18, "sl-min", "9999"), FSpec(12, 18, "sl-max", "9999"),
        FSpec(13, 18, "sl-limit", "9999999"), FSpec(14, 18, "sl-delim", "x1"), FSpec(15, 18, "sl-own-nos", "x1"),
        FSpec(16, 18, "sl-late-per", "9.99"), FSpec(17, 20, "first-sl-batch", "99999"), FSpec(18, 20, "sl-stock-link", "x1"),
        FSpec(19, 20, "sl-pay-ac", "999999"), FSpec(20, 20, "sl-sales-ac", "999999"), FSpec(21, 20, "s-debtors", "999999"),
    ]
    private static let sl2Labels: [Lab] = [
        .key(7, 1, "s2.title"), .key(8, 1, "s2.inv"), .lit(8, 20, "]"), .key(9, 1, "s2.stat"), .lit(9, 20, "]"),
        .key(10, 1, "s2.lets"), .lit(10, 20, "]"), .key(11, 1, "s2.pick"), .lit(11, 20, "]"),
    ]
    private static let sl2Fields = [
        FSpec(8, 19, "sl-comp-head-inv", "x1"), FSpec(9, 19, "sl-comp-head-stat", "x1"),
        FSpec(10, 19, "sl-comp-head-lets", "x1"), FSpec(11, 19, "sl-comp-head-pick", "x1"),
    ]

    private static func setOrUnset(_ s: Session, _ st: State, _ name: String, _ at: Int, eraseSet: Bool = true) {
        if st.sys.int(name) != 0 {
            s.console.display(t(s, "s.sel_set"), at: at, color: 2, eraseEOL: eraseSet)
        } else {
            s.console.display(t(s, "s.unset"), at: at, color: 3, eraseEOL: true)
        }
    }

    private static func slParams(_ s: Session, _ st: State) throws {
        let c = s.console
        while true {
            banner(s, st, 5, "hd.sl1")
            show(s, slLabels)
            c.displayFields(fields(st, slFields))
            try acceptScreen(s, st, slFields)
            if st.sys.int("sl-dunning") == 1 {
                c.display(t(s, "s.dun_sel"), at: 722, color: 2)
            } else {
                st.sys.setInt("sl-dunning", 0)
                c.display(t(s, "s.dun_not"), at: 722, color: 2)
            }
            if st.sys.int("sl-charges") == 1 {
                c.display(t(s, "s.chg_sel"), at: 822, color: 2)
            } else {
                st.sys.setInt("sl-charges", 0)
                c.display(t(s, "s.chg_not"), at: 822, color: 2)
            }
            if blank(st, "sl-delim") {
                c.display(t(s, "s.delim_assumed"), at: 1422, color: 2)
                st.sys["sl-delim"] = "\\"
            }
            upper(st, "sl-own-nos")
            c.display(t(s, st.sys.str("sl-own-nos") == "Y" ? "s.sel_set" : "s.unset7"), at: 1528, color: 2)
            upper(st, "sl-stock-link")
            if st.sys.str("sl-stock-link") == "Y" && st.sys.int("level-4") == 1 {
                c.display(t(s, "s.sel_set16"), at: 1828, color: 2)
            } else {
                st.sys["sl-stock-link"] = "N"
                c.display(t(s, "s.unset_nostock"), at: 1828, color: 3)
            }
            setOrUnset(s, st, "sl-pay-ac", 1928, eraseSet: false)
            setOrUnset(s, st, "sl-sales-ac", 2028)
            setOrUnset(s, st, "s-debtors", 2128)
            if try !verify(s, "v.sl") { break }
        }
        while true {
            banner(s, st, 6, "hd.sl2")
            c.display(" ", at: 7, 1, eraseEOS: true)
            show(s, sl2Labels)
            c.displayFields(fields(st, sl2Fields))
            try acceptScreen(s, st, sl2Fields)
            for name in ["sl-comp-head-inv", "sl-comp-head-stat", "sl-comp-head-lets", "sl-comp-head-pick"] { upper(st, name) }
            for (name, at) in [("sl-comp-head-inv", 822), ("sl-comp-head-stat", 922), ("sl-comp-head-lets", 1022), ("sl-comp-head-pick", 1122)] {
                if st.sys.str(name) != "Y" && st.sys.str(name) != "N" {
                    c.display(t(s, "s2.error"), at: at, color: 4, highlight: true)
                    st.sys[name] = "N"
                }
            }
            if try !verify(s, "v.sl2") { return }
        }
    }

    // MARK: pl-params

    private static let plLabels: [Lab] = [
        .key(14, 1, "s.delim"), .lit(14, 15, "- ["), .lit(14, 19, "]"),
        .key(15, 1, "p.stock_link"), .lit(15, 21, "]"),
        .key(17, 1, "s.next_batch"), .lit(17, 25, "]"),
        .key(18, 1, "p.pay_ac"), .lit(18, 26, "]"),
        .key(19, 1, "p.ledger_ac"), .lit(19, 26, "]"),
        .key(20, 1, "p.creditor_ac"), .lit(20, 26, "]"),
    ]
    private static let plFields = [
        FSpec(14, 18, "pl-delim", "x1"), FSpec(15, 20, "pl-stock-link", "x1"), FSpec(17, 20, "bl-next-batch", "99999"),
        FSpec(18, 20, "bl-pay-ac", "999999"), FSpec(19, 20, "bl-purch-ac", "999999"), FSpec(20, 20, "p-creditors", "999999"),
    ]

    private static func plParams(_ s: Session, _ st: State) throws {
        let c = s.console
        while true {
            banner(s, st, 7, "hd.pl")
            show(s, plLabels)
            c.displayFields(fields(st, plFields))
            try acceptScreen(s, st, plFields)
            if blank(st, "pl-delim") {
                c.display(t(s, "s.delim_assumed"), at: 1422, color: 2)
                st.sys["pl-delim"] = "\\"
            }
            upper(st, "pl-stock-link")
            if st.sys.str("pl-stock-link") == "Y" && st.sys.int("level-4") == 1 {
                c.display(t(s, "s.sel_set"), at: 1528, color: 2, eraseEOL: true)
            } else {
                st.sys["pl-stock-link"] = "N"
                c.display(t(s, "s.unset_nostock"), at: 1528, color: 3, eraseEOL: true)
            }
            setOrUnset(s, st, "bl-pay-ac", 1828)
            setOrUnset(s, st, "bl-purch-ac", 1928)
            setOrUnset(s, st, "p-creditors", 2028)
            if try !verify(s, "v.pl") { return }
        }
    }

    // MARK: Stock-Params

    private static let stockLabels: [Lab] = {
        var l: [Lab] = []
        for (line, key) in [(7, "k.debug"), (9, "k.manu"), (10, "k.oe"), (11, "k.audit"), (12, "k.mov"), (15, "k.ave")] {
            l += [.key(line, 1, key), .lit(line, 15, "- ["), .lit(line, 19, "]"), .key(line, 20, "s.yes0")]
        }
        l += [.key(13, 1, "k.cur"), .lit(13, 15, "- ["), .lit(13, 19, "]"), .key(13, 20, "k.cur_hint"),
              .key(14, 1, "k.dat"), .lit(14, 15, "- ["), .lit(14, 19, "]"), .key(14, 20, "k.dat_hint"),
              .key(17, 1, "k.next2"),
              .key(18, 1, "k.act"), .lit(18, 15, "- ["), .lit(18, 19, "]"), .key(18, 20, "k.act_hint"),
              .key(19, 1, "k.audit_no"), .lit(19, 15, "- ["), .lit(19, 21, "]"), .key(19, 23, "k.audit_hint")]
        return l
    }()
    private static let stockFields = [
        FSpec(7, 18, "stk-debug", "9"), FSpec(9, 18, "stk-manu-used", "9"), FSpec(10, 18, "stk-oe-used", "9"),
        FSpec(11, 18, "stk-audit-used", "9"), FSpec(12, 18, "stk-mov-audit", "9"), FSpec(13, 18, "stk-period-cur", "x1"),
        FSpec(14, 18, "stk-period-dat", "x1"), FSpec(15, 18, "stk-averaging", "9"), FSpec(18, 18, "stk-activity-rep-run", "9"),
        FSpec(19, 18, "stk-audit-no", "999"),
    ]

    private static func stockParams(_ s: Session, _ st: State) throws {
        let c = s.console
        func flag(_ name: String, _ at: Int) {
            if st.sys.int(name) == 1 {
                c.display(t(s, "k.set"), at: at, color: 3, eraseEOL: true)
            } else {
                st.sys.setInt(name, 0)
                c.display(t(s, "k.unset"), at: at, color: 3, eraseEOL: true)
            }
        }
        while true {
            banner(s, st, 8, "hd.stock")
            show(s, stockLabels)
            c.displayFields(fields(st, stockFields))
            try acceptScreen(s, st, stockFields)
            flag("stk-debug", 720); flag("stk-manu-used", 920); flag("stk-oe-used", 1020)
            flag("stk-audit-used", 1120); flag("stk-mov-audit", 1220)
            upper(st, "stk-period-cur")
            switch st.sys.str("stk-period-cur") {
            case "M": c.display(t(s, "k.monthly"), at: 1320, color: 3, eraseEOL: true)
            case "Q": c.display(t(s, "k.quarterly"), at: 1320, color: 3, eraseEOL: true)
            case "W": c.display(t(s, "k.weekly"), at: 1320, color: 3, eraseEOL: true)
            default:
                st.sys["stk-period-cur"] = "M"
                c.display(t(s, "k.def_monthly"), at: 1320, color: 3, highlight: true, eraseEOL: true)
            }
            upper(st, "stk-period-dat")
            switch st.sys.str("stk-period-dat") {
            case "M": c.display(t(s, "k.monthly"), at: 1420, color: 3, eraseEOL: true)
            case "Q": c.display(t(s, "k.quarterly"), at: 1420, color: 3, eraseEOL: true)
            case "Y": c.display(t(s, "k.yearly"), at: 1420, color: 3, eraseEOL: true)
            default:
                st.sys["stk-period-dat"] = "Y"
                c.display(t(s, "k.def_yearly"), at: 1420, color: 3, highlight: true, eraseEOL: true)
            }
            flag("stk-averaging", 1520); flag("stk-activity-rep-run", 1820)
            if st.sys.int("stk-audit-no") > 0 {
                c.display(t(s, "k.set2"), at: 1922, color: 3, eraseEOL: true)
            } else {
                st.sys.setInt("stk-audit-no", 0)
                c.display(t(s, "k.set_zero"), at: 1922, color: 4, highlight: true, eraseEOL: true)
            }
            if try !verify(s, "v.stock") { return }
        }
    }
}
