import Foundation

extension PLA {
    /// fddel.cob delivery-record (134 バイト)
    static let delivLayout = Layout("delivery-record", [
        ("deliv-key-type", .x(1)), ("deliv-purchase-key", .x(7)), ("deliv-name", .x(30)), ("deliv-address", .x(96)),
    ])
    static func deliveryFile(_ s: Session) -> IndexedFile { IndexedFile(s.store, path: s.ledgers + "delivery.dat", layout: delivLayout, keyLength: 8) }

    /// FD レコード領域の初期状態 (全バイト 2 進ゼロ)
    static func fdArea(_ layout: Layout) -> Record {
        Record(layout, bytes: [UInt8](repeating: 0, count: layout.size))
    }
    /// INITIALIZE: FILLER は変更しない
    static func initialize(_ r: inout Record) {
        let n = Record(r.layout)
        for f in r.layout.order {
            if case .filler = f.type { continue }
            for i in 0..<f.type.size { r.bytes[f.offset + i] = n.bytes[f.offset + i] }
        }
    }
    /// copybooks/FileStat-Msgs.cpy
    static func fileStatMsg(_ s: Session, _ status: String) -> String {
        let known = ["00", "02", "04", "05", "07", "10", "14", "21", "22", "23", "30", "31", "34", "35", "37", "38", "39",
                     "41", "42", "43", "44", "46", "47", "48", "49", "51", "52", "57", "61", "91"]
        return known.contains(status) ? s.t("pl.fs_" + status) : Cobol.x("", 25)
    }
}

/// purchase/pl010.cbl: 仕入先マスタ保守
final class PLA010 {
    static let progName = "PL010 (3.01.13)"
    static func run(_ s: Session) throws { try PLA010(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, delivery: IndexedFile
    var purch: Record, deliv: Record
    var menuReply = 0
    var wsReply = " "
    var a = 0, y = 0
    var escapeCode = " "
    var saveNotesTag: Int64 = 0
    var printOut = " "
    var d2402 = " ", d2403 = " ", d24check = Cobol.x("", 15)
    var notes1 = Cobol.x("", 48), notes2 = Cobol.x("", 48)
    var custIn = "", statusIn = " ", creditIn: Int64 = 0, creditOp = " ", invoiceIn: Int64 = 0, invoiceOp = " "
    var averageIn: Int64 = 0, averageOp = " ", overdueIn: Int64 = 0, overdueOp = " ", enterDateIn = "", enterDateOp = " "
    var wsEnterDate: Int64 = 0
    var customerIn = Cobol.x("", 7)
    var customerCode = Cobol.x("", 7)
    var checkDigit = 0
    var errorCode = 0
    var lineCnt = 0
    var l3Report = "", l3Date = ""
    var localDate = ""

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); delivery = PLA.deliveryFile(s)
        purch = PLA.fdArea(PLA.purchLayout); deliv = PLA.fdArea(PLA.delivLayout)
    }

    func main() throws {
        if s.sys.str("purchase-ledger") != "Y" {
            if try !plcreate() { return }
        }
        while true {
            // menu-return
            menuReply = 0
            displayHeading()
            while true {
                c.display(s.t("pl010.select"), at: 701, color: 2)
                c.display(s.t("pl010.menu_1"), at: 1004, color: 2)
                c.display(s.t("pl010.menu_2"), at: 1204, color: 2)
                c.display(s.t("pl010.menu_3"), at: 1404, color: 2)
                c.display(s.t("pl010.menu_4"), at: 1604, color: 2)
                c.display(s.t("pl010.menu_5"), at: 1804, color: 2)
                c.display(s.t("pl010.menu_9"), at: 2104, color: 2)
                menuReply = Int(try c.accept(at: 743, size: 1, kind: .numeric, options: [.auto], color: 6)) ?? 0
                if menuReply == 9 { return }
                if (1...5).contains(menuReply) { break }
            }
            switch menuReply {
            case 1: try setupSuppliers()
            case 2: try amendSupplier()
            case 3: try deleteSupplier()
            case 4: try reportSupplier()
            default: try displaySuppliers()
            }
        }
    }

    func clearErrorLine() { c.display(" ", at: 23, 1, eraseEOL: true) }

    // MARK: test-escape section

    func testEscape() throws {
        c.display(escapeCode, at: 2071, color: 6)
        repeat {
            escapeCode = try c.accept(at: 2071, size: 1, initial: escapeCode, options: [.update], color: 6).uppercased()
        } while !["B", "S", "Q", "K", "D"].contains(escapeCode)
    }

    // MARK: display-heading section

    func displayHeading() {
        c.display(" ", at: 101, eraseEOS: true)
        d2402 = " "; d24check = Cobol.x("", 15)
        d2403 = "]"
        if menuReply != 4 {
            c.display(PLA010.progName, at: 101, color: 2)
            localDate = PLA.toDayDisplay(s)
            c.display(localDate, at: 171, color: 2)
        }
        switch menuReply {
        case 0:
            c.display(s.t("pl010.title"), at: 124, color: 2)
            c.display(s.t("pl010.function_menu"), at: 434, color: 2)
        case 1:
            c.display(s.t("pl010.title_create"), at: 129, color: 2)
            d24check = s.t("pl010.check_digit")
            d2402 = "]"
            d2403 = " "
        case 2: c.display(s.t("pl010.title_amend"), at: 129, color: 2)
        case 3: c.display(s.t("pl010.title_delete"), at: 129, color: 2)
        case 5: c.display(s.t("pl010.title_display"), at: 129, color: 2)
        default: break
        }
    }

    // MARK: display-02 (screen section)

    func setCheckDigitChar(_ ch: String) {
        // d24-digit は d24-check の 14 桁目 (末尾から 2 文字目。訳文は全角文字を含み文字数が異なる)
        var a = Array(d24check)
        a[a.count - 2] = ch.first ?? " "
        d24check = String(a)
    }

    func nz(_ v: Int64, _ digits: Int) -> String { Cobol.z(abs(v) % Cobol.pow10(digits), digits) }

    func fields02() -> [ScreenField] {
        let d = abs(purch.int("purch-discount")) % 10000
        return [
            ScreenField(line: 6, col: 17, size: 30, value: purch.str("purch-name"), color: 2),
            ScreenField(line: 7, col: 17, size: 48, value: purch.str("purch-addr1"), color: 2),
            ScreenField(line: 8, col: 17, size: 48, value: purch.str("purch-addr2"), color: 2),
            ScreenField(line: 10, col: 17, size: 6, kind: .numeric, pic: "9(6)", value: nz(purch.int("purch-sortcode"), 6), color: 2),
            ScreenField(line: 11, col: 17, size: 8, kind: .numeric, pic: "9(8)", value: nz(purch.int("purch-accountno"), 8), color: 2),
            ScreenField(line: 12, col: 17, size: 48, value: notes1, color: 2),
            ScreenField(line: 13, col: 17, size: 48, value: notes2, color: 2),
            ScreenField(line: 14, col: 17, size: 13, value: purch.str("purch-phone"), color: 2),
            ScreenField(line: 14, col: 38, size: 4, value: purch.str("purch-ext"), color: 2),
            ScreenField(line: 14, col: 52, size: 13, value: purch.str("purch-fax"), color: 2),
            ScreenField(line: 15, col: 17, size: 30, value: purch.str("purch-email"), color: 2),
            ScreenField(line: 18, col: 17, size: 2, kind: .numeric, pic: "99", value: nz(purch.int("purch-credit"), 2), color: 2),
            ScreenField(line: 19, col: 17, size: 7, kind: .numeric, pic: "9(7)", value: nz(purch.int("purch-limit"), 7), color: 2),
            ScreenField(line: 19, col: 38, size: 5, kind: .numericEdited, pic: "99.99", value: Cobol.z(d / 100, 2) + "." + Cobol.z(d % 100, 2), color: 2),
        ]
    }

    func store02(_ f: [ScreenField]) {
        func num(_ i: Int, _ digits: Int, scale: Int = 0) -> Int64 {
            let (v, sc) = Cobol.numval(f[i].value)
            return abs(Cobol.rescale(v, from: sc, to: scale)) % Cobol.pow10(digits)
        }
        purch.set("purch-name", f[0].value); purch.set("purch-addr1", f[1].value); purch.set("purch-addr2", f[2].value)
        purch.setInt("purch-sortcode", num(3, 6)); purch.setInt("purch-accountno", num(4, 8))
        notes1 = f[5].value; notes2 = f[6].value
        purch.set("purch-phone", f[7].value); purch.set("purch-ext", f[8].value); purch.set("purch-fax", f[9].value)
        purch.set("purch-email", f[10].value)
        purch.setInt("purch-credit", num(11, 2)); purch.setInt("purch-limit", num(12, 7))
        purch.setInt("purch-discount", num(13, 4, scale: 2))
    }

    func display02(_ f: [ScreenField]? = nil) {
        func lit(_ key: String, _ line: Int, _ col: Int) { c.display(s.t(key), at: line, col, color: 2) }
        func raw(_ text: String, _ line: Int, _ col: Int) { c.display(text, at: line, col, color: 2) }
        lit("pl010.supplier_nos", 4, 1)
        raw(d2402, 4, 23); raw(d2403, 4, 24); raw(d24check, 4, 26)
        lit("pl010.supplier_name", 6, 1); raw("]", 6, 47)
        lit("pl010.addr", 7, 10); raw("]", 7, 65)
        raw("[", 8, 16); raw("]", 8, 65)
        lit("pl010.bank_details", 9, 1)
        lit("pl010.sort_code", 10, 3); raw("]", 10, 23)
        lit("pl010.account_no", 11, 3); raw("]", 11, 25)
        lit("pl010.supplier_note", 12, 1); raw("]", 12, 65)
        raw("[", 13, 16); raw("]", 13, 65)
        lit("pl010.telephone", 14, 1); raw("]", 14, 30)
        lit("pl010.ext", 14, 32); raw("]", 14, 42)
        lit("pl010.fax", 14, 45); raw("]", 14, 65)
        lit("pl010.email", 15, 1); raw("]", 15, 47)
        lit("pl010.credit_period", 18, 1); raw("]", 18, 19)
        lit("pl010.credit_limit", 19, 1)
        lit("pl010.discount", 19, 24); raw("]", 19, 43)
        raw("*******************", 19, 56)
        lit("pl010.unapplied_bal", 20, 1); raw("}", 20, 29)
        lit("pl010.escape_code", 20, 56); raw("] *", 20, 72)
        lit("pl010.current_bal", 21, 1); raw("}", 21, 29)
        lit("pl010.esc_back", 21, 56)
        lit("pl010.last_invoice", 22, 1); raw("}", 22, 27)
        lit("pl010.esc_save", 22, 56)
        lit("pl010.last_payment", 23, 1); raw("}", 23, 27)
        lit("pl010.esc_quit", 23, 56)
        raw("*******************", 24, 56)
        c.displayFields(f ?? fields02())
    }

    // MARK: customer-display section

    func customerDisplay() {
        let k7 = String(Array(purch.str("purch-key"))[6])
        if menuReply == 1 { setCheckDigitChar(k7) } else { d2402 = k7 }
        display02()
        if menuReply == 1 || menuReply == 2 { return }
        c.display(Pic.edit("-(8)9.99", value: purch.int("purch-unapplied"), scale: 2), at: 2017, color: 3)
        c.display(Pic.edit("-(8)9.99", value: purch.int("purch-current"), scale: 2), at: 2117, color: 3)
        if purch.int("purch-last-inv") != 0 { c.display(PLA.dateDisplay(s, purch.int("purch-last-inv")), at: 2217, color: 3) }
        if purch.int("purch-last-pay") != 0 { c.display(PLA.dateDisplay(s, purch.int("purch-last-pay")), at: 2317, color: 3) }
    }

    // MARK: display-outline section

    func displayOutline() {
        displayHeading()
        PLA.initialize(&purch); PLA.initialize(&deliv)
        notes1 = Cobol.x("", 48); notes2 = Cobol.x("", 48)
        display02()
    }

    // MARK: customer-data section

    func delivKey() -> [UInt8] { SJIS.encode("N" + purch.str("purch-key"), size: 8) }

    func customerData() throws {
        while true {
            var errorFlag = 0
            let f = fields02()
            display02(f)
            try c.acceptScreen(f)
            store02(f)
            if !validateAddress(purch.str("purch-address")) {
                c.display(s.t("pl010.pl101"), at: 766, color: 4)
                errorFlag = 1
            } else {
                c.display(" ", at: 766, eraseEOL: true)
            }
            let notesBlank = Cobol.rtrim(notes1 + notes2).isEmpty
            if notesBlank && purch.int("purch-notes-tag") != 0 {
                deliv.set("deliv-purchase-key", purch.str("purch-key"))
                deliv.set("deliv-key-type", "N")
                if delivery.delete(key: delivKey()) != "00" { purch.setInt("purch-notes-tag", 0) }
            }
            purch.setInt("purch-notes-tag", notesBlank ? 0 : 1)
            if errorFlag == 0 { return }
        }
    }

    // MARK: validate-address section

    func validateAddress(_ address: String) -> Bool {
        let test = Array(Cobol.x(address, 92))
        let delim = s.sys.str("pl-delim").first ?? " "
        let n = test.filter { $0 == delim }.count
        var truth = !(n > 4 || n < 1)
        let before = test.firstIndex(of: delim) ?? test.count
        if before > 30 { truth = false }
        return truth
    }

    // MARK: accept-key section

    func acceptKey() throws {
        purch.set("purch-key", "")
        purch.set("purch-key", try c.accept(at: 417, size: 7, color: 3).uppercased())
        errorCode = 0
        if Cobol.rtrim(purch.str("purch-key")).isEmpty { errorCode = 999; return }
        saveNotesTag = 0
        guard let r = purchase.read(key: purch.str("purch-key")) else {
            errorCode = 3
            try PLA.maps99(s, 3)
            customerCode = Cobol.x("", 7)
            return
        }
        purch = r
        clearErrorLine()
        customerCode = purch.str("purch-key")
        if purch.int("purch-notes-tag") != 0 {
            deliv.set("deliv-purchase-key", purch.str("purch-key"))
            deliv.set("deliv-key-type", "N")
            if let d = delivery.read(key: delivKey()) {
                deliv = d
                let adr = Array(d.str("deliv-address"))
                notes1 = String(adr[0..<48]); notes2 = String(adr[48..<96])
                saveNotesTag = 1
                purch.setInt("purch-notes-tag", 1)
            } else {
                purch.setInt("purch-notes-tag", 0)
                notes1 = Cobol.x(s.l10n.raw("pl010.record_not_found"), 48)
                notes2 = Cobol.x("", 48)
            }
        }
    }

    func openIO() {
        _ = purchase.open()
        if delivery.open() != "00" {
            delivery.close()
            delivery.openOutput()
            delivery.close()
            _ = delivery.open()
        }
    }
    func closeFiles() { purchase.close(); delivery.close() }

    // MARK: setup-suppliers section

    func setupSuppliers() throws {
        openIO()
        defer { closeFiles() }
        input: while true {
            notes1 = Cobol.x("", 48); notes2 = Cobol.x("", 48)
            displayOutline()
            while true {
                // customer-accept
                var nos = try c.accept(at: 417, size: 6, color: 3)
                if Cobol.rtrim(nos).isEmpty { return }
                nos = nos.uppercased()
                c.display(nos, at: 417, color: 3)
                clearErrorLine()
                guard let cd = Maps09.checkDigit(nos) else { continue }
                checkDigit = cd
                customerCode = nos + String(cd)
                purch.set("purch-key", customerCode)
                if let r = purchase.read(key: customerCode) {
                    purch = r
                    try PLA.maps99(s, 22)
                    customerDisplay()
                    continue
                }
                break
            }
            // customer-details
            if menuReply == 1 { c.display(String(checkDigit), at: 444, color: 3) }
            let sp30 = Cobol.x("", 30)
            c.display(sp30, at: 21, 6)
            c.display(sp30, at: 22, 6)
            c.display(sp30, at: 23, 6)
            PLA.initialize(&purch); PLA.initialize(&deliv)
            purch.setInt("purch-status", 1)
            purch.set("purch-key", customerCode)
            purch.setInt("purch-create-date", s.sys.int("run-date"))
            purch.setInt("purch-credit", s.sys.int("age-to-pay"))
            repeat {
                customerDisplay()
                try customerData()
                escapeCode = "S"
                try testEscape()
            } while escapeCode == "B"
            if escapeCode == "Q" { return }
            purchase.write(purch)
            if purch.int("purch-notes-tag") != 0 {
                deliv.set("deliv-purchase-key", purch.str("purch-key"))
                deliv.set("deliv-key-type", "N")
                deliv.set("deliv-name", "")
                deliv.set("deliv-address", notes1 + notes2)
                delivery.write(deliv)
            }
            PLA.initialize(&purch); PLA.initialize(&deliv)
            continue input
        }
    }

    // MARK: amend-supplier section

    /// デバッグ用として残っている INVALID KEY 時の表示
    func debugNote(_ key: String, status: String, positioned: Bool) throws {
        c.display(s.t(key), at: 23, 1)
        if positioned { c.display(status, at: 23, 20) } else { c.display(status, at: 23, s.t(key).count + 1) }
        c.display(PLA.fileStatMsg(s, status), at: 23, 23)
        c.display(s.t("pl010.note_and_hit_return"), at: 24, 1)
        _ = try c.accept(at: 24, 20, size: 1)
        c.display(" ", at: 23, 1, eraseEOS: true)
    }

    func amendSupplier() throws {
        openIO()
        defer { closeFiles() }
        input: while true {
            displayOutline()
            repeat {
                try acceptKey()
                if errorCode == 999 { return }
            } while Cobol.rtrim(customerCode).isEmpty
            saveNotesTag = purch.int("purch-notes-tag")
            repeat {
                customerDisplay()
                try customerData()
                escapeCode = "S"
                try testEscape()
            } while escapeCode == "B"
            if escapeCode == "Q" { continue input }
            purchase.rewrite(purch)
            deliv.set("deliv-key-type", "N")
            deliv.set("deliv-purchase-key", purch.str("purch-key"))
            deliv.set("deliv-name", "")
            deliv.set("deliv-address", notes1 + notes2)
            if purch.int("purch-notes-tag") != 0 && saveNotesTag == 0 {
                if delivery.write(deliv) != "00" { try debugNote("pl010.dbg_write_notes", status: delivery.status, positioned: true) }
            } else if purch.int("purch-notes-tag") != 0 {
                if delivery.rewrite(deliv) != "00" { try debugNote("pl010.dbg_rewrite_notes", status: delivery.status, positioned: false) }
            }
            if purch.int("purch-notes-tag") == 0 && saveNotesTag != 0 {
                if delivery.delete(key: delivKey()) != "00" { try debugNote("pl010.dbg_delete_notes", status: delivery.status, positioned: false) }
            }
            if purchase.rewrite(purch) != "00" { try debugNote("pl010.dbg_rewrite_rec", status: purchase.status, positioned: false) }
        }
    }

    // MARK: delete-supplier section

    func deleteSupplier() throws {
        _ = purchase.open(); _ = delivery.open()
        defer { closeFiles() }
        input: while true {
            displayOutline()
            c.display(s.t("pl010.esc_dormant"), at: 2159, color: 2)
            c.display(s.t("pl010.esc_kill"), at: 2259, color: 2)
            while true {
                try acceptKey()
                if errorCode == 999 { return }
                if Cobol.rtrim(customerCode).isEmpty { continue }
                customerDisplay()
                escapeCode = "K"
                try testEscape()
                if escapeCode == "Q" { return }
                if purch.int("purch-current") != 0 || purch.int("purch-unapplied") != 0 {
                    c.display(s.t("pl010.pl109"), at: 501, color: 4)
                    continue
                }
                break
            }
            c.display(" ", at: 501, eraseEOL: true)
            if escapeCode == "D" {
                purch.setInt("purch-status", 0)
                purchase.rewrite(purch)
            }
            if escapeCode != "K" { continue input }
            // main-output: レガシーはピリオドの位置により注記の有無に関係なく delivery を削除する
            if purch.int("purch-notes-tag") != 0 { deliv.set("deliv-key-type", "N") }
            deliv.set("deliv-purchase-key", purch.str("purch-key"))
            delivery.delete(key: SJIS.encode(deliv.str("deliv-key-type") + deliv.str("deliv-purchase-key"), size: 8))
            purchase.delete(key: SJIS.encode(purch.str("purch-key"), size: 7))
            return
        }
    }

    // MARK: display-suppliers section

    func displaySuppliers() throws {
        _ = purchase.open(); _ = delivery.open()
        defer { closeFiles() }
        input: while true {
            displayOutline()
            repeat {
                try acceptKey()
                if errorCode == 999 { return }
            } while Cobol.rtrim(customerCode).isEmpty
            customerDisplay()
            escapeCode = "S"
            try testEscape()
            if wsReply != "Q" { continue input }
            return
        }
    }

    // MARK: report-supplier section

    func reportSupplier() throws {
        try reportSelection()
        reportHeadingSetup()
        produceReport()
        closeFiles()
    }

    func isOp(_ v: String) -> Bool { ["L", "G", "E", " "].contains(v) }

    func reportSelection() throws {
        _ = purchase.open(); _ = delivery.open()
        custIn = Cobol.x("", 6); statusIn = " "; creditOp = " "; invoiceOp = " "; averageOp = " "; overdueOp = " "
        enterDateOp = " "; enterDateIn = Cobol.x("", 10); printOut = " "
        creditIn = 0; invoiceIn = 0; averageIn = 0; overdueIn = 0; wsEnterDate = 0
        var first = true
        while true {
            let f = [
                ScreenField(line: 8, col: 22, size: 6, value: custIn, color: 2),
                ScreenField(line: 10, col: 22, size: 1, value: statusIn, color: 2),
                ScreenField(line: 12, col: 22, size: 2, kind: .numeric, pic: "99", value: nz(creditIn, 2), color: 2),
                ScreenField(line: 12, col: 28, size: 1, value: creditOp, color: 2),
                ScreenField(line: 17, col: 22, size: 5, kind: .numeric, pic: "9(5)", value: nz(invoiceIn, 5), color: 2),
                ScreenField(line: 17, col: 30, size: 1, value: invoiceOp, color: 2),
                ScreenField(line: 19, col: 22, size: 5, kind: .numeric, pic: "9(5)", value: nz(averageIn, 5), color: 2),
                ScreenField(line: 19, col: 30, size: 1, value: averageOp, color: 2),
                ScreenField(line: 21, col: 22, size: 5, kind: .numeric, pic: "9(5)", value: nz(overdueIn, 5), color: 2),
                ScreenField(line: 21, col: 30, size: 1, value: overdueOp, color: 2),
                ScreenField(line: 23, col: 17, size: 10, value: enterDateIn, color: 2),
                ScreenField(line: 23, col: 30, size: 1, value: enterDateOp, color: 2),
            ]
            if first { display03(f); first = false }
            try c.acceptScreen(f)
            func num(_ i: Int) -> Int64 { abs(Cobol.numval(f[i].value).0) }
            custIn = f[0].value.uppercased(); statusIn = f[1].value
            creditIn = num(2) % 100; creditOp = f[3].value
            invoiceIn = num(4) % 100000; invoiceOp = f[5].value
            averageIn = num(6) % 100000; averageOp = f[7].value
            overdueIn = num(8) % 100000; overdueOp = f[9].value
            enterDateIn = f[10].value; enterDateOp = f[11].value
            customerIn = Cobol.x(custIn, 7)
            statusIn = statusIn.uppercased()
            if !["L", "D", " "].contains(statusIn) { continue }
            creditOp = creditOp.uppercased()
            if !isOp(creditOp) { continue }
            invoiceOp = invoiceOp.uppercased()
            if !isOp(invoiceOp) { continue }
            averageOp = averageOp.uppercased()
            if !isOp(averageOp) { continue }
            overdueOp = overdueOp.uppercased()
            if !isOp(overdueOp) { continue }
            enterDateOp = enterDateOp.uppercased()
            if !isOp(enterDateOp) { continue }
            if Cobol.rtrim(enterDateIn).isEmpty { return }
            var t = enterDateIn
            for ch in [".", ",", "-"] { t = t.replacingOccurrences(of: ch, with: "/") }
            let bin = PLA.validateDate(s, t).bin
            if bin == 0 {
                c.display(s.t("pl010.pl005"), at: 2362, color: 4)
                continue
            }
            c.display(" ", at: 2362, eraseEOL: true)
            wsEnterDate = Int64(bin)
            return
        }
    }

    func display03(_ f: [ScreenField]) {
        func lit(_ key: String, _ line: Int, _ col: Int) { c.display(s.t(key), at: line, col, color: 2) }
        func raw(_ text: String, _ line: Int, _ col: Int) { c.display(text, at: line, col, color: 2) }
        c.display(" ", at: 101, eraseEOS: true)
        raw(PLA010.progName, 1, 1)
        lit("pl010.supplier_file", 1, 34)
        raw(Cobol.x(localDate, 10), 1, 71)
        lit("pl010.report_attributes", 3, 32)
        lit("pl010.r_supplier_number", 8, 3); raw("]", 8, 28); lit("pl010.r_supplier_help", 8, 33)
        lit("pl010.r_status", 10, 3); raw("]", 10, 23); lit("pl010.r_status_help", 10, 33)
        lit("pl010.r_credit", 12, 3); raw("]  [", 12, 24); raw("]", 12, 29); lit("pl010.r_credit_help", 12, 33)
        lit("pl010.r_credit_l", 13, 37); lit("pl010.r_credit_g", 14, 37); lit("pl010.r_credit_e", 15, 37)
        lit("pl010.r_invoice", 17, 3); raw("] [", 17, 27); raw("]", 17, 31); lit("pl010.r_invoice_help", 17, 33)
        lit("pl010.r_average", 19, 3); raw("] [", 19, 27); raw("]", 19, 31); lit("pl010.r_average_help", 19, 33)
        lit("pl010.r_overdue", 21, 3); raw("] [", 21, 27); raw("]", 21, 31); lit("pl010.r_overdue_help", 21, 33)
        lit("pl010.r_date", 23, 3); raw("] [", 23, 27); raw("]", 23, 31); lit("pl010.r_date_help", 23, 33)
        c.displayFields(f)
    }

    // MARK: produce-report section

    func produceReport() {
        let p = PLA.Printer(s)
        p.openOutput()
        a = 0
        let pageLines = Int(s.sys.int("page-lines"))
        func headings() {
            a += 1
            let line1 = Cobol.x(PLA010.progName, 57) + Cobol.x(s.t("pl010.rep_title"), 67) + s.t("pl010.rep_page") + Pic.edit("zz9", value: Int64(a % 1000), scale: 0)
            let line3 = Cobol.x(s.sys.str("usera"), 40) + s.t("pl010.rep_report_on") + Cobol.x(l3Report, 70) + Cobol.x(l3Date, 10)
            if a != 1 {
                p.writePage(line1)
                p.write(line3, after: 1)
                p.write("", after: 1)
            } else {
                p.writeBefore(line1, before: 1)
                p.writeBefore(line3, before: 1)
            }
            p.write(s.t("pl010.rep_line4a") + s.t("pl010.rep_line4b") + s.t("pl010.rep_line4c"), after: 1)
            p.write(Cobol.x(s.t("pl010.rep_line5a"), 87) + s.t("pl010.rep_line5b"), after: 1)
            p.write("", after: 1)
            lineCnt = 6
        }
        func bwz(_ pic: String, _ v: Int64, scale: Int = 0) -> String {
            v == 0 ? Cobol.x("", Pic.size(pic)) : Pic.edit(pic, value: v, scale: scale)
        }
        func listing() {
            if lineCnt > pageLines { headings() }
            var phone = Cobol.x("", 18)
            if Cobol.rtrim(purch.str("purch-ext")).isEmpty {
                phone = Cobol.x(purch.str("purch-phone"), 18)
            } else {
                var ph = purch.str("purch-phone")
                if let r = ph.range(of: "  ") { ph = String(ph[..<r.lowerBound]) }
                // y を 1 戻すため電話番号の最後の 1 文字が "x" で上書きされる
                var a18 = Array(phone)
                var y = 1
                for ch in ph where y <= 18 { a18[y - 1] = ch; y += 1 }
                y -= 1
                for ch in "x" + purch.str("purch-ext") where y >= 1 && y <= 18 { a18[y - 1] = ch; y += 1 }
                phone = String(a18)
            }
            let slDelim = s.sys.str("sl-delim").first ?? " "
            let l7 = Cobol.x("", 20) + Cobol.x(String(purch.str("purch-address").map { $0 == slDelim ? "," : $0 }), 112)
            let line6 = Cobol.x(purch.str("purch-key"), 10)
                + Cobol.x(purch.int("purch-status") == 1 ? s.l10n.raw("pl010.rep_active") : s.l10n.raw("pl010.rep_dormant"), 10)
                + Cobol.x(purch.str("purch-name"), 51) + phone + Cobol.x(purch.str("purch-fax"), 13)
                + bwz("z(8)9", abs(purch.int("purch-limit")) % 1_000_000_000) + bwz("z(7)9", abs(purch.int("purch-credit")))
                + bwz("z(7)9.99", purch.int("purch-discount"), scale: 2)
            if lineCnt > pageLines - 3 { headings() }
            p.write(line6, after: 1)
            p.write(l7, after: 1)
            if purch.int("purch-notes-tag") > 0 {
                // notes-print
                var adr = Cobol.x(s.l10n.raw("pl010.record_not_found"), 96)
                if let d = delivery.read(key: delivKey()) { deliv = d; adr = d.str("deliv-address") }
                if let r = adr.range(of: "  ") { adr = String(adr[..<r.lowerBound]) }
                p.write(Cobol.x("", 20) + Cobol.x(s.l10n.raw("pl010.rep_notes") + adr, 112), after: 1)
                lineCnt += 1
            }
            p.write("", after: 1)
            lineCnt += 3
            printOut = "Y"
        }
        func testNum(_ op: String, _ t1: Int64, _ t2: Int64) -> Bool {
            (op == " ") || (op == "L" && t2 < t1) || (op == "G" && t2 > t1) || (op == "E" && t2 == t1)
        }
        headings()
        var upper = customerIn
        if !Cobol.rtrim(customerIn).isEmpty {
            purch.set("purch-key", customerIn)
            if !purchase.start(notLessThan: SJIS.encode(customerIn, size: 7)) { a = 1 }
            upper = customerIn.replacingOccurrences(of: " ", with: "Z")
        } else {
            purchase.startFirst()
        }
        while let r = purchase.readNext() {
            purch = r
            let live = purch.int("purch-status") == 1, dead = purch.int("purch-status") == 0
            if statusIn == "L" && dead { continue }
            if statusIn == "D" && live { continue }
            if !Cobol.rtrim(upper).isEmpty && purch.str("purch-key") > upper { break }
            if creditOp != " " && !testNum(creditOp, creditIn, purch.int("purch-credit")) { continue }
            if invoiceOp != " " && !testNum(invoiceOp, invoiceIn, purch.int("purch-activety")) { continue }
            if averageOp != " " && !testNum(averageOp, averageIn, purch.int("purch-average")) { continue }
            if overdueOp != " " && purch.int("purch-current") > 0
                && !testNum(overdueOp, overdueIn, s.sys.int("run-date") - purch.int("purch-last-inv")) { continue }
            if enterDateOp != " " && !testNum(enterDateOp, wsEnterDate, purch.int("purch-create-date")) { continue }
            listing()
        }
        customerIn = upper
        p.close()
        if printOut == "Y" { p.spool() }
    }

    // MARK: report-heading-setup section

    func reportHeadingSetup() {
        l3Date = PLA.toDayDisplay(s)
        var rep = [Character](repeating: " ", count: 70)
        var y = 1
        func put(_ text: String) {
            // STRING ... WITH POINTER: あふれる場合は入る分だけ転送して終了
            for ch in text {
                if y < 1 || y > 70 { return }
                rep[y - 1] = ch; y += 1
            }
        }
        func operand(_ op: String) -> String { op == "L" ? "< " : (op == "G" ? "> " : "= ") }
        let allBlank = statusIn == " " && creditOp == " " && invoiceOp == " " && averageOp == " " && overdueOp == " "
            && Cobol.rtrim(customerIn).isEmpty
        put(s.l10n.raw(allBlank ? "pl010.rep_all" : "pl010.rep_matched"))
        y += 1
        if statusIn == "L" { put(s.l10n.raw("pl010.rep_live")) }
        if statusIn == "D" { put(s.l10n.raw("pl010.rep_dormant")) }
        y += 1
        if creditOp != " " { put(operand(creditOp) + Pic.edit("z9", value: creditIn, scale: 0) + s.t("pl010.rep_days_credit")) }
        y += 1
        if invoiceOp != " " { put(operand(invoiceOp) + Pic.edit("zzzz9", value: invoiceIn, scale: 0) + s.t("pl010.rep_invoices")) }
        y += 1
        if averageOp != " " { put(operand(averageOp) + Pic.edit("zzzz9", value: averageIn, scale: 0) + s.t("pl010.rep_av_value")) }
        y += 1
        if overdueOp != " " { put(operand(overdueOp) + Pic.edit("zzzz9", value: overdueIn, scale: 0) + s.t("pl010.rep_days_overdue")) }
        y += 1
        if enterDateOp != " " { put(operand(enterDateOp) + Cobol.x(enterDateIn, 8) + s.t("pl010.rep_entry_date")) }
        y += 1
        if !Cobol.rtrim(customerIn).isEmpty { put(s.t("pl010.rep_keys_matching") + customerIn) }
        l3Report = String(rep)
    }

    // MARK: plcreate section

    /// false = exit program
    func plcreate() throws -> Bool {
        while true {
            displayHeading()
            c.display(s.t("pl010.pl103"), at: 1201, color: 4)
            c.display(s.t("pl010.pl104"), at: 1301, color: 2)
            wsReply = " "
            wsReply = try c.accept(at: 1343, size: 1, initial: wsReply, options: [.update], color: 6).uppercased()
            if wsReply == "N" { return false }
            if wsReply == "Y" { break }
        }
        c.display(s.t("pl010.pl105"), at: 1506, color: 2)
        // ストアへの OPEN OUTPUT は失敗しないため PL106/PL107 の分岐には入らない
        purchase.openOutput()
        delivery.openOutput()
        closeFiles()
        PLA.setFileStatus(s, 22, 1); PLA.setFileStatus(s, 14, 1)
        s.sys.set("purchase-ledger", "Y")
        return true
    }
}
