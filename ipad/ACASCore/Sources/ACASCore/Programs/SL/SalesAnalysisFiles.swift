enum SalesAnalysisFiles {
    static let layout = Layout("analysis-record", [
        ("code", .x(3)), ("account", .n9(digits: 6, scale: 0, signed: false)),
        ("description", .x(24)), ("print", .x(3)),
    ])

    static func initialize(_ store: FileStore, system: inout Record) throws {
        var flags = system.raw("file-statuses")
        guard flags[14] != 0x31 else { return }
        guard flags[14] == 0x30 || flags[14] == 0x20 else { throw SalesPosting.Error.invalidAnalysisLayout }
        let analysis = IndexedFile(store, path: SalesPosting.analysisPath, layout: layout, keyLength: 3)
        let values = IndexedFile(store, path: SalesPosting.valuePath, layout: SalesPostingRecords.value, keyLength: 3)
        if !store.exists(values.path) { flags[12] = 0x31 }
        analysis.openOutput()
        guard store.kind(analysis.path) == "indexed", store.all(analysis.path).isEmpty else {
            throw SalesPosting.Error.writeFailed
        }
        for (code, description, printCode) in defaults {
            var row = Record(layout)
            row["code"] = code
            row["description"] = description
            row["print"] = printCode
            if values.read(key: code) == nil {
                var value = Record(SalesPostingRecords.value)
                value.bytes.replaceSubrange(0..<layout.size, with: row.bytes)
                guard values.write(value) == "00" else { throw SalesPosting.Error.writeFailed }
            }
            guard analysis.write(row) == "00" else { throw SalesPosting.Error.writeFailed }
        }
        flags[14] = 0x31
        system.setRaw("file-statuses", flags)
    }

    private static let defaults = [
        ("Sv ", "VAT Control", ""), ("Pv ", "VAT Control", ""),
        ("Pvi", "VAT Input Invoices/CN's", ""), ("Pvj", "VAT Input Receipts", ""),
        ("Sz ", "Computer Control", ""), ("Pz ", "Computer Control", ""),
        ("Pza", "Purchase Carriage Charges", "P&P"), ("Pzb", "Purchase Late Charges", "LCG"),
        ("Szc", "Sales Carriage Charges", "P&P"), ("Szd", "Sales Late Charges", "LCG"),
        ("Svo", "VAT Output Invoices/CN's", ""), ("Svp", "VAT Output Receipts", ""),
        ("Pa ", "Default Group", ""), ("Pa1", "Default Purchases", ""),
        ("Sa ", "Default Group", ""), ("Sa1", "Default Sales", ""),
    ]
}
