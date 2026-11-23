import Foundation

/// purchase/pl080.cbl: 支払入力・消込 (Payment Data Entry)
final class PLA080 {
    static let progName = "PL080 (3.01.04)"
    static func run(_ s: Session) throws { try PLA080(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, oi5: IndexedFile
    var purch = PLA.fdArea(PLA.purchLayout)
    var oi = Record(PLA.oiLayout)
    /// ws-amount-screen-display (10 バイト)。ws-amount-screen-accept は 9(7) + v99 の 9 バイトで再定義されており、
    /// 小数点の位置が入力値で上書きされる (レガシーの癖)。
    var scr = Array("0000000.00".utf8)
    var amtOk: Int64 = 0
    var wsReply = " "
    var toDay = ""
    var k = 0
    var lin = 0
    var appropAmount: Int64 = 0, deductTaken: Int64 = 0
    var payCustomer = "", payDate: Int64 = 0, payValue: Int64 = 0, batchValue: Int64 = 0
    var transactionType: Int64 = 0
    var crt: Int { c.crtStatus }

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); oi5 = PLA.openItem5(s)
        toDay = s.toDay
    }

    func u9(_ v: Int64) -> Int64 { abs(v) % 1_000_000_000 }
    func shownScr() -> String { PLA.shown(scr) }
    func amtFromScr() -> Int64 { (0..<9).reduce(Int64(0)) { $0 * 10 + Int64(scr[$1] & 0x0F) } }
    func amtToScr(_ v: Int64) {
        let d = Array(Cobol.z(u9(v), 9).utf8)
        for i in 0..<9 { scr[i] = d[i] }
    }
    func acceptScr(_ line: Int, _ col: Int, color: UInt8) throws {
        c.display(shownScr(), at: line, col, color: 2)
        let a = Array(try c.accept(at: line, col, size: 9, initial: String(shownScr().prefix(9)), options: [.update], color: color).utf8)
        for i in 0..<9 where i < a.count { scr[i] = a[i] }
        amtOk = amtFromScr()
    }
    /// accept-money
    func acceptMoney(_ line: Int, _ col: Int) throws {
        for i in 0..<7 { scr[i] = 0x30 }
        scr[8] = 0x30; scr[9] = 0x30
        amtOk = 0
        try acceptScr(line, col, color: 3)
    }
    /// accept-money2
    func acceptMoney2(_ line: Int, _ col: Int) throws {
        amtToScr(amtOk)
        try acceptScr(line, col, color: 2)
    }
    func localDate() -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, toDay)
    }

    func displayHeads() {
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA080.progName, at: 101, color: 2)
        c.display(s.t("pl080.title"), at: 133, color: 2)
        c.display(localDate(), at: 171, color: 2)
    }

    func main() throws {
        if s.sys.int("p-flag-i") == 1 {
            try PLA.maps99(s, 28)
            try PLA.maps99(s, 15)
            return
        }
        displayHeads()
        k = 0
        _ = purchase.open(); _ = oi5.open()
        try newPayment()
        purchase.close(); oi5.close()
        displayHeads()
        s.sys.setInt("bl-next-batch", s.sys.int("bl-next-batch") + 1)
        s.sys.set("oi-5-flag", "Y")
    }

    // MARK: new-payment section

    func newPayment() throws {
        payment: while true {
            lin = 4
            displayHeads()
            c.display("****************************************", at: 441, color: 2)
            c.display(s.t("pl080.box_date"), at: 541, color: 2)
            c.display("***                                  ***", at: 641, color: 2)
            c.display(s.t("pl080.box_value"), at: 741, color: 2)
            c.display("****************************************", at: 841, color: 2)
            date: while true {
                var wsDate = localDate()
                c.display(wsDate, at: 549, color: 3)
                wsDate = try c.accept(at: 549, size: 10, initial: wsDate, options: [.update], color: 3)
                if Cobol.rtrim(wsDate).isEmpty || crt == 2005 { return }
                let v = PLA.validateDate(s, wsDate)
                if v.bin == 0 { continue date }
                payDate = Int64(v.bin)
                toDay = Maps04.normalized(v.uk)
                customer: while true {
                    if k == 999 {
                        c.display(s.t("pl080.batch_full"), at: 1041, color: 2)
                        return
                    }
                    payCustomer = try c.accept(at: 572, size: 7, color: 3).uppercased()
                    c.display(payCustomer, at: 572, color: 3)
                    if Cobol.rtrim(payCustomer).isEmpty { continue date }
                    if crt == 2005 { return }
                    purch.set("purch-key", payCustomer)
                    guard let pr = purchase.read(key: payCustomer) else { continue customer }
                    purch = pr
                    c.display(purch.str("purch-name"), at: 401, color: 3)
                    var z = 1
                    let addr = Array(purch.str("purch-address"))
                    let delim = s.sys.str("pl-delim").first ?? " "
                    for l in [5, 6, 7] { c.display(PLA.unstring(addr, delim: delim, pointer: &z, size: 36), at: l, 1, color: 3) }
                    var last = Cobol.x("", 36)
                    if z >= 1 && z <= addr.count { last = Cobol.x(String(addr[(z - 1)..<min(addr.count, z - 1 + 36)]), 36) }
                    c.display(last, at: 801, color: 3)
                    c.display(s.t("pl080.current_balance"), at: 1001, color: 2)
                    c.display(PLA.cr("z(6)9.99cr", purch.int("purch-current"), int: 7), at: 1019, color: 3)
                    transactionType = 5
                    var unapplied = false
                    if purch.int("purch-unapplied") != 0 {
                        amtOk = u9(purch.int("purch-unapplied"))
                        c.display(s.t("pl080.unapplied_balance"), at: 645, color: 2)
                        c.display(PLA.ed("z(6)9.99", purch.int("purch-unapplied"), int: 7), at: 665, color: 3)
                        c.display(s.t("pl080.allocate_unapplied"), at: 1601, color: 2)
                        wsReply = "Y"
                        repeat {
                            c.crtStatus = 0
                            wsReply = try c.accept(at: 1666, size: 1, initial: wsReply, options: [.update], color: 6)
                            if crt == 2005 { continue payment }
                            wsReply = wsReply.uppercased()
                        } while wsReply != "Y" && wsReply != "N"
                        c.display(" ", at: 1601, eraseEOL: true)
                        if wsReply == "Y" {
                            transactionType = 6
                            repeat {
                                try acceptMoney2(7, 49)
                                if amtOk == 0 { continue payment }
                            } while amtOk > purch.int("purch-unapplied")
                            purch.setInt("purch-unapplied", purch.int("purch-unapplied") - amtOk)
                            payValue = amtOk
                            purchase.rewrite(purch)
                            unapplied = true
                        }
                    }
                    if !unapplied {
                        // value-input
                        try acceptMoney(7, 49)
                        payValue = amtOk
                        if payValue == 0 { continue customer }
                        if crt == 2005 { return }
                        s.sys.setInt("p-flag-p", 1)
                        batchValue = u9(batchValue + payValue)
                        c.display(s.t("pl080.batch_total"), at: 1041, color: 2)
                        c.display(PLA.cr("z(6)9.99cr", batchValue, int: 7), at: 1055, color: 3)
                    }
                    break date
                }
            }
            // set-batch-item
            if s.sys.int("bl-next-batch") == 0 { s.sys.setInt("bl-next-batch", 1) }
            k += 1
            c.display(Pic.edit("z(4)9", value: abs(s.sys.int("bl-next-batch")) % 100_000, scale: 0), at: 770, color: 2)
            c.display(Cobol.z(k % 1000, 3), at: 776, color: 2)
            try paymentAppropriate()
            lin = 14
            c.display(" ", at: lin, 1, eraseEOS: true)
            c.display(s.t("pl080.further"), at: 1629, color: 2)
            while true {
                wsReply = try c.accept(at: 1661, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if wsReply == "Y" { continue payment }
                if wsReply == "N" { return }
            }
        }
    }

    // MARK: payment-appropriate section

    func oi5Key(_ supplier: String, _ invoice: Int64) -> [UInt8] {
        var r = Record(PLA.oiLayout)
        r.set("oi-supplier", supplier); r.setInt("oi-invoice", invoice)
        return Array(r.bytes[0..<11])
    }

    func paymentAppropriate() throws {
        c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
        c.display(s.t("pl080.col_1"), at: 1201, color: 2)
        c.display(s.t("pl080.col_2"), at: 1233, color: 2)
        c.display(s.t("pl080.col_3"), at: 1258, color: 2)
        appropAmount = 0
        lin = 14
        _ = oi5.start(notLessThan: oi5Key(payCustomer, 0))
        payLoop: while let rec = oi5.readNext() {
            oi = rec
            if oi.int("oi-type") != 2 { continue }
            if oi.str("oi-supplier") != payCustomer { break }
            if oi.int("oi-b-nos") != 0 { continue }
            var workNet = Cobol.truncate(oi.int("oi-net") + oi.int("oi-carriage") + oi.int("oi-vat") + oi.int("oi-c-vat"), digits: 9)
            let workDed = abs(oi.int("oi-deduct-amt")) % 100_000
            if workNet == oi.int("oi-paid") && oi.int("oi-status") == 0 {
                oi.setInt("oi-date-cleared", payDate)
                oi.setInt("oi-status", 1)
                oi5.rewrite(oi)
                continue
            }
            if workNet <= oi.int("oi-paid") { continue }
            details: while true {
                // pay-details
                c.display(" ", at: lin, 1, eraseEOL: true)
                c.display(Pic.edit("z(7)9", value: abs(oi.int("oi-invoice")) % 100_000_000, scale: 0), at: lin, 1, color: 3)
                c.display(Maps04.toDate(Int(oi.int("oi-date"))), at: lin, 11, color: 3)
                var work1 = u9(workNet)
                let work2 = workDed
                let uBin = oi.int("oi-date") + 1 + oi.int("oi-deduct-days")
                var display5: Int64 = 0
                if uBin > payDate {
                    work1 = u9(work1 - work2)
                    display5 = work2
                }
                work1 = u9(work1 - oi.int("oi-paid"))
                var payPaid = work1
                c.display(PLA.ed("z(6)9.99", work1, int: 7), at: lin, 21, color: 3)
                c.display(PLA.ed("zz9.99", display5, int: 3), at: lin, 35, color: 3)
                if payPaid == 0 { c.display(s.t("pl080.fully_paid"), at: lin, 65, color: 2) }
                else { c.display(" ", at: lin, 65, eraseEOL: true) }
                if payPaid > payValue { payPaid = Cobol.truncate(payValue - appropAmount, digits: 9) }
                amtOk = u9(payPaid)
                try acceptMoney2(lin, 46)
                payPaid = amtOk
                if payPaid == 0 {
                    c.display(PLA.cr("z(6)9.99cr", 0, int: 7), at: lin, 46, color: 3)
                    c.display(s.t("pl080.no_change"), at: lin, 65, color: 2)
                } else {
                    oi.setInt("oi-b-nos", abs(s.sys.int("bl-next-batch")) % 100_000)
                    oi.setInt("oi-b-item", Int64(k))
                    // get-agreement
                    appropAmount = abs(appropAmount + payPaid) % 100_000_000
                    var tooHigh = appropAmount > payValue
                    func clear(takeDeduct: Bool) {
                        oi.setInt("oi-date-cleared", payDate)
                        oi.setInt("oi-status", 1)
                        if takeDeduct {
                            oi.setInt("oi-net", Cobol.truncate(oi.int("oi-net") - oi.int("oi-deduct-amt"), digits: 9))
                            oi.setInt("oi-deduct-amt", 0)
                            deductTaken = abs(deductTaken + work2) % 100_000_000
                        }
                    }
                    if !tooHigh {
                        if payPaid == work1 {
                            clear(takeDeduct: uBin > payDate)
                        } else {
                            if uBin <= payDate { work1 = u9(work1 - work2) }
                            if payPaid > work1 {
                                tooHigh = true
                            } else if payPaid == work1 {
                                c.display("Y", at: lin, 65, color: 6)
                                wsReply = try c.accept(at: lin, 65, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                                if wsReply == "Y" { clear(takeDeduct: true) }
                            }
                        }
                    }
                    if tooHigh {
                        // payment-2-high
                        appropAmount = abs(appropAmount - payPaid) % 100_000_000
                        c.display(s.t("pl080.too_high"), at: lin, 65, color: 4)
                        continue details
                    }
                    // end-line
                    oi.setInt("oi-paid", Cobol.truncate(oi.int("oi-paid") + payPaid, digits: 9))
                    oi.setInt("oi-p-c", Cobol.truncate(oi.int("oi-p-c") + payPaid, digits: 9))
                    oi.setInt("oi-cr", payPaid)
                    workNet = Cobol.truncate(workNet - oi.int("oi-deduct-amt"), digits: 9)
                    if oi.int("oi-paid") == workNet {
                        oi.setInt("oi-date-cleared", payDate)
                        oi.setInt("oi-status", 1)
                    }
                    oi5.rewrite(oi)
                }
                break
            }
            // end-line-2
            lin += 1
            if lin > 23 { lin = 14 }
            if appropAmount >= payValue { break payLoop }
        }
        // main-end
        for f in ["oi-carriage", "oi-vat", "oi-c-vat", "oi-status", "oi-cr", "oi-days", "oi-deduct-vat", "oi-discount", "oi-deduct-days", "oi-p-c"] { oi.setInt(f, 0) }
        oi.set("oi-applied", " ")
        oi.set("oi-supplier", payCustomer)
        oi.setInt("oi-date", payDate)
        oi.setInt("oi-type", transactionType)
        oi.setInt("oi-paid", payValue)
        oi.setInt("oi-approp", appropAmount)
        oi.setInt("oi-deduct-amt", deductTaken % 100_000)
        oi.setInt("oi-b-nos", abs(s.sys.int("bl-next-batch")) % 100_000)
        oi.setInt("oi-b-item", Int64(k))
        oi.setInt("oi-invoice", oi.int("oi-b-nos") * 1000 + oi.int("oi-b-item"))
        oi5.write(oi)
        appropAmount = 0; deductTaken = 0
    }
}
