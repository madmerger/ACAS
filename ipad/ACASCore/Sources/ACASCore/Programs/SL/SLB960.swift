import Foundation

/// sales/sl960.cbl: Customer Set-Up from Invoicing (請求書入力からの得意先新規登録)
enum SLB960 {
    static let progName = "SL960 (3.01.03)"

    /// common/maps09.cbl: 得意先コードのチェックディジット ("C" = 計算、"V" = 検証)。戻り値 = maps09-reply
    static func maps09(_ nos: String, checkDigit: inout Int, reply: String) -> String {
        let alpha = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-")
        let work = Array(Cobol.x(nos, 6))
        var suma = 0
        var a = 1
        while a <= 6 {
            if let q = alpha.firstIndex(of: work[a - 1]) {
                suma += (q + 1) * (8 - a)
            } else {
                suma = 0; a = 7
            }
            a += 1
        }
        if suma == 0 { return "N" }
        let z = suma / 11
        a = 11 - (suma - 11 * z)
        var r = reply
        if r == "C" { checkDigit = a % 10; r = "Y" }
        if r == "V" && a == checkDigit { r = "Y" }
        return r
    }

    static func run(_ s: Session) throws {
        let c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        let salesFile = SLB.salesFile(s)
        let delivery = SLB.deliveryFile(s)
        salesFile.open()
        if delivery.open() != "00" {
            delivery.openOutput(); delivery.close(); delivery.open()
        }
        c.display(" ", at: 301, eraseEOS: true)
        defer { salesFile.close(); delivery.close() }

        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
        var escapeCode = " ", lateCharg = " ", dunLetter = " "
        let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))

        func lit(_ key: String, _ l: Int, _ col: Int) { c.display(s.t(key), at: l, col, color: 2) }
        func literals() {
            lit("sl960.cust_nos", 4, 6)
            c.display("  ", at: 4, 28, color: 2)
            c.display(Cobol.x(s.t("sl960.check_digit"), 13) + " }", at: 4, 31, color: 2)
            lit("sl960.cust_name", 6, 6); c.display("]", at: 6, 52, color: 2)
            lit("sl960.addr", 7, 15); c.display("]", at: 7, 70, color: 2)
            c.display("[", at: 8, 21, color: 2); c.display("]", at: 8, 70, color: 2)
            lit("sl960.deliv_name", 9, 6); c.display("]", at: 9, 52, color: 2)
            lit("sl960.addr", 10, 15); c.display("]", at: 10, 70, color: 2)
            c.display("[", at: 11, 21, color: 2); c.display("]", at: 11, 70, color: 2)
            lit("sl960.telephone", 13, 6); c.display("]", at: 13, 35, color: 2)
            lit("sl960.ext", 13, 37); c.display("]", at: 13, 47, color: 2)
            lit("sl960.fax", 13, 50); c.display("]", at: 13, 70, color: 2)
            lit("sl960.email", 14, 6); c.display("]", at: 14, 52, color: 2)
            lit("sl960.late_charges", 15, 6); c.display("]", at: 15, 23, color: 2)
            lit("sl960.min_balance", 15, 31); c.display("]", at: 15, 73, color: 2)
            lit("sl960.late_letters", 16, 6); c.display("]", at: 16, 23, color: 2)
            lit("sl960.max_late", 16, 31); c.display(": [", at: 16, 66, color: 2); c.display("]", at: 16, 73, color: 2)
            lit("sl960.credit_period", 17, 6); c.display("]", at: 17, 24, color: 2)
            lit("sl960.credit_limit", 18, 6); lit("sl960.discount", 18, 29); c.display("]", at: 18, 47, color: 2)
            lit("sl960.unapplied", 19, 6); c.display("}", at: 19, 34, color: 2)
            c.display(String(repeating: "*", count: 19), at: 19, 61, color: 2)
            lit("sl960.current", 20, 6); c.display("}", at: 20, 34, color: 2)
            lit("sl960.escape", 20, 61); c.display("] *", at: 20, 77, color: 2)
            lit("sl960.last_invoice", 21, 6); c.display("}", at: 21, 30, color: 2)
            lit("sl960.esc_b", 21, 61)
            lit("sl960.last_payment", 22, 6); c.display("}", at: 22, 30, color: 2)
            lit("sl960.esc_s", 22, 61)
            lit("sl960.esc_q", 23, 61)
            c.display(String(repeating: "*", count: 19), at: 24, 61, color: 2)
        }
        func n(_ v: Int64, _ d: Int) -> String { Cobol.z(abs(v) % Cobol.pow10(d), d) }
        func fields() -> [ScreenField] {
            func f(_ l: Int, _ col: Int, _ size: Int, _ v: String, _ k: FieldKind = .alpha) -> ScreenField {
                ScreenField(line: l, col: col, size: size, kind: k, value: v, color: 2)
            }
            let da = Cobol.x(deliv.str("deliv-address"), 96)
            return [
                f(6, 22, 30, sales.str("sales-name")), f(7, 22, 48, sales.str("sales-addr1")), f(8, 22, 48, sales.str("sales-addr2")),
                f(9, 22, 30, deliv.str("deliv-name")), f(10, 22, 48, String(da.prefix(48))), f(11, 22, 48, String(da.suffix(48))),
                f(13, 22, 13, sales.str("sales-phone")), f(13, 43, 4, sales.str("sales-ext")), f(13, 57, 13, sales.str("sales-fax")),
                f(14, 22, 30, sales.str("sales-email")),
                f(15, 22, 1, lateCharg), f(15, 69, 4, n(sales.int("sales-late-min"), 4), .numeric),
                f(16, 22, 1, dunLetter), f(16, 69, 4, n(sales.int("sales-late-max"), 4), .numeric),
                f(17, 22, 2, n(sales.int("sales-credit"), 2), .numeric),
                f(18, 22, 7, n(sales.int("sales-limit"), 7), .numeric),
                f(18, 43, 4, n(sales.int("sales-discount"), 4), .numeric),
                f(20, 76, 1, escapeCode),
            ]
        }
        func num(_ f: ScreenField, _ d: Int) -> Int64 { Cobol.moveNumeric(f.value, digits: d, scale: 0) }

        func validateAddress(_ address: String) -> Bool {
            let test = Array(Cobol.x(address, 96).prefix(92))
            var truth = true
            let a = test.filter { $0 == delim }.count
            if a > 4 || a < 1 { truth = false }
            let before = test.firstIndex(of: delim) ?? test.count
            if before > 30 { truth = false }
            return truth
        }
        /// validate-response: (truth, z)
        func validateResponse(_ reply: String) throws -> (Bool, Int64) {
            switch reply.uppercased() {
            case "Y": c.display(" ", at: 2401, eraseEOL: true); return (true, 1)
            case "N": c.display(" ", at: 2401, eraseEOL: true); return (true, 0)
            default:
                try SLB.maps99(s, 18)
                return (false, 0)
            }
        }

        func customerData() throws {
            while true {
                var errorFlag = 0
                let fs = fields()
                try c.acceptScreen(fs)
                sales["sales-name"] = fs[0].value; sales["sales-addr1"] = fs[1].value; sales["sales-addr2"] = fs[2].value
                deliv["deliv-name"] = fs[3].value; deliv["deliv-address"] = fs[4].value + fs[5].value
                sales["sales-phone"] = fs[6].value; sales["sales-ext"] = fs[7].value; sales["sales-fax"] = fs[8].value
                sales["sales-email"] = fs[9].value
                lateCharg = fs[10].value; sales.setInt("sales-late-min", num(fs[11], 4))
                dunLetter = fs[12].value; sales.setInt("sales-late-max", num(fs[13], 4))
                sales.setInt("sales-credit", num(fs[14], 2)); sales.setInt("sales-limit", num(fs[15], 7))
                sales.setInt("sales-discount", num(fs[16], 4))
                escapeCode = fs[17].value

                if !validateAddress(sales.str("sales-addr1") + sales.str("sales-addr2")) {
                    c.display(s.t("sl960.addr_err"), at: 771, color: 4)
                    errorFlag = 1
                } else { c.display(String(repeating: " ", count: 10), at: 771) }
                if deliv.str("deliv-name") == Cobol.x("", 30) {
                    sales.setInt("delivery-tag", 0)
                } else {
                    if !validateAddress(deliv.str("deliv-address")) {
                        c.display(s.t("sl960.addr_err"), at: 1071, color: 4)
                        errorFlag = 1
                    } else { c.display(String(repeating: " ", count: 10), at: 1071) }
                    sales.setInt("delivery-tag", 1)
                }
                // bypass-deliv-test
                let (t1, z1) = try validateResponse(lateCharg)
                if t1 {
                    sales.setInt("sales-late", z1)
                    c.display(String(repeating: " ", count: 7), at: 1524)
                } else {
                    c.display(s.t("sl960.error"), at: 1524, color: 4)
                    errorFlag = 1
                }
                let (t2, z2) = try validateResponse(dunLetter)
                if t2 {
                    c.display(String(repeating: " ", count: 7), at: 1624)
                    sales.setInt("sales-dunning", z2)
                } else {
                    c.display(s.t("sl960.error"), at: 1624, color: 4)
                    continue
                }
                if errorFlag != 0 { continue }
                return
            }
        }

        // setup-customers
        while true {   // customer-input
            literals()
            c.displayFields(fields())
            var nos = Cobol.x("", 6)
            var accepted = false
            while true {   // customer-accept
                nos = Cobol.x(try c.accept(at: 422, size: 6, initial: nos, options: [.update], color: 3), 6)
                if nos == Cobol.x("", 6) { return }
                nos = nos.uppercased()
                c.display(nos, at: 422, color: 3)
                c.display(" ", at: 2301, eraseEOL: true)
                var digit = 0
                if maps09(nos, checkDigit: &digit, reply: "C") != "Y" { break }
                sales.setRaw("sales-key", SJIS.encode(nos + String(digit), size: 7))
                c.display(String(digit), at: 444, color: 3)
                let key = sales.raw("sales-key")
                if let r = salesFile.read(key: key) {
                    sales = r
                    try SLB.maps99(s, 5)
                    continue
                }
                // customer-details
                sales = Record(SLB.salesLayout); deliv = Record(SLB.deliveryLayout)
                sales.setRaw("sales-key", key)
                sales.setInt("sales-late", s.sys.int("sl-charges"))
                sales.setInt("sales-dunning", s.sys.int("sl-dunning"))
                sales.setInt("sales-credit", s.sys.int("sl-credit"))
                sales.setInt("sales-discount", s.sys.int("sl-disc"))
                sales.setInt("sales-late-min", s.sys.int("sl-min"))
                sales.setInt("sales-late-max", s.sys.int("sl-max"))
                sales.setInt("sales-limit", s.sys.int("sl-limit"))
                sales.setInt("sales-create-date", s.sys.int("run-date"))
                sales.setInt("sales-status", 1)
                accepted = true
                break
            }
            if accepted { break }
        }
        while true {   // get-details
            try customerData()
            escapeCode = "S"
            c.display(escapeCode, at: 2076, color: 6)
            repeat {
                escapeCode = try c.accept(at: 2076, size: 1, initial: escapeCode, options: [.update], color: 6).uppercased()
            } while escapeCode != "B" && escapeCode != "S" && escapeCode != "Q"
            if escapeCode == "B" { continue }
            break
        }
        if escapeCode == "Q" { return }
        _ = salesFile.write(sales)
        if sales.int("delivery-tag") != 0 {
            deliv["deliv-key"] = "D" + sales.str("sales-key")
            _ = delivery.write(deliv)
        }
    }
}
