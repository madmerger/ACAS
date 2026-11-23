enum SalesOpenItems {
    static let path = "ledgers/acas/openitm3.dat"
    private static let nativeLong = FieldType.native(bytes: 4, signed: true)
    private static let nativeByte = FieldType.native(bytes: 1, signed: true)
    private static let amount = FieldType.comp3(digits: 9, scale: 2, signed: true)
    private static let deduction = FieldType.comp(digits: 5, scale: 2, signed: true)
    private static let digit = FieldType.n9(digits: 1, scale: 0, signed: false)

    static let layout = Layout("open-item-header", [
        ("customer", .x(7)), ("invoice", nativeLong), ("date", nativeLong),
        ("batch", .comp(digits: 5, scale: 0, signed: false)),
        ("item", .comp(digits: 3, scale: 0, signed: false)),
        ("type", digit), ("description", .x(25)), ("hold", .x(1)), ("unapplied", .x(1)),
        ("paid-current", amount), ("net", amount), ("extra", amount), ("carriage", amount),
        ("tax", amount), ("discount", amount), ("extra-tax", amount), ("carriage-tax", amount), ("paid", amount),
        ("status", digit), ("deduction-days", nativeByte), ("deduction", deduction), ("deduction-tax", deduction),
        ("days", nativeByte), ("credit", nativeLong), ("applied", .x(1)), ("date-cleared", nativeLong),
    ])

    static func file(_ store: FileStore) -> IndexedFile {
        IndexedFile(store, path: path, layout: layout, keyLength: 11)
    }

    static func key(customer: String, invoice: Int64) -> [UInt8] {
        var record = Record(layout)
        record["customer"] = customer
        record.setInt("invoice", invoice)
        return Array(record.bytes.prefix(11))
    }

    static func invoiceTotal(_ record: Record) -> Int64 {
        ["net", "extra", "carriage", "tax", "carriage-tax", "discount", "extra-tax"].reduce(0) { $0 + record.int($1) }
    }
}
