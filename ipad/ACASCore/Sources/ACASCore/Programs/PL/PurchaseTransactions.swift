import Foundation

extension PurchaseLedger {
    public enum TransactionType: Int64, CaseIterable, Identifiable {
        case receipt = 1, invoice = 2, creditNote = 3
        public var id: Int64 { rawValue }
    }

    public struct Line {
        public var code = ""
        public var net: Int64 = 0
        public var taxCode: Int64 = 1
        public var tax: Int64?
        public init() {}
    }

    public struct Transaction: Identifiable {
        public var number: Int64?
        public var supplier = ""
        public var date: Date
        public var order = ""
        public var reference = ""
        public var type: TransactionType = .invoice
        public var creditReference: Int64 = 0
        public var lines: [Line] = [Line()]
        public var paymentDays: Int64?
        public var carriage: Int64 = 0
        public var carriageTax: Int64?
        public var deduction: Int64 = 0
        public var deductionDays: Int64 = 0
        public fileprivate(set) var posted = false
        public var id: Int64 { number ?? 0 }

        public init(date: Date) { self.date = date }
    }

    public struct AnalysisCode: Identifiable {
        public var code = ""
        public var account: Int64 = 0
        public var name = ""
        public var printGroup = ""
        public var id: String { code }
        public init() {}
    }

    static let analysisLayout = Layout("analysis-record", [
        ("system", .x(1)), ("code", .x(2)), ("account", PurchaseRecords.d(6)),
        ("description", .x(24)), ("print", .x(3)),
    ])
    var analysisPath: String { base + "analysis.dat" }
    var invoicePath: String { base + "pinvoice.dat" }

    func invoiceKey(_ number: Int64, _ line: Int = 0) -> [UInt8] {
        Array(Cobol.z(number, 8).utf8) + [UInt8(line)]
    }

    func header(_ number: Int64) -> Record? {
        guard (0...99_999_999).contains(number), let bytes = store.read(invoicePath, key: invoiceKey(number)),
              bytes.count == PurchaseRecords.invHeaderLayout.size else { return nil }
        return Record(PurchaseRecords.invHeaderLayout, bytes: bytes)
    }

    func headers() -> [Record] {
        store.all(invoicePath).compactMap { entry in
            guard entry.key.count == 9, entry.key.last == 0,
                  entry.data.count == PurchaseRecords.invHeaderLayout.size else { return nil }
            return Record(PurchaseRecords.invHeaderLayout, bytes: entry.data)
        }
    }

    public func transactions() -> [Transaction] { headers().compactMap(decodeTransaction) }

    func decodeTransaction(_ header: Record) -> Transaction? {
        guard let type = TransactionType(rawValue: header.int("ih-type")) else { return nil }
        let date = Maps04.dateOfInteger(Int(header.int("ih-date")))
        let day = context.calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))
        var result = Transaction(date: day ?? processingDate)
        result.number = header.int("ih-invoice")
        result.supplier = Cobol.rtrim(header.str("ih-supplier"))
        result.order = Cobol.rtrim(header.str("ih-order"))
        result.reference = Cobol.rtrim(header.str("ih-ref"))
        result.type = type
        result.creditReference = header.int("ih-cr")
        result.paymentDays = header.int("ih-days")
        result.carriage = header.int("ih-carriage")
        result.carriageTax = header.int("ih-c-vat")
        result.deduction = header.int("ih-deduct-amt")
        result.deductionDays = header.int("ih-deduct-days")
        result.posted = header.str("ih-status").uppercased() == "Z"
        result.lines = (1..<(Int(max(0, header.int("ih-lines"))) + 1)).compactMap { i in
            guard let bytes = store.read(invoicePath, key: invoiceKey(result.id, i)) else { return nil }
            let record = Record(PurchaseRecords.invLineLayout, bytes: bytes)
            var value = Line()
            value.code = Cobol.rtrim(record.str("il-pa"))
            value.net = record.int("il-net")
            value.taxCode = record.int("il-vat-code")
            value.tax = record.int("il-vat")
            return value
        }
        return result
    }

    public func tax(net: Int64, code: Int64) -> Int64 {
        guard (1...3).contains(code), (0..<1_000_000_000).contains(net) else { return 0 }
        return Calc.vat(net: net, rate: system.int("vat-rate-\(code)"))
    }

    var hasIncompatibleAnalysis: Bool {
        store.seek(analysisPath, key: [], inclusive: true).map { $0.data.count != Self.analysisLayout.size } ?? false
    }

    public func analysisCodes() throws -> [AnalysisCode] {
        guard !hasIncompatibleAnalysis else { throw Error.analysisFileIncompatible }
        return store.all(analysisPath).compactMap { entry in
            guard entry.key.first == 0x50 else { return nil }
            let record = Record(Self.analysisLayout, bytes: entry.data)
            var code = AnalysisCode()
            code.code = Cobol.rtrim(record.str("code"))
            code.account = record.int("account")
            code.name = Cobol.rtrim(record.str("description"))
            code.printGroup = Cobol.rtrim(record.str("print"))
            return code
        }
    }

    public func saveAnalysisCode(_ value: AnalysisCode, creating: Bool) throws {
        guard !hasIncompatibleAnalysis else { throw Error.analysisFileIncompatible }
        guard !value.code.isEmpty, SJIS.decode(SJIS.encode(value.code, size: 2)[...]) == Cobol.x(value.code, 2),
              (0...999999).contains(value.account) else { throw Error.invalidCode }
        var record = Record(Self.analysisLayout)
        record["system"] = "P"
        record["code"] = value.code
        let key = Array(record.bytes.prefix(3))
        if key[2] != 0x20 {
            guard let parent = store.read(analysisPath, key: [key[0], key[1], 0x20]),
                  Record(Self.analysisLayout, bytes: parent).int("account") == 0 else { throw Error.analysisCodeNotFound }
        }
        record.setInt("account", value.account)
        record["description"] = value.name
        record["print"] = value.printGroup
        if creating {
            guard store.write(analysisPath, key: key, data: record.bytes) else { throw Error.invalidCode }
        } else {
            guard store.rewrite(analysisPath, key: key, data: record.bytes) else { throw Error.analysisCodeNotFound }
        }
    }

    public func removeAnalysisCode(_ code: String) throws {
        guard !hasIncompatibleAnalysis else { throw Error.analysisFileIncompatible }
        guard store.delete(analysisPath, key: SJIS.encode("P" + code, size: 3)) else { throw Error.analysisCodeNotFound }
    }

    @discardableResult
    public func saveTransaction(_ value: Transaction) throws -> Int64 {
        guard let number = try store.withTransaction({ try persistTransaction(value) }) else {
            throw Error.duplicateFolioAdvanced
        }
        return number
    }

    private func reusableFolio(in bytes: [UInt8]) -> (offset: Int, number: Int64)? {
        for offset in stride(from: 0, to: max(0, bytes.count - 18), by: 19) {
            if let number = Int64(String(decoding: bytes[offset..<(offset + 8)], as: UTF8.self)),
               number > 0, header(number) == nil {
                return (offset, number)
            }
        }
        return nil
    }

    public var nextTransactionFolio: Int64 {
        if let bytes = store.readRaw(base + "delfolio.dat"), let reusable = reusableFolio(in: bytes) {
            return reusable.number
        }
        return Cobol.truncate(max(1, system.int("next-folio")), digits: 8)
    }

    private func persistTransaction(_ value: Transaction) throws -> Int64? {
        guard let supplier = supplierRecord(value.supplier) else { throw Error.supplierNotFound }
        guard (1...40).contains(value.lines.count), (0..<1_000_000_000).contains(value.carriage),
              (0..<100_000).contains(value.deduction), (0...99).contains(value.deductionDays),
              (0...99).contains(value.paymentDays ?? 0), (0...99_999_999).contains(value.creditReference) else {
            throw Error.invalidTransaction
        }
        var configuration = system
        let deletedPath = base + "delfolio.dat"
        let deleted = store.readRaw(deletedPath)
        let reusable = deleted.flatMap { reusableFolio(in: $0) }
        let nextFolio = max(1, configuration.int("next-folio"))
        let number = value.number ?? reusable?.number ?? Cobol.truncate(nextFolio, digits: 8)
        guard (0...99_999_999).contains(number) else { throw Error.invalidTransaction }
        let previous = header(number)
        if value.number != nil && previous == nil { throw Error.transactionNotFound }
        if value.number == nil && previous != nil {
            configuration.setInt("next-folio", nextFolio + 1)
            try systemFile.write(1, configuration.bytes)
            return nil
        }
        if previous?.str("ih-status").uppercased() == "Z" { throw Error.alreadyPosted }
        if value.type == .creditNote, value.creditReference != 0 {
            guard value.creditReference != number, value.creditReference != 99_999_999 else { throw Error.invalidTransaction }
            if let target = self.header(value.creditReference) {
                guard target.int("ih-type") == TransactionType.invoice.rawValue,
                      target.raw("ih-supplier") == supplier.raw("purch-key") else { throw Error.invalidTransaction }
            }
        }
        var header = previous ?? Record(PurchaseRecords.invHeaderLayout)
        header.setInt("ih-invoice", number)
        header["ih-supplier"] = supplier.str("purch-key")
        header.setInt("ih-date", try legacyDate(value.date))
        header["ih-order"] = value.order
        header["ih-ref"] = value.reference
        header.setInt("ih-type", value.type.rawValue)
        header.setInt("ih-cr", value.creditReference)
        header.setInt("ih-days", value.paymentDays ?? (value.type == .invoice ? supplier.int("purch-credit") : 0))
        header.setInt("ih-carriage", value.carriage)
        let carriageTax = value.carriageTax ?? tax(net: value.carriage, code: 1)
        guard (0..<100_000_000).contains(carriageTax) else { throw Error.invalidTransaction }
        header.setInt("ih-c-vat", carriageTax)
        header.setInt("ih-deduct-amt", value.deduction)
        header.setInt("ih-deduct-days", value.deductionDays)
        header.setInt("ih-lines", Int64(value.lines.count))
        let compatible = !hasIncompatibleAnalysis && store.exists(analysisPath)
        var net: Int64 = 0, vat: Int64 = 0
        let records = try value.lines.enumerated().map { index, line -> Record in
            guard !Cobol.rtrim(line.code).isEmpty, (1..<1_000_000_000).contains(line.net),
                  (0...3).contains(line.taxCode) else { throw Error.invalidTransaction }
            let lineTax = line.tax ?? tax(net: line.net, code: line.taxCode)
            guard (0..<100_000_000).contains(lineTax) else { throw Error.invalidTransaction }
            let analysis = store.read(analysisPath, key: SJIS.encode("P" + line.code, size: 3))
            if compatible && analysis == nil { throw Error.analysisCodeNotFound }
            var row = Record(PurchaseRecords.invLineLayout)
            row.setInt("il-invoice", number)
            row.setInt("il-line", Int64(index + 1))
            row["il-pa"] = line.code
            row["il-type"] = String(value.type.rawValue)
            row.setRaw("il-description", compatible ? Record(Self.analysisLayout, bytes: analysis ?? []).raw("description")
                : [UInt8](repeating: 0, count: 24))
            row.setInt("il-net", line.net)
            row.setInt("il-vat", lineTax)
            row.setInt("il-vat-code", line.taxCode)
            net = Cobol.truncate(net + line.net, digits: 9)
            vat = Cobol.truncate(vat + lineTax, digits: 9)
            return row
        }
        header.setInt("ih-net", net)
        header.setInt("ih-vat", vat)
        header["ih-status"] = "P"
        if let previous {
            for i in 0..<(Int(max(0, previous.int("ih-lines"))) + 1) {
                store.delete(invoicePath, key: invoiceKey(number, i))
            }
        } else {
            if let reusable, var deleted {
                deleted.removeSubrange(reusable.offset..<(reusable.offset + 19))
                try store.writeRaw(deletedPath, deleted)
            } else {
                if deleted != nil { try store.writeRaw(deletedPath, []) }
                configuration.setInt("next-folio", nextFolio + 1)
            }
            setFileFlag(26, in: &configuration)
        }
        store.write(invoicePath, key: invoiceKey(number), data: header.bytes)
        for (index, record) in records.enumerated() {
            store.write(invoicePath, key: invoiceKey(number, index + 1), data: record.bytes)
        }
        configuration.setInt("p-flag-i", 1)
        configuration.setInt("pass-value", 0)
        try systemFile.write(1, configuration.bytes)
        return number
    }

    public func removeTransaction(number: Int64) throws {
        guard let header = header(number) else { throw Error.transactionNotFound }
        guard header.str("ih-status").uppercased() != "Z" else { throw Error.alreadyPosted }
        for i in 0..<(Int(max(0, header.int("ih-lines"))) + 1) {
            store.delete(invoicePath, key: invoiceKey(number, i))
        }
        try store.appendRaw(base + "delfolio.dat", Array(header.bytes.prefix(8)) + header.raw("ih-date") + header.raw("ih-supplier"))
    }
}
