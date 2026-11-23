enum MasterAnalysisSetup {
    private static let path = "ledgers/acas/analysis.dat"
    private static let count = FieldType.comp(digits: 5, scale: 0, signed: false)
    private static let amount = FieldType.comp3(digits: 10, scale: 2, signed: true)
    private static let layout = Layout("analysis-value-record", [
        ("code", .x(3)), ("ledger-account", .n9(digits: 6, scale: 0, signed: false)),
        ("title", .x(24)), ("print-label", .x(3)),
        ("count-current", count), ("count-last", count), ("count-year", count),
        ("value-current", amount), ("value-last", amount), ("value-year", amount),
    ])

    static func prepare(_ store: FileStore) throws {
        guard !store.exists(path) else { return }
        let file = IndexedFile(store, path: path, layout: layout, keyLength: 3)
        for (code, title, label) in [
            ("Sv ", "VAT Control", ""), ("Pv ", "VAT Control", ""),
            ("Pvi", "VAT Input Invoices/CN's", ""), ("Pvj", "VAT Input Receipts", ""),
            ("Sz ", "Computer Control", ""), ("Pz ", "Computer Control", ""),
            ("Pza", "Purchase Carriage Charges", "P&P"), ("Pzb", "Purchase Late Charges", "LCG"),
            ("Szc", "Sales Carriage Charges", "P&P"), ("Szd", "Sales Late Charges", "LCG"),
            ("Svo", "VAT Output Invoices/CN's", ""), ("Svp", "VAT Output Receipts", ""),
            ("Pa ", "Default Group", ""), ("Pa1", "Default Purchases", ""),
            ("Sa ", "Default Group", ""), ("Sa1", "Default Sales", ""),
        ] {
            var record = Record(layout)
            record["code"] = code
            record["title"] = title
            record["print-label"] = label
            guard file.write(record) == "00" else { throw MasterSetup.Error.storage }
        }
    }
}
