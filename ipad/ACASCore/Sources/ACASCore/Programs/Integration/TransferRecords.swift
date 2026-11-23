enum TransferRecords {
    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static func d(_ width: Int) -> FieldType { .n9(digits: width, scale: 0, signed: false) }

    static let batchLayout: Layout = {
        let amt = FieldType.comp3(digits: 11, scale: 2, signed: false)
        let l = Layout("batch-record", [
            ("ledger", d(1)), ("batch-nos", d(5)), ("items", d(2)), ("batch-status", d(1)), ("cleared-status", d(1)), ("bcycle", d(2)),
            ("entered", bl), ("proofed", bl), ("posted", bl), ("stored", bl),
            ("input-gross", amt), ("input-vat", amt), ("actual-gross", amt), ("actual-vat", amt),
            ("description", .x(24)), ("bdefault", d(2)), ("convention", .x(2)), ("batch-def-ac", d(6)), ("batch-def-pc", d(2)),
            ("batch-def-code", .x(2)), ("batch-def-vat", .x(1)), ("batch-start", d(5)),
        ])
        l.redefine("batch-key", .x(6), at: 0)
        return l
    }()
    static let postLayout = Layout("posting-record", [
        ("batch", d(5)), ("post-number", d(5)), ("post-code", .x(2)), ("post-date", .x(8)), ("post-dr", d(6)), ("dr-pc", d(2)),
        ("post-cr", d(6)), ("cr-pc", d(2)), ("post-amount", .n9(digits: 10, scale: 2, signed: true)), ("post-legend", .x(32)),
        ("vat-ac", d(6)), ("vat-pc", d(2)), ("post-vat-side", .x(2)), ("vat-amount", .n9(digits: 10, scale: 2, signed: true)),
    ])
}
