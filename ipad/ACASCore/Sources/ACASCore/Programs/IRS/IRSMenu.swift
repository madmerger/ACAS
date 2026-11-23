import Foundation

/// incomplete_records_system/irs.cbl: IRS システムメニューとシステムファイル設定 (set-up)
enum IRSMenu {
    static let progName = "IRS (3.01.18)"

    /// data-files (acnts.dat / system.dat / dflt.dat / post.dat / prn + op-system)
    static let dataFileNames = "acnts.dat" + "system.dat" + "dflt.dat" + "post.dat" + Cobol.x("prn", 12) + " "

    final class State {
        var dataFiles = dataFileNames   // 48 桁
        var opSystem: Character = "0"
        var exitToSystem = Cobol.x("to Linux", 18)
        var batchText = Cobol.x("", 28)
        var wsPass = "    "
        var validOS: Bool { ("1"..."6").contains(opSystem) }
    }

    static func run(_ s: Session) throws {
        let ctx = IRS.context(s)
        let st = State()
        // initialize system-record
        ctx.sys = IRS.initialSystemRecord()
        ctx.sys["fn-2"] = "system.dat"
        if !IRSub2.read(s) {
            ctx.sys.setInt("next-post", 0)
            ctx.sys["run-date"] = todayShort(s)
            try setUp(s, st)
        }
        moveSystemFilesToDataFiles(ctx, st)
        if !spoolValid(ctx.sys.str("print-spool-name")) {
            ctx.sys["print-spool-name"] = ""
            try setUp(s, st)
        }
        let exitKey: String
        switch st.opSystem {
        case "1": exitKey = "irs.to_dos"
        case "2": exitKey = "irs.to_windows"
        case "3": exitKey = "irs.to_mac"
        case "4": exitKey = "irs.to_os2"
        case "5": exitKey = "irs.to_unix"
        case "6": exitKey = "irs.to_linux"
        default: exitKey = "irs.to_unknown"
        }
        st.exitToSystem = Cobol.x(s.t(exitKey), 18)
        if todayShort(s) != ctx.sys.str("run-date") {
            ctx.sys["run-date"] = todayShort(s)
            try setUp(s, st)
        }
        // CBL_CHECK_FILE_EXIST: 端末内にはバックアップスクリプト (irsbakup.sh 等) が存在しない
        st.batchText = Cobol.x(s.t("irs.backup_not_found"), 28)
        // Get-Env-Set-Files
        if (s.environment["ACAS_IRS"] ?? "").isEmpty {
            s.console.display(s.t("irs.env_not_set"), at: 505, eraseEOS: true)
            throw StopRun()
        }

        let c = s.console
        mainLoop: while true {
            displayMenu1(s, st)
            let reply = try c.accept(at: 534, size: 1, initial: " ", options: [.update, .auto, .prompt], color: 6)
            let f = c.crtStatus
            func call(_ names: String...) throws {
                for n in names { try s.call(n) }
            }
            if reply == "1" || f == 1001 { try setUp(s, st); continue }
            if reply == "2" || f == 1002 { try call("irs010"); continue }
            if reply == "3" || f == 1003 { try call("irs020"); continue }
            if reply == "4" || f == 1004 { try call("irs030"); continue }
            if reply == "5" || f == 1005 { try call("irs040"); continue }
            if reply == "6" || f == 1006 { try call("irs050"); continue }
            if reply == "7" || f == 1007 { try call("irs065", "irs060"); continue }
            if reply == "8" || f == 1008 { try call("irs070"); continue }
            if reply == "9" || f == 1009 { try call("irs085", "irs090"); continue }
            if reply == "|" {
                let prog = try c.accept(at: 101, size: 6)
                try s.call(Cobol.rtrim(prog))
                continue
            }
            if reply == "a" || reply == "A" || f == 1010 { try call("irs080"); continue }
            if reply != "X" && reply != "x" && f != 2005 { continue }
            break mainLoop
        }
        // eoj
        IRSub2.write(s)
        _ = IRSub2.read(s)
        // not Backup-Script-Found
        throw StopRun()
    }

    static func todayShort(_ s: Session) -> String {
        let d = s.today
        return "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/\(Cobol.z(d.year % 100, 2))"
    }

    static func spoolValid(_ name: String) -> Bool {
        guard let ch = name.first, ch.isASCII else { return false }
        return ch.isLetter || ch.isNumber
    }

    static func moveSystemFilesToDataFiles(_ ctx: IRS.Context, _ st: State) {
        let sf = Array(Cobol.x(ctx.sys.str("system-files"), 49))
        st.dataFiles = String(sf[0..<48])
        st.opSystem = sf[48]
    }

    static func displayMenu1(_ s: Session, _ st: State) {
        let c = s.console
        let sys = IRS.context(s).sys
        c.eraseScreen()
        c.display(Cobol.x(progName, 14), at: 101, color: 2)
        c.display(s.t("irs.menu_title"), at: 131, color: 7, reverse: true)
        c.display(sys.str("run-date"), at: 173, color: 2)
        c.display(s.t("irs.client"), at: 301, color: 2)
        c.display(Cobol.x(sys.str("client"), 29), at: 310, color: 3)
        c.display(s.t("irs.start_date"), at: 339, color: 2)
        c.display(sys.str("start-date"), at: 352, color: 3)
        c.display(s.t("irs.end_date"), at: 362, color: 2)
        c.display(sys.str("end-date"), at: 373, color: 3)
        c.display(s.t("irs.select_function"), at: 501, color: 2)
        c.display("]", at: 535, color: 2)
        c.display(s.t("irs.item_1"), at: 706, color: 2)
        c.display(s.t("irs.item_2"), at: 806, color: 2)
        c.display(s.t("irs.item_3"), at: 906, color: 2)
        c.display(s.t("irs.item_4"), at: 1006, color: 2)
        c.display(s.t("irs.item_5"), at: 1106, color: 2)
        c.display(s.t("irs.item_6"), at: 1206, color: 2)
        c.display(s.t("irs.item_7"), at: 1306, color: 2)
        c.display(s.t("irs.item_8"), at: 1406, color: 2)
        c.display(s.t("irs.item_9"), at: 1506, color: 2)
        c.display(s.t("irs.item_a"), at: 1606, color: 2)
        c.display(s.t("irs.item_x"), at: 2006, color: 2)
        c.display(st.exitToSystem, at: 2016, color: 2)
        c.display(st.batchText, at: 2041, color: 3)
        c.display(s.t("irs.menu_footer"), at: 2301, color: 7, highlight: true)
    }

    // MARK: set-up section

    static func setUp(_ s: Session, _ st: State) throws {
        let c = s.console
        let ctx = IRS.context(s)
        // display Menu-Screen-2
        c.eraseScreen()
        c.display(Cobol.x(progName, 14), at: 101, color: 2)
        c.display(s.t("irs.setup_title"), at: 132, color: 7, reverse: true)
        c.display(ctx.sys.str("run-date"), at: 173, color: 2)
        c.display(s.t("irs.setup_date"), at: 406, color: 2)
        c.display(ctx.sys.str("run-date"), at: 414, color: 6)
        c.display("}", at: 422, color: 2)
        c.display(s.t("irs.setup_password"), at: 446, color: 2)
        c.display("****", at: 459, color: 6)
        c.display("}", at: 463, color: 2)
        // get-run-date
        while true {
            let d = try c.accept(at: 414, size: 8, initial: ctx.sys.str("run-date"), options: [.update], color: 6)
            ctx.sys["run-date"] = d
            if c.crtStatus == 2005 { return }
            let (bin, norm) = dateValidate(d)
            if bin == 0 {
                c.display(s.t("irs.date_error"), at: 424, color: 4)
                continue
            }
            c.display(Cobol.x("", 10), at: 424)
            ctx.sys["run-date"] = norm
            break
        }
        st.wsPass = try c.accept(at: 459, size: 4, options: [.secure])
        if c.crtStatus == 2005 { return }
        if st.wsPass != ctx.sys.str("pass-word") { return }
        c.display(s.t("irs.new"), at: 465, color: 3)
        ctx.sys["pass-word"] = try c.accept(at: 459, size: 4, initial: ctx.sys.str("pass-word"), options: [.update, .secure])
        if c.crtStatus == 2005 { return }
        c.display("    ", at: 465, eraseEOL: true)
        if !st.validOS { st.opSystem = "0" }

        // display / accept Menu-Screen-3
        let sys = ctx.sys
        let labels: [(String, Int)] = [
            ("irs.setup_user", 606), ("irs.setup_vat", 646), ("irs.setup_client_name", 806), ("irs.setup_addr", 920),
            ("irs.setup_period", 1406), ("irs.setup_start", 1420), ("irs.setup_end", 1520),
            ("irs.setup_os", 1702), ("irs.setup_os_list", 1802), ("irs.setup_spool", 2002),
        ]
        for (k, at) in labels { c.display(s.t(k), at: at, color: 2) }
        for at in [638, 663, 852, 952, 1052, 1152, 1252, 1442, 1542, 1724, 2053] { c.display("]", at: at, color: 2) }
        for at in [1027, 1127, 1227] { c.display("[", at: at, color: 2) }
        c.display("- [", at: 1720, color: 2)
        c.display(String(Array(st.exitToSystem)[2..<12]), at: 1726, color: 2)
        c.display(s.t("irs.setup_footer"), at: 2301, color: 7, highlight: true)
        let fUser = ScreenField(line: 6, col: 14, size: 24, value: sys.str("suser"), color: 6)
        let fVat = ScreenField(line: 6, col: 59, size: 4, kind: .numeric, pic: "99v99", value: sys.str("vat"), color: 6)
        let fClient = ScreenField(line: 8, col: 28, size: 24, value: sys.str("client"), color: 6)
        let fA1 = ScreenField(line: 9, col: 28, size: 24, value: sys.str("address-1"), color: 6)
        let fA2 = ScreenField(line: 10, col: 28, size: 24, value: sys.str("address-2"), color: 6)
        let fA3 = ScreenField(line: 11, col: 28, size: 24, value: sys.str("address-3"), color: 6)
        let fA4 = ScreenField(line: 12, col: 28, size: 24, value: sys.str("address-4"), color: 6)
        let fStart = ScreenField(line: 14, col: 34, size: 8, value: sys.str("start-date"), color: 6)
        let fEnd = ScreenField(line: 15, col: 34, size: 8, value: sys.str("end-date"), color: 6)
        let fOS = ScreenField(line: 17, col: 23, size: 1, kind: .numeric, pic: "9", value: String(st.opSystem), color: 6)
        let fSpool = ScreenField(line: 20, col: 21, size: 32, value: sys.str("print-spool-name"), color: 2)
        let fields = [fUser, fVat, fClient, fA1, fA2, fA3, fA4, fStart, fEnd, fOS, fSpool]
        c.displayFields(fields)
        try c.acceptScreen(fields)
        ctx.sys["suser"] = fUser.value
        ctx.sys.setRaw("vat", Array(Cobol.x(fVat.value, 4).utf8))
        ctx.sys["client"] = fClient.value
        ctx.sys["address-1"] = fA1.value
        ctx.sys["address-2"] = fA2.value
        ctx.sys["address-3"] = fA3.value
        ctx.sys["address-4"] = fA4.value
        ctx.sys["start-date"] = fStart.value
        ctx.sys["end-date"] = fEnd.value
        st.opSystem = fOS.value.first ?? "0"
        ctx.sys["print-spool-name"] = fSpool.value

        // get-startd
        while true {
            let (bin, norm) = dateValidate(ctx.sys.str("start-date"))
            if bin == 0 {
                c.display(s.t("irs.date_error"), at: 1444, color: 3)
                ctx.sys["start-date"] = try c.accept(at: 1434, size: 8, initial: ctx.sys.str("start-date"), options: [.update], color: 6)
                continue
            }
            c.display(Cobol.x("", 10), at: 1444)
            ctx.sys["start-date"] = norm
            break
        }
        // get-endd
        while true {
            let (bin, norm) = dateValidate(ctx.sys.str("end-date"))
            if bin == 0 {
                c.display(s.t("irs.date_error"), at: 1544, color: 3)
                ctx.sys["end-date"] = try c.accept(at: 1534, size: 8, initial: ctx.sys.str("end-date"), options: [.update], color: 6)
                continue
            }
            c.display(Cobol.x("", 10), at: 1544)
            ctx.sys["end-date"] = norm
            break
        }
        // get-os
        while !st.validOS {
            c.display(s.t("irs.invalid_option"), at: 1726, color: 3)
            let v = try c.accept(at: 1723, size: 1, kind: .numeric, initial: String(st.opSystem), options: [.update], color: 6)
            st.opSystem = v.first ?? "0"
        }
        let osName = ["1": "DOS", "2": "Windows", "3": "Mac OSX", "4": "OS/2", "5": "Unix", "6": "Linux"][String(st.opSystem)]!
        c.display(osName, at: 1730, color: 3)
        ctx.sys["system-files"] = st.dataFiles + String(st.opSystem)
        ctx.sys["system-work-group"] = ""
        ctx.sys.setInt("pass-value", 0); ctx.sys.setInt("save-sequ", 0); ctx.sys.setInt("first-time-flag", 0)
        if !IRS.isNumeric(ctx.sys.raw("next-post")) { ctx.sys.setInt("next-post", 0) }
        IRSub2.write(s)
        st.wsPass = "    "
        moveSystemFilesToDataFiles(ctx, st)
    }

    // MARK: date-validate section

    /// dd/mm/yy を検証し (u-bin, 区切りを / に置換した u-date) を返す。不正は u-bin = 0。
    static func dateValidate(_ date: String) -> (Int, String) {
        let a = Array(Cobol.x(date, 8).map { ".,-".contains($0) ? Character("/") : $0 })
        let norm = String(a)
        func num(_ i: Int) -> Int? {
            guard a[i].isASCII, a[i].isNumber, a[i + 1].isASCII, a[i + 1].isNumber else { return nil }
            return Int(String(a[i...(i + 1)]))
        }
        guard a.filter({ $0 == "/" }).count == 2, let dd = num(0), let mm = num(3), let yy = num(6),
              (1...31).contains(dd), (1...12).contains(mm) else { return (0, norm) }
        let days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if dd > 29 && mm == 2 { return (0, norm) }
        if dd > days[mm - 1] && mm != 2 { return (0, norm) }
        var work2 = (yy / 4) * 4
        if mm == 2 && dd > 28 && yy != work2 { return (0, norm) }
        var work1 = 1
        work2 = 0
        var bin = 0
        if yy != 0 { bin = yy * 365 }
        while yy > work2 { bin += 1; work2 += 4 }
        if yy == work2 && mm > 2 { bin += 1 }
        while mm > work1 { bin += days[work1 - 1]; work1 += 1 }
        if dd <= days[work1 - 1] { return (bin + dd, norm) }
        if dd == 29 && mm == 2 && yy == work2 { return (bin + dd, norm) }
        return (0, norm)
    }
}
