import Foundation

enum PurchaseRecords {
    static let bc = FieldType.native(bytes: 1, signed: true)
    static let bs = FieldType.native(bytes: 2, signed: true)
    static let bl = FieldType.native(bytes: 4, signed: true)
    static func money(_ digits: Int = 9) -> FieldType { .comp3(digits: digits, scale: 2, signed: true) }
    static func d(_ n: Int) -> FieldType { .n9(digits: n, scale: 0, signed: false) }

    /// fdpl.cob Purch-Record (300 バイト)
    static let purchLayout: Layout = {
        let l = Layout("purch-record", [
            ("purch-key", .x(7)), ("purch-status", d(1)), ("purch-notes-tag", d(1)), ("purch-name", .x(30)),
            ("purch-addr1", .x(48)), ("purch-addr2", .x(48)), ("purch-phone", .x(13)), ("purch-ext", .x(4)),
            ("purch-fax", .x(13)), ("purch-email", .x(30)), ("purch-discount", .comp(digits: 4, scale: 2, signed: false)),
            ("purch-credit", bc), ("purch-sortcode", bl), ("purch-accountno", bl), ("purch-limit", bl),
            ("purch-activety", bl), ("purch-last-inv", bl), ("purch-last-pay", bl), ("purch-average", bl),
            ("purch-create-date", bl), ("purch-pay-activety", bl), ("purch-pay-average", bl), ("purch-pay-worst", bl),
            ("purch-current", money(10)), ("purch-last", money(10)),
            ("turnover-q1", money(10)), ("turnover-q2", money(10)), ("turnover-q3", money(10)), ("turnover-q4", money(10)),
            ("purch-unapplied", money(10)), ("", .filler(16)),
        ])
        l.redefine("purch-address", .x(96), at: l.offset("purch-addr1"))
        return l
    }()

    /// fdpinv2.cob / wspinv.cob invoice-header (129 バイト)
    static let invHeaderLayout: Layout = {
        let l = Layout("invoice-header", [
            ("ih-invoice", d(8)), ("ih-test", bc), ("ih-supplier", .x(7)), ("ih-date", bl), ("ih-order", .x(10)),
            ("ih-type", d(1)), ("ih-ref", .x(10)),
            ("ih-p-c", money()), ("ih-net", money()), ("ih-extra", money()), ("ih-carriage", money()),
            ("ih-vat", money()), ("ih-discount", money()), ("ih-e-vat", money()), ("ih-c-vat", money()),
            ("ih-status", .x(1)), ("ih-lines", bc), ("ih-deduct-days", bc),
            ("ih-deduct-amt", .comp(digits: 5, scale: 2, signed: false)), ("ih-deduct-vat", .comp(digits: 5, scale: 2, signed: false)),
            ("ih-days", bc), ("ih-cr", bl), ("ih-day-book-flag", .x(1)), ("ih-update", .x(1)), ("", .filler(30)),
        ])
        l.redefine("invoice-key", .x(9), at: 0)
        l.redefine("ih-nos", .x(6), at: 9)
        l.redefine("ih-check", d(1), at: 15)
        return l
    }()

    /// wspinv.cob の明細を fdpinv2.cob の 129 バイト領域にグループ転記する。
    static let invLineLayout: Layout = {
        let l = Layout("invoice-line", [
            ("il-invoice", d(8)), ("il-line", bc), ("il-product", .x(12)), ("il-pa", .x(2)), ("", .filler(3)),
            ("il-qty", bs), ("il-type", .x(1)), ("il-description", .x(24)), ("", .filler(2)),
            ("il-net", money()), ("il-unit", money()), ("il-discount", .comp(digits: 4, scale: 2, signed: false)),
            ("il-vat", money()), ("il-vat-code", d(1)), ("il-update", .x(1)), ("", .filler(55)),
        ])
        l.redefine("invoice-key", .x(9), at: 0)
        return l
    }()

    /// wsoi.cob oi-header / fdoi5.cob open-item-record-5 (109 バイト、キー = supplier(7) + invoice(binary-long))
    static let oiLayout: Layout = {
        let l = Layout("oi-header", [
            ("oi-supplier", .x(7)), ("oi-invoice", bl), ("oi-date", bl),
            ("oi-b-nos", .comp(digits: 5, scale: 0, signed: false)), ("oi-b-item", .comp(digits: 3, scale: 0, signed: false)),
            ("oi-type", d(1)), ("oi-ref", .x(10)), ("oi-order", .x(10)), ("oi-hold-flag", .x(1)), ("oi-unapl", .x(1)),
            ("oi-p-c", money()), ("oi-net", money()), ("oi-extra", money()), ("oi-carriage", money()), ("oi-vat", money()),
            ("oi-discount", money()), ("oi-e-vat", money()), ("oi-c-vat", money()), ("oi-paid", money()),
            ("oi-status", d(1)), ("oi-deduct-days", bc),
            ("oi-deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("oi-deduct-vat", .comp(digits: 5, scale: 2, signed: true)),
            ("oi-days", bc), ("oi-cr", bl), ("oi-applied", .x(1)), ("oi-date-cleared", bl),
        ])
        l.redefine("oi-approp", money(), at: l.offset("oi-net"))
        l.redefine("oi5-key", .x(11), at: 0)
        return l
    }()

}
