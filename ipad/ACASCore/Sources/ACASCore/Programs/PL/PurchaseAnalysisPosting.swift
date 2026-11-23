import Foundation

struct PurchaseAnalysisPosting {
    let ledger: PurchaseLedger
    var store: FileStore { ledger.store }
    var path: String { ledger.base + "value.dat" }

    init(_ ledger: PurchaseLedger) { self.ledger = ledger }

    func accumulate(headers: [Record]) throws {
        guard !headers.isEmpty else { return }
        let compatible = !ledger.hasIncompatibleAnalysis
        var specials = [(Int64, Int64)](repeating: (0, 0), count: 4)
        for header in headers {
            let number = header.int("ih-invoice")
            let type = header.int("ih-type")
            if header.str("ih-update").uppercased() != "Z" {
                let sign: Int64 = type == 3 ? -1 : 1
                let amounts = [
                    type == 1 ? 0 : sign * (header.int("ih-vat") + header.int("ih-c-vat")),
                    type == 1 ? header.int("ih-vat") + header.int("ih-c-vat") : 0,
                    sign * header.int("ih-carriage"), header.int("ih-deduct-amt"),
                ]
                for i in amounts.indices where amounts[i] != 0 {
                    specials[i].0 += 1
                    specials[i].1 = Cobol.truncate(specials[i].1 + amounts[i], digits: 9)
                }
            }
            for index in 0..<Int(max(0, header.int("ih-lines"))) {
                let invoiceKey = ledger.invoiceKey(number, index + 1)
                guard let bytes = store.read(ledger.invoicePath, key: invoiceKey) else { continue }
                var row = Record(PurchaseRecords.invLineLayout, bytes: bytes)
                guard row.str("il-update").uppercased() != "Z" else { continue }
                let offset = row.layout.offset("il-pa") + 1
                let key = [UInt8(0x50)] + Array(row.bytes[offset..<(offset + 2)])
                let amount = row.int("il-net") * (row.str("il-type") == "3" ? -1 : 1)
                if try accumulate(key, count: 1, net: amount, compatible: compatible) {
                    row["il-update"] = "z"
                    try requirePostingWrite(store.rewrite(ledger.invoicePath, key: invoiceKey, data: row.bytes),
                                            path: ledger.invoicePath)
                }
            }
        }
        for (code, totals) in zip(["Pvi", "Pvj", "Pza", "Pzb"], specials) {
            try accumulate(Array(code.utf8), count: totals.0, net: totals.1, compatible: compatible)
        }
    }

    @discardableResult
    private func accumulate(_ key: [UInt8], count: Int64, net: Int64, compatible: Bool) throws -> Bool {
        let parent = [key[0], key[1], 0x20]
        if store.read(path, key: key) == nil, compatible {
            let missing = store.read(ledger.analysisPath, key: key) == nil
            if missing {
                try createEmergencyAnalysis(key)
                if key != parent { try createEmergencyAnalysis(parent) }
            }
            if key != parent, store.read(path, key: parent) == nil,
               let source = store.read(ledger.analysisPath, key: parent) {
                try requirePostingWrite(store.write(path, key: parent, data: initialValue(parent, analysis: source).bytes), path: path)
            }
        }
        let analysis = compatible ? store.read(ledger.analysisPath, key: key) : nil
        try update(key, count: count, net: net, initial: initialValue(key, analysis: analysis))
        guard key != parent, store.read(path, key: parent) != nil else { return false }
        try update(parent, count: count, net: net)
        return true
    }

    private func createEmergencyAnalysis(_ key: [UInt8]) throws {
        guard store.read(ledger.analysisPath, key: key) == nil else { return }
        var record = Record(PurchaseLedger.analysisLayout)
        record.bytes.replaceSubrange(0..<3, with: key)
        record["description"] = "Emergency Name"
        try requirePostingWrite(store.write(ledger.analysisPath, key: key, data: record.bytes), path: ledger.analysisPath)
    }

    private func initialValue(_ key: [UInt8], analysis: [UInt8]?) -> Record {
        var record = Record(PurchaseRecords.valueLayout)
        let metadataSize = PurchaseLedger.analysisLayout.size
        record.bytes.replaceSubrange(0..<metadataSize, with: analysis ?? key + [UInt8](repeating: 0, count: metadataSize - 3))
        return record
    }

    private func update(_ key: [UInt8], count: Int64, net: Int64, initial: Record? = nil) throws {
        let data = store.read(path, key: key)
        guard var record = data.map({ Record(PurchaseRecords.valueLayout, bytes: $0) }) ?? initial else { return }
        for period in ["this", "year"] {
            let field = period + "-count"
            record.setInt(field, Cobol.truncate(record.int(field) + count, digits: 5, signed: false))
            let amount = period + "-net"
            record.setInt(amount, Cobol.truncate(record.int(amount) + net, digits: 10))
        }
        let succeeded = data == nil ? store.write(path, key: key, data: record.bytes) : store.rewrite(path, key: key, data: record.bytes)
        try requirePostingWrite(succeeded, path: path)
    }
}
