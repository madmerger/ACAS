enum MasterRecordLayout {
    private static let byte = FieldType.native(bytes: 1, signed: true)
    private static let long = FieldType.native(bytes: 4, signed: true)
    private static let digit = FieldType.n9(digits: 1, scale: 0, signed: false)
    private static let quantity = FieldType.comp(digits: 6, scale: 0, signed: true)
    private static let counter = FieldType.comp(digits: 8, scale: 0, signed: false)
    private static let money = FieldType.comp3(digits: 10, scale: 2, signed: true)

    static let supplier = Layout("purchase-record", [
        ("purch-key", .x(7)), ("purch-status", digit), ("notes", digit), ("purch-name", .x(30)),
        ("purch-addr1", .x(48)), ("purch-addr2", .x(48)), ("purch-phone", .x(13)), ("ext", .x(4)),
        ("fax", .x(13)), ("purch-email", .x(30)), ("discount", .comp(digits: 4, scale: 2, signed: false)),
        ("purch-credit", byte), ("sortcode", long), ("account", long), ("limit", long), ("activity", long),
        ("last-invoice", long), ("last-payment", long), ("average", long), ("purch-create-date", long),
        ("payment-activity", long), ("payment-average", long), ("payment-worst", long),
        ("current", money), ("last", money), ("q1", money), ("q2", money), ("q3", money), ("q4", money),
        ("unapplied", money), ("", .filler(16)),
    ])

    static let stock = Layout("stock-record", [
        ("code", .x(13)), ("abbreviation", .x(7)), ("suppliers", .x(21)), ("name", .x(32)),
        ("construction-item", .x(13)), ("location", .x(10)), ("analysis-codes", .x(6)), ("services", .x(1)),
        ("last-cost", .comp3(digits: 9, scale: 2, signed: false)), ("", .filler(8)),
        ("bundle", quantity), ("under-construction", quantity), ("work-in-progress", quantity),
        ("reorder-point", quantity), ("reorder-quantity", quantity), ("back-ordered", quantity),
        ("on-order", quantity), ("held", quantity), ("pre-sales", quantity),
        ("retail", .comp3(digits: 9, scale: 2, signed: false)), ("cost", .comp3(digits: 11, scale: 4, signed: false)),
        ("value", .comp3(digits: 11, scale: 2, signed: false)),
        ("order-due", counter), ("order-date", counter),
        ("adds", counter), ("deducts", counter), ("wip-adds", counter), ("wip-deducts", counter),
    ] + (1...12).flatMap { month in
        ["adds", "deducts", "wip-adds", "wip-deducts"].map { ("history-\(month)-" + $0, counter) }
    } + [("", .filler(15))])

    static func initialRecord(_ layout: Layout) -> Record {
        var record = Record(layout)
        for field in layout.order {
            if case .filler(let size) = field.type {
                record.bytes.replaceSubrange(field.offset..<(field.offset + size), with: repeatElement(UInt8(0), count: size))
            }
        }
        return record
    }
}
