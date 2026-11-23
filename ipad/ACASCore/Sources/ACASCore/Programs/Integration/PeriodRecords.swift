enum PeriodRecords {
    private static let c3 = FieldType.comp3(digits: 10, scale: 2, signed: true)
    private static let c3s = FieldType.comp3(digits: 9, scale: 2, signed: true)
    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static let bc = FieldType.native(bytes: 1, signed: true)
    private static let d1 = FieldType.n9(digits: 1, scale: 0, signed: false)

    static let purchLayout = Layout("xl150-purch", [
        ("key", .x(7)), ("status", d1), ("", .filler(1)), ("name", .x(30)), ("", .filler(171)),
        ("activety", bl), ("last-inv", bl), ("last-pay", bl),
        ("average", bl), ("", .filler(16)), ("current", c3), ("last", c3),
        ("turnover-q1", c3), ("turnover-q2", c3), ("turnover-q3", c3), ("turnover-q4", c3), ("unapplied", c3), ("", .filler(16))
    ])
    /// fdval.cob (value-record, 66 バイト)
    static let valueLayout = Layout("xl150-value", [
        ("system", .x(1)), ("", .filler(35)),
        ("t-this", .comp(digits: 5, scale: 0, signed: false)), ("t-last", .comp(digits: 5, scale: 0, signed: false)), ("", .filler(4)),
        ("v-this", c3), ("v-last", c3), ("", .filler(6))
    ])
    /// sales/wssoi.cob (soi-header, 114 バイト)
    static let soiLayout = Layout("xl150-soi", [
        ("", .filler(7)), ("invoice", bl), ("", .filler(10)), ("type", d1), ("", .filler(27)), ("p-c", c3s), ("", .filler(40)),
        ("status", d1), ("", .filler(1)), ("deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("", .filler(9)),
        ("applied", .x(1)), ("", .filler(4))
    ])
    /// purchase/wssoi.cob (poi-header, 109 バイト)
    static let poiLayout = Layout("xl150-poi", [
        ("", .filler(7)), ("invoice", bl), ("", .filler(10)), ("type", d1), ("", .filler(22)), ("p-c", c3s), ("", .filler(40)),
        ("status", d1), ("", .filler(1)), ("deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("", .filler(9)),
        ("applied", .x(1)), ("", .filler(4))
    ])
    /// purchase/wspinv.cob の請求書ヘッダー投影。
    static let pihLayout = Layout("xl150-pih", [
        ("invoice", .n9(digits: 8, scale: 0, signed: false)), ("test", bc), ("supplier", .x(7)),
        ("date", bl), ("order", .x(10)), ("type", d1), ("ref", .x(10)),
        ("p-c", c3s), ("net", c3s), ("extra", c3s), ("carriage", c3s),
        ("vat", c3s), ("discount", c3s), ("e-vat", c3s), ("c-vat", c3s),
        ("status", .x(1)), ("lines", bc), ("deduct-days", bc),
        ("deduct-amt", .comp(digits: 5, scale: 2, signed: false)),
        ("deduct-vat", .comp(digits: 5, scale: 2, signed: false)),
        ("days", bc), ("cr", bl), ("day-book-flag", .x(1)), ("update", .x(1)), ("", .filler(1))
    ])
}
