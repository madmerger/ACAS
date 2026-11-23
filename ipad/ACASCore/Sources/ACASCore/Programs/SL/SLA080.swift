import Foundation

/// sales/sl080.cbl: Payment Data Entry (入金入力)
enum SLA080 {
    static let progName = "SL080 (3.01.08)"

    final class WS {
        var toDay = ""
        var uDate = SLA.spaces(10)
        var uBin: Int64 = 0
        /// ws-amount-screen-display (9(7) "." v99 の 10 桁グループ)
        var amtScreen = Array("0000000.00")
        /// amt-ok (9(7)v99) を 9 桁の数字列で持つ
        var amtDigits = Array("000000000")
        var work1: Int64 = 0, work2: Int64 = 0
        var workNet: Int64 = 0, workDed: Int64 = 0
        var k = 0
        var appropAmount: Int64 = 0, deductTaken: Int64 = 0
        var payCustomer = SLA.spaces(7)
        var payDate: Int64 = 0
        var payValue: Int64 = 0, batchValue: Int64 = 0, payPaid: Int64 = 0
        var transactionType: Int64 = 0
        var lin = 0, cole = 0
        var oi: Record = { var r = Record(SLA.oiLayout); SLA.initialize(&r); return r }()
        var sales = Record(SLA.salesLayout)
        var salesFile: IndexedFile!, oi3: IndexedFile!
        var amtOk: Int64 {
            get { amtDigits.reduce(Int64(0)) { $0 * 10 + Int64(($1.asciiValue ?? 0) & 0x0f) % 10 } }
            set { amtDigits = Array(Cobol.z(newValue, 9)) }
        }
    }

    /// 符号なし項目への格納 (絶対値・上位桁あふれ切り捨て)
    static func u(_ v: Int64, _ digits: Int) -> Int64 { Cobol.truncate(abs(v), digits: digits, signed: false) }
    static func m9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9, signed: true) }
    static func wsDate(_ s: Session, _ w: WS) -> String { Common.convDate(s, w.toDay) }

    static func run(_ s: Session) throws {
        let w = WS()
        w.toDay = s.toDay
        if s.sys.int("s-flag-i") == 1 {
            try SLA.maps99(s, 28)
            try SLA.maps99(s, 15)
            return
        }
        if SLA.fileStatus(s, 19) != 1 {
            try SLA.maps99(s, 19)
            try SLA.maps99(s, 15)
            return
        }
        displayHeads(s, w)
        w.k = 0
        w.salesFile = SLA.salesFile(s); w.oi3 = SLA.openItemFile3(s)
        _ = w.salesFile.open(); _ = w.oi3.open()
        try newPayment(s, w)
        w.salesFile.close(); w.oi3.close()
        displayHeads(s, w)
        s.sys.setInt("first-sl-batch", s.sys.int("first-sl-batch") + 1)
        s.sys["oi-3-flag"] = "Y"
    }

    static func displayHeads(_ s: Session, _ w: WS) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("sl080.title"), at: 133, color: 2)
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        c.display(wsDate(s, w), at: 171, color: 2)
    }

    // MARK: new-payment section

    static func newPayment(_ s: Session, _ w: WS) throws {
        let c = s.console
        let stars = String(repeating: "*", count: 40)
        newPayment: while true {
            w.lin = 4
            displayHeads(s, w)
            c.display(stars, at: 441, color: 2)
            c.display(s.t("sl080.box1"), at: 541, color: 2)
            c.display(s.t("sl080.box2"), at: 641, color: 2)
            c.display(s.t("sl080.box3"), at: 741, color: 2)
            c.display(stars, at: 841, color: 2)
            dateInput: while true {
                var d = wsDate(s, w)
                c.display(d, at: 551, color: 3)
                d = try c.accept(at: 551, size: 10, initial: d, options: [.update], color: 3)
                if d.allSatisfy({ $0 == " " }) || c.crtStatus == 2005 { return }
                let bin = Int64(SLA.validateDate(s, d))
                if bin == 0 { continue }
                w.uBin = bin
                w.payDate = bin
                w.uDate = Maps04.toDate(Int(bin))
                w.toDay = w.uDate
                customerInput: while true {
                    if w.k == 999 {
                        c.display(s.t("sl080.batch_full"), at: 1041, color: 2)
                        return
                    }
                    w.payCustomer = Cobol.x(try c.accept(at: 572, size: 7, initial: SLA.spaces(7), options: [.update], color: 3).uppercased(), 7)
                    c.display(w.payCustomer, at: 572, color: 3)
                    if w.payCustomer == SLA.spaces(7) { continue dateInput }
                    if c.crtStatus == 2005 { return }
                    guard let sr = w.salesFile.read(key: SJIS.encode(w.payCustomer, size: 7)) else { continue }
                    w.sales = sr
                    let address = Array(sr.str("sales-addr1") + sr.str("sales-addr2"))
                    c.display(sr.str("sales-name"), at: 401, color: 3)
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
                                // unstring address-a into address-line pointer z (区切りなし: 受け側の長さ分)
                                while j < address.count && part.count < 36 { part.append(address[j]); j += 1 }
                                ptr = j + 1
                            }
                        }
                        c.display(Cobol.x(part, 36), at: 5 + i, 1, color: 3)
                    }
                    c.display(s.t("sl080.current_balance"), at: 1001, color: 2)
                    c.display(Pic.edit("z(6)9.99cr", value: sr.int("sales-current"), scale: 2), at: 1019, color: 3)
                    w.transactionType = 5
                    var unappliedPath = false
                    if w.sales.int("sales-unapplied") != 0 {
                        c.display(s.t("sl080.unapplied_balance"), at: 645, color: 2)
                        c.display(Pic.edit("z(6)9.99", value: w.sales.int("sales-unapplied"), scale: 2), at: 665, color: 3)
                        w.amtOk = u(w.sales.int("sales-unapplied"), 9)
                        c.display(s.t("sl080.allocate"), at: 1601, color: 2)
                        var reply = "Y"
                        while true {
                            reply = try c.accept(at: 1666, size: 1, initial: reply, options: [.update], color: 6)
                            if c.crtStatus == 2005 { continue newPayment }
                            reply = reply.uppercased()
                            if reply == "Y" || reply == "N" { break }
                        }
                        c.display(" ", at: 1601, eraseEOL: true)
                        if reply == "Y" {
                            w.transactionType = 6
                            w.lin = 7; w.cole = 49
                            while true {
                                try acceptMoney2(s, w)
                                if w.amtOk == 0 { continue newPayment }
                                if w.amtOk > w.sales.int("sales-unapplied") { continue }
                                break
                            }
                            w.sales.setInt("sales-unapplied", w.sales.int("sales-unapplied") - w.amtOk)
                            w.payValue = w.amtOk
                            _ = w.salesFile.rewrite(w.sales)
                            unappliedPath = true
                        }
                    }
                    if !unappliedPath {
                        // value-input
                        w.lin = 7; w.cole = 49
                        try acceptMoney(s, w)
                        w.payValue = w.amtOk
                        if w.payValue == 0 { continue customerInput }
                        if c.crtStatus == 2005 { return }
                        s.sys.setInt("s-flag-p", 1)
                        w.batchValue = u(w.batchValue + w.payValue, 9)
                        c.display(s.t("sl080.batch_total"), at: 1041, color: 2)
                        c.display(Pic.edit("z(6)9.99cr", value: w.batchValue, scale: 2), at: 1055, color: 3)
                    }
                    // set-batch-item
                    if s.sys.int("first-sl-batch") == 0 { s.sys.setInt("first-sl-batch", 1) }
                    w.k = (w.k + 1) % 1000
                    c.display(Pic.edit("z(4)9", value: Cobol.truncate(s.sys.int("first-sl-batch"), digits: 5, signed: false), scale: 0), at: 770, color: 3)
                    c.display(Cobol.z(w.k, 3), at: 776, color: 3)
                    // data-input
                    try paymentAppropriate(s, w)
                    w.lin = 14; w.cole = 1
                    c.display(" ", at: w.lin, w.cole, eraseEOS: true)
                    c.display(s.t("sl080.further"), at: 1629, color: 2)
                    while true {
                        let reply = try c.accept(at: 1661, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                        if reply == "Y" { continue newPayment }
                        if reply == "N" { return }
                    }
                }
            }
        }
    }

    // MARK: accept-money / accept-money2

    static func acceptAmount(_ s: Session, _ w: WS) throws {
        let c = s.console
        c.display(String(w.amtScreen), at: w.lin, w.cole, color: 3)
        w.amtScreen = Array(Cobol.x(try c.accept(at: w.lin, w.cole, size: 10, initial: String(w.amtScreen), options: [.update], color: 3), 10))
        w.amtDigits = Array(w.amtScreen[0..<7]) + Array(w.amtScreen[8..<10])
    }

    static func acceptMoney(_ s: Session, _ w: WS) throws {
        w.amtDigits = Array("000000000")
        w.amtScreen.replaceSubrange(0..<7, with: Array("0000000"))
        w.amtScreen.replaceSubrange(8..<10, with: Array("00"))
        try acceptAmount(s, w)
    }

    static func acceptMoney2(_ s: Session, _ w: WS) throws {
        w.amtScreen.replaceSubrange(8..<10, with: w.amtDigits[7..<9])
        w.amtScreen.replaceSubrange(0..<7, with: w.amtDigits[0..<7])
        try acceptAmount(s, w)
    }

    // MARK: payment-appropriate section

    static func paymentAppropriate(_ s: Session, _ w: WS) throws {
        let c = s.console
        c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
        c.display(s.t("sl080.head1"), at: 1202, color: 2)
        c.display(s.t("sl080.head2"), at: 1233, color: 2)
        c.display(s.t("sl080.head3"), at: 1258, color: 2)
        w.appropAmount = 0
        w.lin = 14
        _ = w.oi3.start(notLessThan: SLA.oiKey(w.payCustomer, 0))
        payLoop: while let rec = w.oi3.readNext() {
            w.oi = rec
            if w.oi.int("oi-type") != 2 { continue }
            if w.oi.str("oi-customer") != w.payCustomer { break }
            if w.oi.int("oi-b-nos") != 0 { continue }
            w.workNet = m9(w.oi.int("oi-net") + w.oi.int("oi-extra") + w.oi.int("oi-carriage") + w.oi.int("oi-vat") + w.oi.int("oi-c-vat")
                + w.oi.int("oi-discount") + w.oi.int("oi-e-vat"))
            w.workDed = u(w.oi.int("oi-deduct-amt") + w.oi.int("oi-deduct-vat"), 5)
            let testAmount = m9(w.workNet + w.workDed)
            if testAmount == w.oi.int("oi-paid") && w.oi.int("oi-status") == 0 {
                w.oi.setInt("oi-date-cleared", w.payDate)
                w.oi.setInt("oi-status", 1)
                _ = w.oi3.rewrite(w.oi)
                continue
            }
            if testAmount <= w.oi.int("oi-paid") { continue }
            var noChange = false
            payDetails: while true {
                c.display(" ", at: w.lin, 1, eraseEOL: true)
                c.display(Pic.edit("z(7)9", value: Cobol.truncate(w.oi.int("oi-invoice"), digits: 8, signed: false), scale: 0), at: w.lin, 1, color: 3)
                // zz060: maps04 は u-bin > 0 なら u-date へ展開、そうでなければ u-date から u-bin を求める
                w.uBin = w.oi.int("oi-date")
                if w.uBin > 0 { w.uDate = Maps04.toDate(Int(w.uBin)) } else { w.uBin = Int64(Maps04.toBinary(w.uDate)) }
                c.display(w.uDate, at: w.lin, 11, color: 3)
                w.work1 = u(w.workNet, 9)
                w.work2 = w.workDed
                w.uBin += 1 + w.oi.int("oi-deduct-days")
                w.work1 = u(w.work1 + w.work2, 9)
                var display5: Int64 = 0
                if w.uBin > w.payDate {
                    w.work1 = u(w.work1 - w.work2, 9)
                    display5 = w.work2
                }
                w.work1 = u(w.work1 - w.oi.int("oi-paid"), 9)
                w.payPaid = w.work1
                c.display(Pic.edit("z(6)9.99", value: w.work1, scale: 2), at: w.lin, 21, color: 3)
                c.display(Pic.edit("zz9.99", value: display5, scale: 2), at: w.lin, 35, color: 3)
                if w.payPaid == 0 {
                    c.display(s.t("sl080.fully_paid"), at: w.lin, 65, color: 2)
                } else {
                    c.display(" ", at: w.lin, 65, eraseEOL: true)
                }
                if w.payPaid > w.payValue { w.payPaid = m9(w.payValue - w.appropAmount) }
                w.cole = 46
                w.amtOk = u(w.payPaid, 9)
                try acceptMoney2(s, w)
                w.payPaid = w.amtOk
                if w.payPaid == 0 {
                    c.display(Pic.edit("z(6)9.99cr", value: 0, scale: 2), at: w.lin, 46, color: 3)
                    c.display(s.t("sl080.no_change"), at: w.lin, 65, color: 2)
                    noChange = true
                    break
                }
                w.oi.setInt("oi-b-nos", Cobol.truncate(s.sys.int("first-sl-batch"), digits: 5, signed: false))
                w.oi.setInt("oi-b-item", Int64(w.k))
                // get-agreement
                w.appropAmount = u(w.appropAmount + w.payPaid, 8)
                func tooHigh() {
                    w.appropAmount = u(w.appropAmount - w.payPaid, 8)
                    c.display(s.t("sl080.too_high"), at: w.lin, 65, color: 2)
                }
                if w.appropAmount > w.payValue { tooHigh(); continue }
                if w.payPaid == w.work1 {
                    w.oi.setInt("oi-date-cleared", w.payDate)
                    w.oi.setInt("oi-status", 1)
                    if w.uBin > w.payDate {
                        w.oi.setInt("oi-deduct-amt", 0); w.oi.setInt("oi-deduct-vat", 0)
                        w.deductTaken = u(w.deductTaken + w.work2, 8)
                    }
                    break
                }
                if w.uBin <= w.payDate { w.work1 = u(w.work1 - w.work2, 9) }
                if w.payPaid > w.work1 {
                    // payment-2-high-maybe
                    w.work1 = u(w.work1 + w.work2, 9)
                    if w.payPaid > w.work1 { tooHigh(); continue }
                    break
                }
                if w.payPaid != w.work1 { break }
                c.display("Y", at: w.lin, 65, color: 6)
                let reply = try c.accept(at: w.lin, 65, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if reply == "Y" {
                    w.oi.setInt("oi-date-cleared", w.payDate)
                    w.oi.setInt("oi-status", 1)
                    w.deductTaken = u(w.deductTaken + w.work2, 8)
                    w.oi.setInt("oi-deduct-amt", 0); w.oi.setInt("oi-deduct-vat", 0)
                }
                break
            }
            if !noChange {
                // end-line
                w.oi.setInt("oi-paid", m9(w.oi.int("oi-paid") + w.payPaid))
                w.oi.setInt("oi-p-c", m9(w.oi.int("oi-p-c") + w.payPaid))
                w.oi.setInt("oi-cr", Cobol.truncate(w.payPaid, digits: 9, signed: true))
                w.workNet = m9(w.workNet + w.oi.int("oi-deduct-amt") + w.oi.int("oi-deduct-vat"))
                if w.oi.int("oi-paid") == w.workNet {
                    w.oi.setInt("oi-date-cleared", w.payDate)
                    w.oi.setInt("oi-status", 1)
                }
                _ = w.oi3.rewrite(w.oi)
            }
            // end-line-2
            w.lin += 1
            if w.lin > 23 { w.lin = 14 }
            if w.appropAmount >= w.payValue { break payLoop }
        }
        // main-end
        for f in ["oi-extra", "oi-carriage", "oi-vat", "oi-discount", "oi-e-vat", "oi-c-vat", "oi-status",
                  "oi-cr", "oi-days", "oi-deduct-vat", "oi-deduct-days", "oi-p-c"] { w.oi.setInt(f, 0) }
        for f in ["oi-description", "oi-applied", "oi-unapl", "oi-hold-flag"] { w.oi[f] = "" }
        w.oi["oi-customer"] = w.payCustomer
        w.oi.setInt("oi-date", w.payDate)
        w.oi.setInt("oi-type", w.transactionType)
        w.oi.setInt("oi-paid", w.payValue)
        w.oi.setInt("oi-net", w.appropAmount)
        w.oi.setInt("oi-deduct-amt", Cobol.truncate(w.deductTaken, digits: 5, signed: true))
        w.oi.setInt("oi-b-nos", Cobol.truncate(s.sys.int("first-sl-batch"), digits: 5, signed: false))
        w.oi.setInt("oi-b-item", Int64(w.k))
        w.oi.setInt("oi-invoice", w.oi.int("oi-b-nos") * 1000 + w.oi.int("oi-b-item"))
        _ = w.oi3.write(w.oi)
        w.appropAmount = 0; w.deductTaken = 0
    }
}
