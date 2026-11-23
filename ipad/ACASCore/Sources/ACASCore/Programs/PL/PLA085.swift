import Foundation

/// purchase/pl085.cbl: 支払修正 (Payment Data Amend)
final class PLA085 {
    static let progName = "PL085 (3.01.02)"
    static func run(_ s: Session) throws { try PLA085(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, oi5: IndexedFile
    var purch = PLA.fdArea(PLA.purchLayout)
    var oi = Record(PLA.oiLayout)
    /// ws-amount-screen-display (10 バイト) / -display2 (6 バイト)。accept 側の再定義は小数点を含まない (レガシーの癖)。
    var scr = Array("0000000.00".utf8), scr2 = Array("000.00".utf8)
    var amtOk: Int64 = 0, amtOk2: Int64 = 0
    var wsReply = " "
    var k: Int64 = 0, displayN: Int64 = 0
    var appropAmount: Int64 = 0, payValue: Int64 = 0, holdPay: Int64 = 0, siDeductAmt: Int64 = 0
    var payCustomer = "", saveSupplier = ""
    var transactionType: Int64 = 0

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); oi5 = PLA.openItem5(s)
    }

    func oi5Key(_ supplier: String, _ invoice: Int64) -> [UInt8] {
        var r = Record(PLA.oiLayout)
        r.set("oi-supplier", supplier); r.setInt("oi-invoice", invoice)
        return Array(r.bytes[0..<11])
    }
    /// accept-money2
    func acceptMoney2(_ line: Int, _ col: Int) throws {
        let d = Array(Cobol.z(abs(amtOk) % 1_000_000_000, 9).utf8)
        for i in 0..<9 { scr[i] = d[i] }
        c.display(PLA.shown(scr), at: line, col, color: 3)
        let a = Array(try c.accept(at: line, col, size: 9, initial: String(PLA.shown(scr).prefix(9)), options: [.update], color: 3).utf8)
        for i in 0..<9 where i < a.count { scr[i] = a[i] }
        amtOk = (0..<9).reduce(Int64(0)) { $0 * 10 + Int64(scr[$1] & 0x0F) }
    }
    /// accept-money
    func acceptMoney(_ line: Int, _ col: Int) throws {
        for i in [0, 1, 2, 4, 5] { scr2[i] = 0x30 }
        c.display(PLA.shown(scr2), at: line, col, color: 3)
        let a = Array(try c.accept(at: line, col, size: 5, initial: String(PLA.shown(scr2).prefix(5)), options: [.update], color: 3).utf8)
        for i in 0..<5 where i < a.count { scr2[i] = a[i] }
        amtOk2 = (0..<5).reduce(Int64(0)) { $0 * 10 + Int64(scr2[$1] & 0x0F) }
    }

    func displayHeads() {
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA085.progName, at: 101, color: 2)
        c.display(s.t("pl085.title"), at: 133, color: 2)
        c.display(PLA.toDayDisplay(s), at: 171, color: 2)
    }

    func main() throws {
        if s.sys.int("p-flag-p") == 0 {
            try PLA.maps99(s, 30)
            try PLA.maps99(s, 15)
            return
        }
        displayHeads()
        k = 0
        _ = purchase.open(); _ = oi5.open()
        try newPayment()
        purchase.close(); oi5.close()
        s.sys.set("oi-5-flag", "Y")
        displayHeads()
    }

    // MARK: new-payment section

    func newPayment() throws {
        payment: while true {
            displayHeads()
            c.display("****************************************", at: 441, color: 2)
            c.display(s.t("pl085.box_date"), at: 541, color: 2)
            c.display("***                                  ***", at: 641, color: 2)
            c.display(s.t("pl085.box_value"), at: 741, color: 2)
            c.display("****************************************", at: 841, color: 2)
            c.display(PLA.toDayDisplay(s), at: 549, color: 3)
            batch: while true {
                // get-batch
                let sup = try c.accept(at: 572, size: 7, initial: "", options: [.update], color: 3).uppercased()
                c.display(sup, at: 572, color: 3)
                if Cobol.rtrim(sup).isEmpty { return }
                customer: while true {
                    displayN = Int64(try c.accept(at: 770, size: 5, kind: .numeric, initial: "00000", options: [.update], color: 3)) ?? 0
                    if displayN == 0 { return }
                    k = Int64(try c.accept(at: 776, size: 3, kind: .numeric, initial: Cobol.z(k, 3), options: [.update], color: 3)) ?? 0
                    if k == 0 { continue customer }
                    break
                }
                let saveInvoice = displayN * 1000 + k
                saveSupplier = sup
                _ = oi5.start(notLessThan: oi5Key(sup, saveInvoice))
                var found = false
                while let rec = oi5.readNext() {
                    oi = rec
                    if oi.str("oi-supplier") != saveSupplier || oi.int("oi-invoice") != saveInvoice { break }
                    if oi.int("oi-b-nos") != displayN || oi.int("oi-b-item") != k || (oi.int("oi-type") != 5 && oi.int("oi-type") != 6) { continue }
                    found = true
                    break
                }
                if found { break batch }
            }
            if oi.int("oi-type") == 6 {
                c.display(s.t("pl085.warning_unapplied"), at: 645, color: 2)
                transactionType = oi.int("oi-type")
            }
            payCustomer = oi.str("oi-supplier")
            payValue = oi.int("oi-paid"); holdPay = oi.int("oi-paid")
            appropAmount = oi.int("oi-approp")
            c.display(payCustomer, at: 572, color: 3)
            purch.set("purch-key", payCustomer)
            if let pr = purchase.read(key: payCustomer) { purch = pr }
            c.display(PLA.shown(purch.raw("purch-name")), at: 401, color: 3)
            var a = 1
            let addr = Array(PLA.shown(purch.raw("purch-address")))
            let delim = s.sys.str("pl-delim").first ?? " "
            for l in [5, 6, 7] { c.display(PLA.unstring(addr, delim: delim, pointer: &a, size: 36), at: l, 1, color: 3) }
            var last = Cobol.x("", 36)
            if a >= 1 && a <= addr.count { last = Cobol.x(String(addr[(a - 1)..<min(addr.count, a - 1 + 36)]), 36) }
            c.display(last, at: 801, color: 3)
            c.display(s.t("pl085.current_balance"), at: 1001, color: 2)
            c.display(PLA.cr("z(5)9.99cr", purch.int("purch-current"), int: 6), at: 1019, color: 3)
            value: while true {
                amtOk = payValue
                try acceptMoney2(7, 49)
                payValue = amtOk
                if payValue == oi.int("oi-paid") {
                    c.display(s.t("pl085.confirm_no_action"), at: 1201, color: 2)
                    while true {
                        wsReply = try c.accept(at: 1251, size: 1, color: 2).uppercased()
                        if wsReply == "Y" { continue payment }
                        if wsReply == "N" { break }
                    }
                }
                // value-input-2
                if payValue != 0 {
                    c.display(s.t("pl085.pl140"), at: 1201, color: 2, eraseEOL: true)
                    continue value
                }
                break
            }
            oi5.delete(key: Array(oi.bytes[0..<11]))
            if oi.int("oi-approp") != 0 {
                siDeductAmt = oi.int("oi-deduct-amt")
                try paymentAppropriate()
            }
            if transactionType == 6 {
                purch.setInt("purch-unapplied", Cobol.truncate(purch.int("purch-unapplied") + holdPay, digits: 10))
                purchase.rewrite(purch)
            }
            c.display(" ", at: 14, 1, eraseEOS: true)
            c.display(s.t("pl085.further"), at: 1629, color: 2)
            while true {
                wsReply = try c.accept(at: 1663, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if wsReply == "Y" { continue payment }
                if wsReply == "N" { return }
            }
        }
    }

    // MARK: payment-appropriate section

    func paymentAppropriate() throws {
        c.display(s.t("pl085.reversing"), at: 1101, color: 2)
        _ = oi5.start(notLessThan: oi5Key(saveSupplier, 0))
        while let rec = oi5.readNext() {
            oi = rec
            if oi.int("oi-type") != 2 { continue }
            if oi.str("oi-supplier") != payCustomer { break }
            if oi.int("oi-b-nos") != displayN || oi.int("oi-b-item") != k { continue }
            // oi-cr は支払額 × 100 (整数) で保持されている
            let work1 = Cobol.truncate(oi.int("oi-cr"), digits: 8)
            oi.setInt("oi-paid", Cobol.truncate(oi.int("oi-paid") - work1, digits: 9))
            oi.setInt("oi-p-c", Cobol.truncate(oi.int("oi-p-c") - work1, digits: 9))
            appropAmount = Cobol.truncate(appropAmount - work1, digits: 8)
            for f in ["oi-b-nos", "oi-b-item", "oi-cr", "oi-status"] { oi.setInt(f, 0) }
            if siDeductAmt != 0 && oi.int("oi-deduct-amt") == 0 {
                while true {
                    // get-deduct
                    c.display(s.t("pl085.for_folio"), at: 1301, color: 2)
                    let inv = oi.int("oi-invoice")
                    c.display((inv < 0 ? "-" : "+") + Cobol.z(abs(inv), 10), at: 1317, color: 3)
                    c.display(s.t("pl085.enter_deduct"), at: 1201, color: 2)
                    c.display(s.t("pl085.amount_available"), at: 1240, color: 2)
                    c.display(Pic.edit("-zz9.99", value: siDeductAmt, scale: 2), at: 1259, color: 3)
                    try acceptMoney(12, 24)
                    oi.setInt("oi-deduct-amt", amtOk2)
                    if oi.int("oi-deduct-amt") > siDeductAmt { continue }
                    oi.setInt("oi-net", Cobol.truncate(oi.int("oi-net") + oi.int("oi-deduct-amt"), digits: 9))
                    siDeductAmt -= oi.int("oi-deduct-amt")
                    break
                }
                c.display(" ", at: 1201, eraseEOL: true)
                c.display(" ", at: 1301, eraseEOL: true)
            }
            oi5.rewrite(oi)
            if appropAmount == 0 && siDeductAmt == 0 { break }
        }
        if appropAmount != 0 || siDeductAmt != 0 {
            c.display(s.t("pl085.pl141"), at: 1201, color: 2)
            c.display(Pic.edit("-(5)9.99", value: appropAmount, scale: 2), at: 1304, color: 3)
            c.display(PLA.cr("z(5)9.99cr", siDeductAmt, int: 6), at: 1317, color: 3)
            c.display(s.t("pl085.pl003"), at: 1401, color: 2)
            wsReply = try c.accept(at: 1430, size: 1, color: 2)
        }
    }
}
