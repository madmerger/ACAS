import Foundation

/// sales/sl085.cbl: Payment Data Amend (入金訂正)
enum SLA085 {
    static let progName = "SL085 (3.01.06)"

    final class WS {
        var amtScreen = Array("0000000.00")
        var amtDigits = Array("000000000")
        /// ws-amount-screen-display2 (999 "." v99)
        var amtScreen2 = Array("000.00")
        var amtDigits2 = Array("00000")
        var work1: Int64 = 0
        var displayN: Int64 = 0
        var siDeductAmt: Int64 = 0
        var k: Int64 = 0
        var appropAmount: Int64 = 0
        var payCustomer = SLA.spaces(7)
        var payDate: Int64 = 0
        var payValue: Int64 = 0, holdPay: Int64 = 0
        var transactionType: Int64 = 0
        var saveCustomer = SLA.spaces(7)
        var lin = 0, cole = 0
        var oi: Record = { var r = Record(SLA.oiLayout); SLA.initialize(&r); return r }()
        var sales = Record(SLA.salesLayout, bytes: [UInt8](repeating: 0, count: 300))
        var salesFile: IndexedFile!, oi3: IndexedFile!
        var amtOk: Int64 {
            get { amtDigits.reduce(Int64(0)) { $0 * 10 + Int64(($1.asciiValue ?? 0) & 0x0f) % 10 } }
            set { amtDigits = Array(Cobol.z(newValue, 9)) }
        }
        var amtOk2: Int64 { amtDigits2.reduce(Int64(0)) { $0 * 10 + Int64(($1.asciiValue ?? 0) & 0x0f) % 10 } }
    }

    static func m8(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 8, signed: true) }
    static func m9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9, signed: true) }

    /// PIC -(5)9.99 (浮動マイナス)
    static func floatMinus(_ v: Int64) -> String {
        let a = abs(v) % 10_000_000
        let body = (v < 0 ? "-" : "") + "\(a / 100)." + Cobol.z(a % 100, 2)
        return String(repeating: " ", count: max(9 - body.count, 0)) + body
    }

    static func run(_ s: Session) throws {
        let w = WS()
        if s.sys.int("s-flag-p") == 0 {
            try SLA.maps99(s, 30)
            try SLA.maps99(s, 15)
            return
        }
        displayHeads(s)
        w.k = 0
        w.salesFile = SLA.salesFile(s); w.oi3 = SLA.openItemFile3(s)
        _ = w.salesFile.open(); _ = w.oi3.open()
        try newPayment(s, w)
        w.salesFile.close(); w.oi3.close()
        s.sys["oi-3-flag"] = "Y"
        displayHeads(s)
    }

    static func displayHeads(_ s: Session) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 202, color: 2)
        c.display(s.t("sl085.title"), at: 233, color: 2)
        c.display(SLA.convertDate(s), at: 271, color: 2)
    }

    // MARK: new-payment section

    static func newPayment(_ s: Session, _ w: WS) throws {
        let c = s.console
        let stars = String(repeating: "*", count: 40)
        newPayment: while true {
            w.lin = 4
            displayHeads(s)
            c.display(stars, at: 441, color: 2)
            c.display(s.t("sl085.box1"), at: 541, color: 2)
            c.display(s.t("sl085.box2"), at: 641, color: 2)
            c.display(s.t("sl085.box3"), at: 741, color: 2)
            c.display(stars, at: 841, color: 2)
            c.display(SLA.convertDate(s), at: 551, color: 3)
            getBatch: while true {
                let cust = Cobol.x(try c.accept(at: 654, size: 7, color: 3).uppercased(), 7)
                c.display(cust, at: 654, color: 3)
                if cust == SLA.spaces(7) { return }
                // customer-input
                while true {
                    w.displayN = Cobol.moveNumeric(try c.accept(at: 770, size: 5, kind: .numeric, initial: "00000", options: [.update], color: 3), digits: 5, scale: 0)
                    if w.displayN == 0 { return }
                    w.k = Cobol.moveNumeric(try c.accept(at: 776, size: 3, kind: .numeric, initial: Cobol.z(w.k, 3), options: [.update], color: 3), digits: 3, scale: 0)
                    if w.k != 0 { break }
                }
                let saveInvoice = w.displayN * 1000 + w.k
                w.saveCustomer = cust
                _ = w.oi3.start(notLessThan: SLA.oiKey(cust, saveInvoice))
                var found = false
                while let rec = w.oi3.readNext() {
                    w.oi = rec
                    if w.oi.str("oi-customer") != w.saveCustomer || w.oi.int("oi-invoice") != saveInvoice { break }
                    let type = w.oi.int("oi-type")
                    if w.oi.int("oi-b-nos") != w.displayN || w.oi.int("oi-b-item") != w.k || (type != 5 && type != 6) { continue }
                    found = true
                    break
                }
                if !found { continue getBatch }
                if w.oi.int("oi-type") == 6 { c.display(s.t("sl085.warning_unapplied"), at: 645, color: 2) }
                w.transactionType = w.oi.int("oi-type")
                w.payCustomer = w.oi.str("oi-customer")
                w.payDate = w.oi.int("oi-date")
                w.payValue = m8(w.oi.int("oi-paid")); w.holdPay = w.payValue
                w.appropAmount = m8(w.oi.int("oi-net"))
                c.display(w.payCustomer, at: 572, color: 2)
                // read sales-file invalid key (レコード領域は前のまま)
                if let sr = w.salesFile.read(key: SJIS.encode(w.payCustomer, size: 7)) { w.sales = sr }
                let address = Array(w.sales.str("sales-addr1") + w.sales.str("sales-addr2"))
                c.display(w.sales.str("sales-name"), at: 401, color: 2)
                let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
                var ptr = 1
                for i in 0..<4 {
                    var part = ""
                    if ptr >= 1 && ptr <= address.count {
                        var j = ptr - 1
                        if i < 3 {
                            while j < address.count && address[j] != delim { part.append(address[j]); j += 1 }
                            ptr = j < address.count ? j + 2 : j + 1
                        } else {
                            while j < address.count && part.count < 36 { part.append(address[j]); j += 1 }
                            ptr = j + 1
                        }
                    }
                    c.display(Cobol.x(part, 36), at: 5 + i, 1, color: 2)
                }
                c.display(s.t("sl085.current_balance"), at: 1001, color: 2)
                c.display(Pic.edit("z(5)9.99cr", value: w.sales.int("sales-current"), scale: 2), at: 1019, color: 2)
                // value-input
                valueInput: while true {
                    w.amtOk = Cobol.truncate(abs(w.payValue), digits: 9, signed: false)
                    w.lin = 7; w.cole = 51
                    try acceptMoney2(s, w)
                    w.payValue = m8(w.amtOk)
                    if w.payValue == w.oi.int("oi-paid") {
                        c.display(s.t("sl085.confirm"), at: 1201, color: 2)
                        while true {
                            let reply = try c.accept(at: 1251, size: 1, color: 6).uppercased()
                            if reply == "Y" { continue newPayment }
                            if reply == "N" { break }
                        }
                    }
                    // value-input-2
                    if w.payValue != 0 {
                        c.display(s.t("sl085.sl140"), at: 1201, eraseEOL: true)
                        continue valueInput
                    }
                    break
                }
                _ = w.oi3.delete(key: Array(w.oi.bytes[0..<11]))
                if w.oi.int("oi-net") != 0 {
                    w.siDeductAmt = w.oi.int("oi-deduct-amt")
                    try paymentAppropriate(s, w)
                }
                // skip-pay-approp
                if w.transactionType == 6 {
                    w.sales.setInt("sales-unapplied", Cobol.truncate(w.sales.int("sales-unapplied") + w.holdPay, digits: 10, signed: true))
                    _ = w.salesFile.rewrite(w.sales)
                }
                w.lin = 14; w.cole = 1
                c.display(" ", at: w.lin, w.cole, eraseEOS: true)
                c.display(s.t("sl085.further"), at: 1629, color: 2)
                while true {
                    let reply = try c.accept(at: 1663, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                    if reply == "Y" { continue newPayment }
                    if reply == "N" { return }
                }
            }
        }
    }

    /// accept-money (控除額 999.99 用)
    static func acceptMoney(_ s: Session, _ w: WS) throws {
        let c = s.console
        w.amtDigits2 = Array("00000")
        w.amtScreen2.replaceSubrange(0..<3, with: Array("000"))
        w.amtScreen2.replaceSubrange(4..<6, with: Array("00"))
        c.display(String(w.amtScreen2), at: w.lin, w.cole, color: 2)
        w.amtScreen2 = Array(Cobol.x(try c.accept(at: w.lin, w.cole, size: 6, initial: String(w.amtScreen2), options: [.update], color: 2), 6))
        w.amtDigits2 = Array(w.amtScreen2[0..<3]) + Array(w.amtScreen2[4..<6])
    }

    static func acceptMoney2(_ s: Session, _ w: WS) throws {
        let c = s.console
        w.amtScreen.replaceSubrange(8..<10, with: w.amtDigits[7..<9])
        w.amtScreen.replaceSubrange(0..<7, with: w.amtDigits[0..<7])
        c.display(String(w.amtScreen), at: w.lin, w.cole, color: 3)
        w.amtScreen = Array(Cobol.x(try c.accept(at: w.lin, w.cole, size: 10, initial: String(w.amtScreen), options: [.update], color: 3), 10))
        w.amtDigits = Array(w.amtScreen[0..<7]) + Array(w.amtScreen[8..<10])
    }

    // MARK: payment-appropriate section

    static func paymentAppropriate(_ s: Session, _ w: WS) throws {
        let c = s.console
        c.display(s.t("sl085.reversing"), at: 1101, color: 2)
        _ = w.oi3.start(notLessThan: SLA.oiKey(w.saveCustomer, 0))
        while let rec = w.oi3.readNext() {
            w.oi = rec
            if w.oi.int("oi-type") != 2 { continue }
            if w.oi.str("oi-customer") != w.payCustomer { break }
            if w.oi.int("oi-b-nos") != w.displayN || w.oi.int("oi-b-item") != w.k { continue }
            // divide oi-cr by 100 giving work-1 (oi-cr は入金額 × 100 の整数)
            w.work1 = m8(w.oi.int("oi-cr"))
            w.oi.setInt("oi-paid", m9(w.oi.int("oi-paid") - w.work1))
            w.oi.setInt("oi-p-c", m9(w.oi.int("oi-p-c") - w.work1))
            w.appropAmount = m8(w.appropAmount - w.work1)
            for f in ["oi-b-nos", "oi-b-item", "oi-cr", "oi-status"] { w.oi.setInt(f, 0) }
            if !(w.siDeductAmt == 0 || w.oi.int("oi-deduct-amt") != 0) {
                while true {
                    let a = abs(w.siDeductAmt) % 100_000
                    let siDisplay = (w.siDeductAmt < 0 ? "-" : " ") + Pic.edit("zz9.99", value: a, scale: 2)
                    c.display(s.t("sl085.for_invoice"), at: 1301, color: 2)
                    c.display(Pic.edit("z(7)9", value: Cobol.truncate(w.oi.int("oi-invoice"), digits: 8, signed: false), scale: 0), at: 1317, color: 2)
                    c.display(s.t("sl085.enter_deduct"), at: 1201, color: 2)
                    c.display(s.t("sl085.available"), at: 1240, color: 2)
                    c.display(siDisplay, at: 1259, color: 3)
                    w.lin = 12; w.cole = 24
                    try acceptMoney(s, w)
                    w.oi.setInt("oi-deduct-amt", w.amtOk2)
                    if w.oi.int("oi-deduct-amt") > w.siDeductAmt { continue }
                    w.siDeductAmt -= w.oi.int("oi-deduct-amt")
                    break
                }
                c.display(" ", at: 1201, eraseEOL: true)
                c.display(" ", at: 1301, eraseEOL: true)
            }
            _ = w.oi3.rewrite(w.oi)
            if w.appropAmount == 0 && w.siDeductAmt == 0 { break }
        }
        if w.appropAmount != 0 || w.siDeductAmt != 0 {
            c.display(s.t("sl085.sl141"), at: 1201, color: 4)
            c.display(floatMinus(w.appropAmount), at: 1304, color: 2)
            c.display(Pic.edit("z(5)9.99cr", value: w.siDeductAmt, scale: 2), at: 1317, color: 2)
            c.display(s.t("sl085.sl003"), at: 1331, color: 4)
            _ = try c.accept(at: 1354, size: 1, color: 2)
        }
    }
}
