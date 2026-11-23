enum SalesPostingRecords {
    private static let long = FieldType.native(bytes: 4, signed: true)
    private static let money = FieldType.comp3(digits: 10, scale: 2, signed: true)
    private static let total = FieldType.comp3(digits: 11, scale: 2, signed: false)
    private static let count = FieldType.comp(digits: 5, scale: 0, signed: false)
    private static let displayMoney = FieldType.n9(digits: 10, scale: 2, signed: true)

    private static func digit(_ field: String, _ n: Int = 1) -> (String, FieldType) {
        (field, .n9(digits: n, scale: 0, signed: false))
    }

    static let value = Layout("value-record", [
        ("code", .x(3)), digit("account", 6), ("description", .x(24)), ("print", .x(3)),
        ("count-this", count), ("count-last", count), ("count-year", count),
        ("value-this", money), ("value-last", money), ("value-year", money),
    ])

    static let batch = Layout("batch-record", [
        digit("ledger"), digit("number", 5), digit("items", 2), digit("status"), digit("cleared"), digit("cycle", 2),
        ("entered", long), ("proofed", long), ("posted", long), ("stored", long),
        ("input-gross", total), ("input-tax", total), ("actual-gross", total), ("actual-tax", total),
        ("description", .x(24)), digit("default", 2), ("convention", .x(2)), digit("account", 6),
        digit("profit-centre", 2), ("code", .x(2)), ("tax-code", .x(1)), digit("start", 5),
    ])

    static let posting = Layout("posting-record", [
        digit("batch", 5), digit("number", 5), ("code", .x(2)), ("date", .x(8)),
        digit("debit", 6), digit("debit-centre", 2), digit("credit", 6), digit("credit-centre", 2),
        ("amount", displayMoney), ("legend", .x(32)), digit("tax-account", 6), digit("tax-centre", 2),
        ("tax-side", .x(2)), ("tax-amount", displayMoney),
    ])

    static let monthly = Layout("system-record-4", [
        ("old-balance", money), ("balance", money), ("invoices", money), ("credit-notes", money),
        ("variance", money), ("credit-deductions", money), ("unapplied-credits", money), ("payments", money),
        ("", .filler(976)),
    ])

    static func irsMoney(_ value: Int64) -> [UInt8] {
        var bytes = Array(Cobol.z(value, 9).utf8)
        if value < 0 { bytes[0] += 0x40 }
        return bytes
    }
}
