import Foundation

/// sales/sl010.cbl: Customer File Set-Up & Maintenance (得意先マスタ保守)
enum SLA010 {
    static let progName = "SL010 (3.01.20)"

    final class WS {
        var menuReply = 0
        /// FD のレコード領域は初期状態で NUL (FILLER は INITIALIZE されず NUL のまま書かれる: レガシー実測)
        var rec = Record(SLA.salesLayout, bytes: [UInt8](repeating: 0, count: 300))
        var deliv = Record(SLA.deliveryLayout)
        var escapeCode = " "
        var errorCode = 0
        var customerCode = SLA.spaces(7)
        var saveTag = 0, saveNotesTag = 0
        var printOut = " "
        var d2402 = " ", d2403 = " ", d24check = SLA.spaces(15)
        var lateCharg = " ", dunLetter = " ", emailLet = " ", emailStat = " ", emailInv = " "
        var notes1 = SLA.spaces(48), notes2 = SLA.spaces(48)
        var delivName = SLA.spaces(30), delivAddr1 = SLA.spaces(48), delivAddr2 = SLA.spaces(48)
        var custIn = SLA.spaces(6), statusIn = " "
        var creditIn = 0, creditOp = " ", invoiceIn = 0, invoiceOp = " ", averageIn = 0, averageOp = " "
        var overdueIn = 0, overdueOp = " ", enterDateIn = SLA.spaces(10), enterDateOp = " "
        var wsEnterDate = 0
        var customerIn = SLA.spaces(7)
        var localDate = SLA.spaces(10)
        var a = 0, y = 0, z = 0
        var lineCnt = 0
        var l3report = [Character](repeating: " ", count: 70)
        var l3date = "", l3user = ""
        var sales: IndexedFile!
        var delivery: IndexedFile!
        var printer: SLA.Printer!
        var notes: String { notes1 + notes2 }
        var delivAddress: String { delivAddr1 + delivAddr2 }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let w = WS()
        w.sales = SLA.salesFile(s)
        w.delivery = SLA.deliveryFile(s)
        if s.sys.str("sales-ledger") != "Y" {
            if try !slcreate(s, w) { return }
        }
        while true {
            w.menuReply = 0
            displayHeading(s, w)
            while true {
                c.display(s.t("sl010.select"), at: 701, color: 2)
                c.display(s.t("sl010.opt1"), at: 1004, color: 2)
                c.display(s.t("sl010.opt2"), at: 1204, color: 2)
                c.display(s.t("sl010.opt3"), at: 1404, color: 2)
                c.display(s.t("sl010.opt4"), at: 1604, color: 2)
                c.display(s.t("sl010.opt5"), at: 1804, color: 2)
                c.display(s.t("sl010.opt9"), at: 2104, color: 2)
                let r = try c.accept(at: 743, size: 1, kind: .numeric, options: [.auto], color: 2)
                w.menuReply = Int(Cobol.moveNumeric(r, digits: 1, scale: 0))
                if w.menuReply == 9 { return }
                if w.menuReply >= 1 && w.menuReply <= 5 { break }
            }
            switch w.menuReply {
            case 1: try setupCustomers(s, w)
            case 2: try amendCustomer(s, w)
            case 3: try deleteCustomer(s, w)
            case 4:
                try reportSelection(s, w)
                reportHeadingSetup(s, w)
                produceReport(s, w)
                w.sales.close(); w.delivery.close()
            default: try displayCustomers(s, w)
            }
        }
    }

    // MARK: test-escape

    static func testEscape(_ s: Session, _ w: WS) throws {
        let c = s.console
        c.display(w.escapeCode, at: 2071, color: 6)
        while true {
            w.escapeCode = try c.accept(at: 2071, size: 1, initial: w.escapeCode, options: [.update], color: 6).uppercased()
            if ["B", "S", "Q", "K", "D", "T"].contains(w.escapeCode) { return }
        }
    }

    // MARK: display-heading

    static func displayHeading(_ s: Session, _ w: WS) {
        let c = s.console
        c.display(" ", at: 101, color: 2, eraseEOS: true)
        w.d2402 = " "; w.d24check = SLA.spaces(15); w.d2403 = "]"
        if w.menuReply != 4 {
            c.display(progName, at: 101, color: 2)
            w.localDate = SLA.convertDate(s)
            c.display(w.localDate, at: 171, color: 2)
        }
        switch w.menuReply {
        case 0:
            c.display(s.t("sl010.title"), at: 124, color: 2)
            c.display(s.t("sl010.function_menu"), at: 434, color: 2)
        case 1:
            c.display(s.t("sl010.title_create"), at: 129, color: 2)
            w.d24check = Cobol.x(s.t("sl010.check_digit"), 12) + "{ }"
            w.d2402 = "]"; w.d2403 = " "
        case 2: c.display(s.t("sl010.title_amend"), at: 129, color: 2)
        case 3: c.display(s.t("sl010.title_delete"), at: 129, color: 2)
        case 5: c.display(s.t("sl010.title_display"), at: 129, color: 2)
        default: break
        }
    }

    // MARK: screen display-02

    static let literals02: [(Int, Int, String)] = [
        (4, 1, "sl010.s2.nos"), (6, 1, "sl010.s2.name"), (6, 47, "]"), (7, 10, "sl010.s2.addr"), (7, 65, "]"),
        (8, 16, "["), (8, 65, "]"), (9, 1, "sl010.s2.deliv"), (9, 47, "]"), (10, 10, "sl010.s2.addr"), (10, 65, "]"),
        (11, 16, "["), (11, 65, "]"), (12, 1, "sl010.s2.note"), (12, 65, "]"), (13, 16, "["), (13, 65, "]"),
        (14, 1, "sl010.s2.phone"), (14, 30, "]"), (14, 32, "sl010.s2.ext"), (14, 42, "]"), (14, 45, "sl010.s2.fax"), (14, 65, "]"),
        (15, 1, "sl010.s2.email"), (15, 47, "]"), (16, 1, "sl010.s2.late"), (16, 18, "]"), (16, 26, "sl010.s2.minbal"), (16, 68, "]"),
        (17, 1, "sl010.s2.letters"), (17, 18, "]"), (17, 26, "sl010.s2.maxlate"), (17, 61, ": ["), (17, 68, "]"),
        (18, 1, "sl010.s2.credit"), (18, 19, "]"), (18, 26, "sl010.s2.einv"), (18, 38, "]"), (18, 40, "sl010.s2.estat"), (18, 48, "]"),
        (18, 50, "sl010.s2.edun"), (18, 58, "]"), (19, 1, "sl010.s2.limit"), (19, 24, "sl010.s2.discount"), (19, 43, "]"),
        (19, 56, "*******************"), (20, 1, "sl010.s2.unapplied"), (20, 29, "}"), (20, 56, "sl010.s2.escape"), (20, 72, "] *"),
        (21, 1, "sl010.s2.current"), (21, 29, "}"), (21, 56, "sl010.s2.back"), (22, 1, "sl010.s2.lastinv"), (22, 27, "}"),
        (22, 56, "sl010.s2.save"), (23, 1, "sl010.s2.lastpay"), (23, 27, "}"), (23, 56, "sl010.s2.quit"), (24, 56, "*******************"),
    ]

    static func fields02(_ w: WS) -> [ScreenField] {
        let r = w.rec
        func f(_ l: Int, _ c: Int, _ n: Int, _ v: String) -> ScreenField { ScreenField(line: l, col: c, size: n, value: v, color: 2) }
        func n(_ l: Int, _ c: Int, _ pic: String, _ v: Int64, _ scale: Int = 0) -> ScreenField {
            ScreenField(line: l, col: c, size: Pic.size(pic), kind: .numeric, pic: pic, value: Pic.edit(pic, value: v, scale: scale), color: 2)
        }
        return [
            f(6, 17, 30, r.str("sales-name")), f(7, 17, 48, r.str("sales-addr1")), f(8, 17, 48, r.str("sales-addr2")),
            f(9, 17, 30, w.delivName), f(10, 17, 48, w.delivAddr1), f(11, 17, 48, w.delivAddr2),
            f(12, 17, 48, w.notes1), f(13, 17, 48, w.notes2),
            f(14, 17, 13, r.str("sales-phone")), f(14, 38, 4, r.str("sales-ext")), f(14, 52, 13, r.str("sales-fax")),
            f(15, 17, 30, r.str("sales-email")),
            f(16, 17, 1, w.lateCharg), n(16, 64, "9(4)", r.int("sales-late-min")),
            f(17, 17, 1, w.dunLetter), n(17, 64, "9(4)", r.int("sales-late-max")),
            n(18, 17, "99", r.int("sales-credit")), f(18, 37, 1, w.emailInv), f(18, 47, 1, w.emailStat), f(18, 57, 1, w.emailLet),
            n(19, 17, "9(7)", r.int("sales-limit")), n(19, 38, "99.99", r.int("sales-discount"), 2),
        ]
    }

    static func display02(_ s: Session, _ w: WS, accept: Bool = false) throws {
        let c = s.console
        for (l, col, k) in literals02 { c.display(k.hasPrefix("sl010.") ? s.t(k) : k, at: l, col, color: 2) }
        c.display(w.d2402, at: 4, 23, color: 2)
        c.display(w.d2403, at: 4, 24, color: 2)
        c.display(Cobol.x(w.d24check, 15), at: 4, 26, color: 2)
        let fs = fields02(w)
        c.displayFields(fs)
        guard accept else { return }
        try c.acceptScreen(fs)
        let v = fs.map { $0.value }
        w.rec["sales-name"] = v[0]; w.rec["sales-addr1"] = v[1]; w.rec["sales-addr2"] = v[2]
        w.delivName = v[3]; w.delivAddr1 = v[4]; w.delivAddr2 = v[5]
        w.notes1 = v[6]; w.notes2 = v[7]
        w.rec["sales-phone"] = v[8]; w.rec["sales-ext"] = v[9]; w.rec["sales-fax"] = v[10]; w.rec["sales-email"] = v[11]
        w.lateCharg = v[12]; w.rec.setInt("sales-late-min", Cobol.moveNumeric(v[13], digits: 4, scale: 0))
        w.dunLetter = v[14]; w.rec.setInt("sales-late-max", Cobol.moveNumeric(v[15], digits: 4, scale: 0))
        w.rec.setInt("sales-credit", Cobol.moveNumeric(v[16], digits: 2, scale: 0))
        w.emailInv = v[17]; w.emailStat = v[18]; w.emailLet = v[19]
        w.rec.setInt("sales-limit", Cobol.moveNumeric(v[20], digits: 7, scale: 0))
        w.rec.setInt("sales-discount", Cobol.moveNumeric(v[21], digits: 4, scale: 2))
    }

    // MARK: customer-display

    static func customerDisplay(_ s: Session, _ w: WS) throws {
        let c = s.console
        func yn(_ f: String) -> String { w.rec.int(f) == 1 ? "Y" : "N" }
        w.lateCharg = yn("sales-late"); w.dunLetter = yn("sales-dunning")
        w.emailInv = yn("email-invoice"); w.emailStat = yn("email-statement"); w.emailLet = yn("email-letters")
        let k7 = String(Array(w.rec.str("sales-key"))[6])
        if w.menuReply == 1 {
            w.d24check = Cobol.x(s.t("sl010.check_digit"), 12) + "{" + k7 + "}"
        } else { w.d2402 = k7 }
        try display02(s, w)
        if w.menuReply == 1 || w.menuReply == 2 { return }
        c.display(Pic.edit("-(8)9.99", value: w.rec.int("sales-unapplied"), scale: 2), at: 2017, color: 2)
        c.display(Pic.edit("-(8)9.99", value: w.rec.int("sales-current"), scale: 2), at: 2117, color: 2)
        if w.rec.int("sales-last-inv") != 0 { c.display(SLA.convertBin(s, w.rec.int("sales-last-inv")), at: 2217, color: 2) }
        if w.rec.int("sales-last-pay") != 0 { c.display(SLA.convertBin(s, w.rec.int("sales-last-pay")), at: 2317, color: 2) }
    }

    // MARK: display-outline

    static func displayOutline(_ s: Session, _ w: WS) throws {
        displayHeading(s, w)
        SLA.initialize(&w.rec); SLA.initialize(&w.deliv)
        w.lateCharg = " "; w.dunLetter = " "; w.emailLet = " "; w.emailStat = " "; w.emailInv = " "
        w.delivName = SLA.spaces(30); w.delivAddr1 = SLA.spaces(48); w.delivAddr2 = SLA.spaces(48)
        w.notes1 = SLA.spaces(48); w.notes2 = SLA.spaces(48)
        try display02(s, w)
    }

    // MARK: customer-data

    static func delivKey(_ type: String, _ key: String) -> [UInt8] { SJIS.encode(type + Cobol.x(key, 7), size: 8) }

    static func customerData(_ s: Session, _ w: WS) throws {
        let c = s.console
        while true {
            var errorFlag = 0
            try display02(s, w, accept: true)
            if validateAddress(s, w.rec.str("sales-addr1") + w.rec.str("sales-addr2")) {
                c.display(" ", at: 766, eraseEOL: true)
            } else {
                c.display(s.t("sl010.sl101"), at: 766, color: 4); errorFlag = 1
            }
            let key = w.rec.str("sales-key")
            let delivBlank = w.delivName.allSatisfy { $0 == " " } && w.delivAddress.allSatisfy { $0 == " " }
            if delivBlank && w.rec.int("delivery-tag") != 0 {
                w.deliv["deliv-sales-key"] = key; w.deliv["deliv-key-type"] = "D"
                if w.delivery.delete(key: delivKey("D", key)) != "00" { w.rec.setInt("delivery-tag", 0) }
            }
            if delivBlank {
                w.rec.setInt("delivery-tag", 0)
            } else {
                if validateAddress(s, w.delivAddress) {
                    c.display(" ", at: 1066, eraseEOL: true)
                } else {
                    c.display(s.t("sl010.sl101"), at: 1066, color: 4); errorFlag = 1
                }
                if !w.delivAddress.allSatisfy({ $0 == " " }) { w.rec.setInt("delivery-tag", 1) }
            }
            let notesBlank = w.notes.allSatisfy { $0 == " " }
            if notesBlank && w.rec.int("notes-tag") != 0 {
                w.deliv["deliv-sales-key"] = key; w.deliv["deliv-key-type"] = "N"
                if w.delivery.delete(key: delivKey("N", key)) != "00" { w.rec.setInt("notes-tag", 0) }
            }
            w.rec.setInt("notes-tag", notesBlank ? 0 : 1)
            if try validateResponse(s, w, w.lateCharg) {
                w.rec.setInt("sales-late", Int64(w.z)); c.display(SLA.spaces(7), at: 1619)
            } else { errorFlag = 1; c.display(s.t("sl010.sl102"), at: 1619, color: 4) }
            if try validateResponse(s, w, w.dunLetter) {
                c.display(SLA.spaces(7), at: 1719); w.rec.setInt("sales-dunning", Int64(w.z))
            } else { errorFlag = 1; c.display(s.t("sl010.sl102"), at: 1719, color: 4) }
            if try validateResponse(s, w, w.emailInv) {
                c.display(" ", at: 1839); w.rec.setInt("email-invoice", Int64(w.z))
            } else { errorFlag = 1; c.display("*", at: 1839, color: 4) }
            if try validateResponse(s, w, w.emailStat) {
                c.display(" ", at: 1849); w.rec.setInt("email-statement", Int64(w.z))
            } else { errorFlag = 1; c.display("*", at: 1849, color: 4) }
            if try validateResponse(s, w, w.emailLet) {
                c.display(" ", at: 1859); w.rec.setInt("email-letters", Int64(w.z))
            } else { errorFlag = 1; c.display("*", at: 1859, color: 4) }
            if errorFlag == 0 { return }
        }
    }

    static func validateAddress(_ s: Session, _ address: String) -> Bool {
        let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
        let a = Array(Cobol.x(address, 96))
        let n = a.filter { $0 == delim }.count
        var truth = !(n > 4 || n < 1)
        let before = a.firstIndex(of: delim) ?? a.count
        if before > 30 { truth = false }
        return truth
    }

    static func validateResponse(_ s: Session, _ w: WS, _ reply: String) throws -> Bool {
        let c = s.console
        switch reply.uppercased() {
        case "Y": w.z = 1
        case "N": w.z = 0
        default:
            try SLA.maps99(s, 18)
            try SLA.maps99(s, 15)
            _ = try c.accept(at: 2479, size: 1)
            return false
        }
        c.display(" ", at: 24, 1, eraseEOL: true)
        return true
    }

    // MARK: accept-key

    static func acceptKey(_ s: Session, _ w: WS) throws {
        let c = s.console
        w.rec["sales-key"] = try c.accept(at: 417, size: 7, color: 3).uppercased()
        w.errorCode = 0
        if w.rec.str("sales-key").allSatisfy({ $0 == " " }) { w.errorCode = 999; return }
        w.saveTag = 0; w.saveNotesTag = 0
        guard let r = w.sales.read(key: w.rec.str("sales-key")) else {
            w.errorCode = 3
            try SLA.maps99(s, 3)
            w.customerCode = SLA.spaces(7)
            return
        }
        w.rec = r
        c.display(" ", at: 23, 1, eraseEOL: true)
        w.customerCode = r.str("sales-key")
        if r.int("delivery-tag") != 0 {
            w.deliv["deliv-sales-key"] = w.customerCode; w.deliv["deliv-key-type"] = "D"
            if let d = w.delivery.read(key: delivKey("D", w.customerCode)) {
                w.deliv = d
                w.delivName = d.str("deliv-name"); w.delivAddr1 = d.str("deliv-addr1"); w.delivAddr2 = d.str("deliv-addr2")
                w.saveTag = 1; w.rec.setInt("delivery-tag", 1)
            } else {
                w.rec.setInt("delivery-tag", 0)
                w.delivName = Cobol.x("record not found", 30); w.delivAddr1 = SLA.spaces(48); w.delivAddr2 = SLA.spaces(48)
            }
        }
        if w.rec.int("notes-tag") != 0 {
            w.deliv["deliv-sales-key"] = w.customerCode; w.deliv["deliv-key-type"] = "N"
            if let d = w.delivery.read(key: delivKey("N", w.customerCode)) {
                w.deliv = d
                w.notes1 = d.str("deliv-addr1"); w.notes2 = d.str("deliv-addr2")
                w.saveNotesTag = 1; w.rec.setInt("notes-tag", 1)
            } else {
                w.rec.setInt("notes-tag", 0)
                w.notes1 = Cobol.x("Record Not Found", 48); w.notes2 = SLA.spaces(48)
            }
        }
    }

    static func openIO(_ w: WS) {
        _ = w.sales.open()
        if w.delivery.open() != "00" {
            w.delivery.close(); w.delivery.openOutput(); w.delivery.close(); _ = w.delivery.open()
        }
    }

    static func setDeliv(_ w: WS, _ type: String, _ name: String, _ a1: String, _ a2: String) {
        w.deliv["deliv-key-type"] = type; w.deliv["deliv-sales-key"] = w.rec.str("sales-key")
        w.deliv["deliv-name"] = name; w.deliv["deliv-addr1"] = a1; w.deliv["deliv-addr2"] = a2
    }

    // MARK: setup-customers

    static func setupCustomers(_ s: Session, _ w: WS) throws {
        let c = s.console
        openIO(w)
        defer { w.sales.close(); w.delivery.close() }
        input: while true {
            w.notes1 = SLA.spaces(48); w.notes2 = SLA.spaces(48)
            try displayOutline(s, w)
            var check = 0
            while true {
                var nos = try c.accept(at: 417, size: 6, color: 3)
                if nos.allSatisfy({ $0 == " " }) { return }
                nos = Cobol.x(nos.uppercased(), 6)
                c.display(nos, at: 417, color: 3)
                c.display(" ", at: 23, 1, eraseEOL: true)
                guard let d = Maps09.checkDigit(nos) else { w.customerCode = nos + String(Array(w.customerCode)[6]); continue }
                check = d
                w.customerCode = nos + String(d)
                w.rec["sales-key"] = w.customerCode
                if let r = w.sales.read(key: w.customerCode) {
                    w.rec = r
                    try SLA.maps99(s, 5)
                    try customerDisplay(s, w)
                    continue
                }
                break
            }
            if w.menuReply == 1 { c.display(String(check), at: 439, color: 3) }
            c.display(SLA.spaces(30), at: 2101)
            c.display(SLA.spaces(30), at: 2201)
            c.display(SLA.spaces(30), at: 2301)
            SLA.initialize(&w.rec); SLA.initialize(&w.deliv)
            w.rec["sales-key"] = w.customerCode
            w.rec.setInt("sales-late", s.sys.int("sl-charges"))
            w.rec.setInt("sales-dunning", s.sys.int("sl-dunning"))
            w.rec.setInt("sales-credit", Cobol.truncate(s.sys.int("sl-credit"), digits: 2, signed: false))
            w.rec.setInt("sales-discount", s.sys.int("sl-disc"))
            w.rec.setInt("sales-late-min", s.sys.int("sl-min"))
            w.rec.setInt("sales-late-max", s.sys.int("sl-max"))
            w.rec.setInt("sales-limit", s.sys.int("sl-limit"))
            w.rec.setInt("sales-create-date", s.sys.int("run-date"))
            w.rec.setInt("sales-status", 1)
            repeat {
                try customerDisplay(s, w)
                try customerData(s, w)
                w.escapeCode = "S"
                try testEscape(s, w)
            } while w.escapeCode == "B"
            if w.escapeCode == "Q" { return }
            _ = w.sales.write(w.rec)
            if w.rec.int("delivery-tag") != 0 {
                setDeliv(w, "D", w.delivName, w.delivAddr1, w.delivAddr2)
                _ = w.delivery.write(w.deliv)
            }
            if w.rec.int("notes-tag") != 0 {
                setDeliv(w, "N", SLA.spaces(30), w.notes1, w.notes2)
                _ = w.delivery.write(w.deliv)
            }
            SLA.initialize(&w.rec); SLA.initialize(&w.deliv)
        }
    }

    // MARK: amend-customer

    /// INVALID KEY 時のデバッグ表示 (レガシーに残っているもの)
    static func debugMsg(_ s: Session, _ what: String, _ status: String, positioned: Bool) throws {
        let c = s.console
        c.display(what, at: 23, 1)
        if positioned { c.display(status, at: 23, 20) } else { c.display(status, at: c.term.cursorLine, c.term.cursorCol) }
        c.display(Cobol.x(evaluateMessage(status), 25), at: 23, 23)
        c.display("Note and hit return", at: 24, 1)
        _ = try c.accept(at: 24, 20, size: 1)
        c.display(" ", at: 23, 1, eraseEOS: true)
    }

    static func evaluateMessage(_ status: String) -> String {
        let m: [String: String] = [
            "00": "Success", "02": "Success Duplicate", "04": "Success Incomplete", "05": "Success Optional",
            "07": "Success No Unit", "10": "End Of File", "14": "Out Of Key Range", "21": "Key Invalid",
            "22": "Key Exists", "23": "Key Not Exists", "30": "Permanent Error", "31": "Inconsistent Filename",
            "34": "Boundary Violation", "35": "File Not Found", "37": "Permission Denied", "38": "Closed With Lock",
            "39": "Conflict Attribute", "41": "Already Open", "42": "Not Open", "43": "Read Not Done",
            "44": "Record Overflow", "46": "Read Error", "47": "Input Denied", "48": "Output Denied",
            "49": "I/O Denied", "51": "Record Locked", "52": "End-Of-Page", "57": "I/O Linage",
            "61": "File Sharing Failure", "91": "File Not Available",
        ]
        return m[status] ?? ""
    }

    static func amendCustomer(_ s: Session, _ w: WS) throws {
        openIO(w)
        defer { w.sales.close(); w.delivery.close() }
        while true {
            try displayOutline(s, w)
            repeat {
                try acceptKey(s, w)
                if w.errorCode == 999 { return }
            } while w.customerCode.allSatisfy { $0 == " " }
            w.saveTag = Int(w.rec.int("delivery-tag"))
            w.saveNotesTag = Int(w.rec.int("notes-tag"))
            if w.rec.int("email-invoice") != 0 && w.rec.int("email-invoice") != 1 {
                w.rec.setInt("email-invoice", 0); w.rec.setInt("email-statement", 0); w.rec.setInt("email-letters", 0)
            }
            repeat {
                try customerDisplay(s, w)
                try customerData(s, w)
                w.escapeCode = "S"
                try testEscape(s, w)
            } while w.escapeCode == "B"
            if w.escapeCode == "Q" { continue }
            let key = w.rec.str("sales-key")
            setDeliv(w, "D", w.delivName, w.delivAddr1, w.delivAddr2)
            if w.rec.int("delivery-tag") != 0 && w.saveTag == 0 {
                let st = w.delivery.write(w.deliv)
                if st != "00" {
                    try debugMsg(s, "write deliverytag ", st, positioned: true)
                    _ = w.delivery.rewrite(w.deliv)
                }
            } else if w.rec.int("delivery-tag") != 0 {
                let st = w.delivery.rewrite(w.deliv)
                if st != "00" { try debugMsg(s, "rewrite deliverytag ", st, positioned: true) }
            }
            if w.rec.int("delivery-tag") == 0 && w.saveTag != 0 {
                let st = w.delivery.delete(key: delivKey("D", key))
                if st != "00" { try debugMsg(s, "Delete deliverytag ", st, positioned: true) }
            }
            setDeliv(w, "N", SLA.spaces(30), w.notes1, w.notes2)
            if w.rec.int("notes-tag") != 0 && w.saveNotesTag == 0 {
                let st = w.delivery.write(w.deliv)
                if st != "00" { try debugMsg(s, "write notes tag ", st, positioned: true) }
            } else if w.rec.int("notes-tag") != 0 {
                let st = w.delivery.rewrite(w.deliv)
                if st != "00" { try debugMsg(s, "Rewrite notes tag ", st, positioned: false) }
            }
            if w.rec.int("notes-tag") == 0 && w.saveNotesTag != 0 {
                let st = w.delivery.delete(key: delivKey("N", key))
                if st != "00" { try debugMsg(s, "Delete notes tag ", st, positioned: false) }
            }
            let st = w.sales.rewrite(w.rec)
            if st != "00" { try debugMsg(s, "Rewrite Sales Rec ", st, positioned: false) }
        }
    }

    // MARK: delete-customer

    static func deleteCustomer(_ s: Session, _ w: WS) throws {
        let c = s.console
        _ = w.sales.open(); _ = w.delivery.open()
        defer { w.sales.close(); w.delivery.close() }
        while true {
            try displayOutline(s, w)
            c.display(s.t("sl010.dormant"), at: 2159, color: 2)
            c.display(s.t("sl010.kill"), at: 2259, color: 2)
            while true {
                try acceptKey(s, w)
                if w.errorCode == 999 { return }
                if w.customerCode.allSatisfy({ $0 == " " }) { continue }
                try customerDisplay(s, w)
                w.escapeCode = "K"
                try testEscape(s, w)
                if w.escapeCode == "Q" { return }
                if w.rec.int("sales-current") != 0 || w.rec.int("sales-unapplied") != 0 {
                    c.display(s.t("sl010.sl109"), at: 501, color: 4)
                    continue
                }
                break
            }
            c.display(" ", at: 501, eraseEOL: true)
            if w.escapeCode == "D" {
                w.rec.setInt("sales-status", 0)
                _ = w.sales.rewrite(w.rec)
            }
            if w.escapeCode != "K" { continue }
            let key = w.rec.str("sales-key")
            _ = w.delivery.delete(key: delivKey("D", key))
            _ = w.delivery.delete(key: delivKey("N", key))
            _ = w.sales.delete(key: SJIS.encode(key, size: 7))
            return
        }
    }

    // MARK: display-customers

    static func displayCustomers(_ s: Session, _ w: WS) throws {
        _ = w.delivery.open(); _ = w.sales.open()
        defer { w.sales.close(); w.delivery.close() }
        while true {
            try displayOutline(s, w)
            repeat {
                try acceptKey(s, w)
                if w.errorCode == 999 { return }
            } while w.customerCode.allSatisfy { $0 == " " }
            try customerDisplay(s, w)
            w.escapeCode = "S"
            try testEscape(s, w)
            if w.escapeCode == "T" {
                w.rec.setInt("sales-unapplied", try acceptMoney9c(s, 20, 17, w.rec.int("sales-unapplied")))
                w.rec.setInt("sales-current", try acceptMoney9c(s, 21, 17, w.rec.int("sales-current")))
                _ = w.sales.rewrite(w.rec)
            }
            if w.escapeCode == "Q" { return }
        }
    }

    /// zz030-accept-money9c: 9(9).99 を表示して上書き入力させる (符号なし)。結果は s9(8)v99 へ。
    static func acceptMoney9c(_ s: Session, _ lin: Int, _ col: Int, _ value: Int64) throws -> Int64 {
        let c = s.console
        let v = abs(value)
        let shown = Cobol.z(v / 100, 9) + "." + Cobol.z(v % 100, 2)
        c.display(shown, at: lin, col, color: 3)
        let r = Array(Cobol.x(try c.accept(at: lin, col, size: 12, initial: shown, options: [.update], color: 3), 12))
        func digits(_ a: ArraySlice<Character>) -> Int64 {
            a.reduce(Int64(0)) { $0 * 10 + Int64(($1.asciiValue ?? 0x30) & 0x0f) % 10 }
        }
        let amt = digits(r[0..<9]) * 100 + digits(r[10..<12])
        return amt % 10_000_000_000
    }

    // MARK: report-selection (screen display-03)

    static let literals03: [(Int, Int, String)] = [
        (1, 34, "sl010.s3.title"), (3, 32, "sl010.s3.attributes"),
        (8, 3, "sl010.s3.number"), (8, 28, "]"), (8, 33, "sl010.s3.number_help"),
        (10, 3, "sl010.s3.status"), (10, 23, "]"), (10, 33, "sl010.s3.status_help"),
        (12, 3, "sl010.s3.credit"), (12, 24, "]  ["), (12, 29, "]"), (12, 33, "sl010.s3.credit_help"),
        (13, 37, "sl010.s3.credit_l"), (14, 37, "sl010.s3.credit_g"), (15, 37, "sl010.s3.credit_e"),
        (17, 3, "sl010.s3.invoice"), (17, 27, "] ["), (17, 31, "]"), (17, 33, "sl010.s3.invoice_help"),
        (19, 3, "sl010.s3.average"), (19, 27, "] ["), (19, 31, "]"), (19, 33, "sl010.s3.average_help"),
        (21, 3, "sl010.s3.overdue"), (21, 27, "] ["), (21, 31, "]"), (21, 33, "sl010.s3.overdue_help"),
        (23, 3, "sl010.s3.date"), (23, 27, "] ["), (23, 31, "]"), (23, 33, "sl010.s3.date_help"),
    ]

    static func reportSelection(_ s: Session, _ w: WS) throws {
        let c = s.console
        _ = w.sales.open(); _ = w.delivery.open()
        w.custIn = SLA.spaces(6); w.statusIn = " "; w.creditOp = " "; w.invoiceOp = " "; w.averageOp = " "
        w.overdueOp = " "; w.enterDateOp = " "; w.enterDateIn = SLA.spaces(10); w.printOut = " "
        w.creditIn = 0; w.invoiceIn = 0; w.averageIn = 0; w.overdueIn = 0; w.wsEnterDate = 0
        func f(_ l: Int, _ col: Int, _ n: Int, _ v: String) -> ScreenField { ScreenField(line: l, col: col, size: n, value: v, color: 2) }
        func n(_ l: Int, _ col: Int, _ pic: String, _ v: Int) -> ScreenField {
            ScreenField(line: l, col: col, size: Pic.size(pic), kind: .numeric, pic: pic, value: Pic.edit(pic, value: Int64(v), scale: 0), color: 2)
        }
        func fields() -> [ScreenField] {
            [f(8, 22, 6, w.custIn), f(10, 22, 1, w.statusIn), n(12, 22, "99", w.creditIn), f(12, 28, 1, w.creditOp),
             n(17, 22, "9(5)", w.invoiceIn), f(17, 30, 1, w.invoiceOp), n(19, 22, "9(5)", w.averageIn), f(19, 30, 1, w.averageOp),
             n(21, 22, "9(5)", w.overdueIn), f(21, 30, 1, w.overdueOp), f(23, 17, 10, w.enterDateIn), f(23, 30, 1, w.enterDateOp)]
        }
        c.eraseScreen()
        c.display(progName, at: 1, 1, color: 2)
        c.display(w.localDate, at: 1, 71, color: 2)
        for (l, col, k) in literals03 { c.display(k.hasPrefix("sl010.") ? s.t(k) : k, at: l, col, color: 2) }
        c.displayFields(fields())
        while true {
            let fs = fields()
            try c.acceptScreen(fs)
            let v = fs.map { $0.value }
            func num(_ x: String, _ d: Int) -> Int { Int(Cobol.moveNumeric(x, digits: d, scale: 0)) }
            w.custIn = v[0].uppercased(); w.customerIn = Cobol.x(w.custIn, 7)
            w.statusIn = v[1].uppercased(); w.creditIn = num(v[2], 2); w.creditOp = v[3]
            w.invoiceIn = num(v[4], 5); w.invoiceOp = v[5]; w.averageIn = num(v[6], 5); w.averageOp = v[7]
            w.overdueIn = num(v[8], 5); w.overdueOp = v[9]; w.enterDateIn = v[10]; w.enterDateOp = v[11]
            if !["L", "D", " "].contains(w.statusIn) { continue }
            let ok = ["L", "G", "E", " "]
            w.creditOp = w.creditOp.uppercased(); if !ok.contains(w.creditOp) { continue }
            w.invoiceOp = w.invoiceOp.uppercased(); if !ok.contains(w.invoiceOp) { continue }
            w.averageOp = w.averageOp.uppercased(); if !ok.contains(w.averageOp) { continue }
            w.overdueOp = w.overdueOp.uppercased(); if !ok.contains(w.overdueOp) { continue }
            w.enterDateOp = w.enterDateOp.uppercased(); if !ok.contains(w.enterDateOp) { continue }
            if w.enterDateIn.allSatisfy({ $0 == " " }) { return }
            let bin = SLA.validateDate(s, w.enterDateIn)
            if bin == 0 {
                c.display(s.t("sl010.sl005"), at: 2362, color: 4)
                continue
            }
            c.display(" ", at: 2362, eraseEOL: true)
            w.wsEnterDate = bin
            return
        }
    }

    // MARK: report-heading-setup

    static func reportHeadingSetup(_ s: Session, _ w: WS) {
        w.l3date = SLA.convertDate(s)
        w.l3user = s.sys.str("usera")
        w.y = (w.y + 1) % 100
        w.l3report = [Character](repeating: " ", count: 70)
        func put(_ t: String) { SLA.string(t, into: &w.l3report, pointer: &w.y) }
        func bump() { w.y = (w.y + 1) % 100 }
        let blank = w.statusIn == " " && w.creditOp == " " && w.invoiceOp == " " && w.averageOp == " "
            && w.overdueOp == " " && w.customerIn.allSatisfy { $0 == " " }
        put(s.l10n.raw(blank ? "report.sl010.all" : "report.sl010.matched"))
        bump()
        if w.statusIn == "L" { put(s.l10n.raw("report.sl010.live")) }
        if w.statusIn == "D" { put(s.l10n.raw("report.sl010.dormant")) }
        bump()
        func operand(_ op: String) -> String { op == "L" ? "< " : (op == "G" ? "> " : (op == "E" ? "= " : "  ")) }
        if w.creditOp != " " { put(operand(w.creditOp) + Pic.edit("z9", value: Int64(w.creditIn), scale: 0) + Cobol.x(s.l10n.raw("report.sl010.days_credit"), 12)) }
        bump()
        if w.invoiceOp != " " { put(operand(w.invoiceOp) + Pic.edit("zzzz9", value: Int64(w.invoiceIn), scale: 0) + Cobol.x(s.l10n.raw("report.sl010.invoices"), 9)) }
        bump()
        if w.averageOp != " " { put(operand(w.averageOp) + Pic.edit("zzzz9", value: Int64(w.averageIn), scale: 0) + Cobol.x(s.l10n.raw("report.sl010.av_value"), 10)) }
        bump()
        if w.overdueOp != " " { put(operand(w.overdueOp) + Pic.edit("zzzz9", value: Int64(w.overdueIn), scale: 0) + Cobol.x(s.l10n.raw("report.sl010.days_overdue"), 13)) }
        bump()
        if w.enterDateOp != " " { put(operand(w.enterDateOp) + Cobol.x(w.enterDateIn, 10) + Cobol.x(s.l10n.raw("report.sl010.entry_date"), 11)) }
        bump()
        if !w.customerIn.allSatisfy({ $0 == " " }) { put(s.l10n.raw("report.sl010.keys_matching") + w.customerIn) }
    }

    // MARK: produce-report

    static func produceReport(_ s: Session, _ w: WS) {
        let p = SLA.Printer(s)
        w.printer = p
        p.open()
        w.a = 0
        headings(s, w)
        if !w.customerIn.allSatisfy({ $0 == " " }) {
            if !w.sales.start(notLessThan: SJIS.encode(w.customerIn, size: 7)) { w.a = 1 }
            w.customerIn = w.customerIn.replacingOccurrences(of: " ", with: "Z")
        }
        while let r = w.sales.readNext() {
            w.rec = r
            let live = r.int("sales-status") == 1, dead = r.int("sales-status") == 0
            if w.statusIn == "L" && dead { continue }
            if w.statusIn == "D" && live { continue }
            if !w.customerIn.allSatisfy({ $0 == " " }) && r.str("sales-key") > w.customerIn { break }
            if w.creditOp != " " && !testNum(w.creditOp, Int64(w.creditIn), r.int("sales-credit")) { continue }
            if w.invoiceOp != " " && !testNum(w.invoiceOp, Int64(w.invoiceIn), r.int("sales-activety")) { continue }
            if w.averageOp != " " && !testNum(w.averageOp, Int64(w.averageIn), r.int("sales-average")) { continue }
            if w.overdueOp != " " && r.int("sales-current") > 0
                && !testNum(w.overdueOp, Int64(w.overdueIn), s.sys.int("run-date") - r.int("sales-last-inv")) { continue }
            if w.enterDateOp != " " && !testNum(w.enterDateOp, Int64(w.wsEnterDate), r.int("sales-create-date")) { continue }
            listing(s, w)
        }
        p.close(spool: w.printOut == "Y")
    }

    static func testNum(_ op: String, _ test1: Int64, _ test2: Int64) -> Bool {
        switch op {
        case " ": return true
        case "L": return test2 < test1
        case "G": return test2 > test1
        case "E": return test2 == test1
        default: return false
        }
    }

    static func headings(_ s: Session, _ w: WS) {
        let p = w.printer!
        w.a = (w.a + 1) % 1000
        let line1 = Cobol.x(progName, 57) + Cobol.x(s.l10n.raw("report.sl010.title"), 67) + Cobol.x(s.l10n.raw("report.sl010.page"), 5)
            + Pic.edit("zz9", value: Int64(w.a), scale: 0)
        let line3 = Cobol.x(w.l3user, 40) + Cobol.x(s.l10n.raw("report.sl010.report_on"), 12) + String(w.l3report) + Cobol.x(w.l3date, 10)
        if w.a != 1 {
            p.afterPage(line1)
            p.after(1, line3)
            p.after(1, "")
        } else {
            p.before(1, line1)
            p.before(1, line3)
        }
        p.after(1, Cobol.x(s.l10n.raw("report.sl010.cols1"), 127) + Cobol.x(s.l10n.raw("report.sl010.cols1_disc"), 5))
        p.after(1, " " + Cobol.x(s.l10n.raw("report.sl010.cols2"), 103) + Cobol.x(s.l10n.raw("report.sl010.cols2_right"), 28))
        p.after(1, "")
        w.lineCnt = 6
    }

    static func line6(_ key: String, _ status: String, _ name: String, _ phone: String, _ fax: String,
                      _ charges: String, _ letter: String, _ limit: Int64, _ credit: Int64, _ discount: Int64) -> String {
        var l = Cobol.x(key, 10) + Cobol.x(status, 10) + Cobol.x(name, 50) + Cobol.x(phone, 18) + Cobol.x(fax, 13)
        l += SLA.spaces(4) + Cobol.x(charges, 1) + SLA.spaces(4) + Cobol.x(letter, 1) + "  "
        l += limit == 0 ? SLA.spaces(7) : Pic.edit("z(6)9", value: limit, scale: 0)
        l += credit == 0 ? SLA.spaces(7) : Pic.edit("zzz9", value: credit, scale: 0) + "   "
        l += discount == 0 ? SLA.spaces(5) : Pic.edit("z9.99", value: discount, scale: 2)
        return l
    }

    static func listing(_ s: Session, _ w: WS) {
        let p = w.printer!
        let r = w.rec
        let pageLines = Int(s.sys.int("page-lines"))
        let delim = s.sys.str("sl-delim")
        if w.lineCnt > pageLines { headings(s, w) }
        let status = s.l10n.raw(r.int("sales-status") == 1 ? "report.sl010.active" : "report.sl010.dormant_status")
        var address = r.str("sales-addr1") + r.str("sales-addr2")
        address = address.replacingOccurrences(of: delim, with: ",")
        var phone = [Character](repeating: " ", count: 18)
        if r.str("sales-ext").allSatisfy({ $0 == " " }) {
            phone = Array(Cobol.x(r.str("sales-phone"), 18))
        } else {
            w.y = 1
            SLA.string(SLA.delimited(r.str("sales-phone")), into: &phone, pointer: &w.y)
            w.y -= 1
            SLA.string("x" + r.str("sales-ext"), into: &phone, pointer: &w.y)
        }
        if w.lineCnt > pageLines - 5 { headings(s, w) }
        p.after(1, line6(r.str("sales-key"), status, r.str("sales-name"), String(phone), r.str("sales-fax"),
                         r.int("sales-late") == 1 ? "Y" : " ", r.int("sales-dunning") == 1 ? "Y" : " ",
                         r.int("sales-limit"), r.int("sales-credit"), r.int("sales-discount")))
        p.after(1, SLA.spaces(20) + Cobol.x(address, 112))
        let key = r.str("sales-key")
        if r.int("delivery-tag") > 0 {
            var name: String, addr: String
            if let d = w.delivery.read(key: delivKey("D", key)) {
                w.deliv = d
                name = d.str("deliv-name"); addr = d.str("deliv-addr1") + d.str("deliv-addr2")
            } else {
                w.deliv["deliv-key-type"] = "D"; w.deliv["deliv-sales-key"] = key
                w.deliv["deliv-name"] = "Record Not Found"
                name = w.deliv.str("deliv-name"); addr = w.deliv.str("deliv-addr1") + w.deliv.str("deliv-addr2")
            }
            if Cobol.rtrim(name) != "Record Not Found" { addr = addr.replacingOccurrences(of: delim, with: ",") }
            name = Cobol.x(name, 30)
            p.after(1, line6(s.l10n.raw("report.sl010.deliver1"), s.l10n.raw("report.sl010.deliver2"), name, "", "", " ", " ", 0, 0, 0))
            p.after(1, SLA.spaces(20) + Cobol.x(addr, 112))
            w.lineCnt += 2
        }
        if r.int("notes-tag") > 0 {
            var addr: String
            if let d = w.delivery.read(key: delivKey("N", key)) {
                w.deliv = d
                addr = d.str("deliv-addr1") + d.str("deliv-addr2")
            } else {
                w.deliv["deliv-key-type"] = "N"; w.deliv["deliv-sales-key"] = key
                w.deliv["deliv-addr1"] = "Record Not Found"; w.deliv["deliv-addr2"] = ""
                addr = w.deliv.str("deliv-addr1") + w.deliv.str("deliv-addr2")
            }
            var l7 = [Character](repeating: " ", count: 112)
            var ptr = 1
            SLA.string(s.l10n.raw("report.sl010.notes") + SLA.delimited(addr), into: &l7, pointer: &ptr)
            p.after(1, SLA.spaces(20) + String(l7))
            w.lineCnt += 1
        }
        p.after(1, "")
        w.lineCnt += 3
        w.printOut = "Y"
    }

    // MARK: slcreate

    /// 戻り値 false = "N" (exit program)
    static func slcreate(_ s: Session, _ w: WS) throws -> Bool {
        let c = s.console
        while true {
            displayHeading(s, w)
            c.display(s.t("sl010.sl103"), at: 1201, color: 4)
            c.display(s.t("sl010.sl104"), at: 1301, color: 2)
            let r = try c.accept(at: 1343, size: 1, initial: " ", options: [.update], color: 6).uppercased()
            if r == "N" { return false }
            if r == "Y" { break }
        }
        c.display(s.t("sl010.sl105"), at: 1506, color: 2)
        w.sales.openOutput()
        w.delivery.openOutput()
        w.sales.close(); w.delivery.close()
        SLA.setFileStatus(s, 12, 1); SLA.setFileStatus(s, 14, 1)
        s.sys["sales-ledger"] = "Y"
        return true
    }
}
