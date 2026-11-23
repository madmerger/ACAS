import Foundation

public struct PurchaseLedger {
    public enum Error: Swift.Error {
        case invalidDate, invalidCode, invalidAddress, duplicateSupplier, supplierNotFound
        case supplierHasBalance, invalidTransaction, transactionNotFound, alreadyPosted, duplicateTransaction
        case analysisCodeNotFound, analysisFileIncompatible
    }

    let context: BusinessContext
    let base = "ledgers/acas/"
    var store: FileStore { context.store }
    var systemFile: RelativeFile { RelativeFile(store, path: base + "system.dat", recordSize: 1024) }
    var system: Record {
        systemFile.read(1).map { Record(SystemLayout.layout, bytes: $0) } ?? SystemAuxRecords.initialSystem()
    }

    public init(_ context: BusinessContext) { self.context = context }

    public var processingDate: Date {
        let days = Int(system.int("run-date"))
        guard days > 0 else { return context.now() }
        let parts = Maps04.dateOfInteger(days)
        return context.calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? context.now()
    }

    func legacyDate(_ date: Date) throws -> Int64 {
        let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = parts.year, let m = parts.month, let d = parts.day, Maps04.validYMD(y, m, d) else {
            throw Error.invalidDate
        }
        return Int64(Maps04.integerOfDate(year: y, month: m, day: d))
    }

    public func setProcessingDate(_ date: Date) throws {
        var record = system
        record.setInt("run-date", try legacyDate(date))
        if !(1...3).contains(record.int("date-form")) { record.setInt("date-form", 1) }
        try systemFile.write(1, record.bytes)
    }

    func setFileFlag(_ number: Int, in record: inout Record) {
        var flags = record.raw("file-statuses")
        flags[number - 1] = 0x31
        record.setRaw("file-statuses", flags)
    }

    public struct Supplier: Identifiable {
        public var code = ""
        public var name = ""
        public var address1 = ""
        public var address2 = ""
        public var sortCode: Int64 = 0
        public var accountNumber: Int64 = 0
        public var note1 = ""
        public var note2 = ""
        public var telephone = ""
        public var extensionNumber = ""
        public var fax = ""
        public var email = ""
        public var paymentDays: Int64 = 0
        public var creditLimit: Int64 = 0
        public var discount: Int64 = 0
        public fileprivate(set) var currentBalance: Int64 = 0
        public fileprivate(set) var unapplied: Int64 = 0
        public fileprivate(set) var active = true
        public var id: String { code }

        public init() {}
    }

    var suppliersPath: String { base + "purchled.dat" }
    var notesPath: String { base + "delivery.dat" }

    func supplierRecord(_ code: String) -> Record? {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.utf8.count == 7 else { return nil }
        return store.read(suppliersPath, key: SJIS.encode(normalized, size: 7))
            .map { Record(PurchaseRecords.purchLayout, bytes: $0) }
    }

    public var newSupplier: Supplier {
        var supplier = Supplier()
        supplier.paymentDays = system.int("age-to-pay")
        return supplier
    }

    public func supplier(code: String) throws -> Supplier {
        guard let record = supplierRecord(code) else { throw Error.supplierNotFound }
        return decodeSupplier(record)
    }

    public func suppliers(byName: Bool = false) -> [Supplier] {
        let values = store.all(suppliersPath).map {
            decodeSupplier(Record(PurchaseRecords.purchLayout, bytes: $0.data))
        }
        return byName ? values.sorted { ($0.name, $0.code) < ($1.name, $1.code) } : values
    }

    private func decodeSupplier(_ record: Record) -> Supplier {
        func str(_ name: String) -> String { Cobol.rtrim(record.str("purch-" + name)) }
        var value = Supplier()
        value.code = str("key"); value.name = str("name")
        value.address1 = str("addr1"); value.address2 = str("addr2")
        value.telephone = str("phone"); value.extensionNumber = str("ext")
        value.fax = str("fax"); value.email = str("email")
        value.sortCode = record.int("purch-sortcode"); value.accountNumber = record.int("purch-accountno")
        value.paymentDays = record.int("purch-credit"); value.creditLimit = record.int("purch-limit")
        value.discount = record.int("purch-discount"); value.currentBalance = record.int("purch-current")
        value.unapplied = record.int("purch-unapplied"); value.active = record.int("purch-status") != 0
        if record.int("purch-notes-tag") != 0, let notes = store.read(notesPath, key: SJIS.encode("N" + value.code, size: 8)),
           notes.count == 134 {
            value.note1 = Cobol.rtrim(SJIS.decode(notes[38..<86]))
            value.note2 = Cobol.rtrim(SJIS.decode(notes[86..<134]))
        }
        return value
    }

    @discardableResult
    public func saveSupplier(_ supplier: Supplier, creating: Bool, joiningAddressLines: Bool = false) throws -> String {
        var code = supplier.code.uppercased()
        var record: Record
        if creating {
            guard code.utf8.count == 6, let digit = Maps09.checkDigit(code) else { throw Error.invalidCode }
            code += String(digit)
            guard supplierRecord(code) == nil else { throw Error.duplicateSupplier }
            record = Record(PurchaseRecords.purchLayout)
            record.bytes.replaceSubrange((record.bytes.count - 16)..<record.bytes.count, with: [UInt8](repeating: 0, count: 16))
            record["purch-key"] = code
            record.setInt("purch-status", 1)
            record.setInt("purch-create-date", system.int("run-date"))
        } else {
            guard let existing = supplierRecord(code) else { throw Error.supplierNotFound }
            record = existing
            code = record.str("purch-key")
        }
        for (field, value) in [
            ("name", supplier.name), ("phone", supplier.telephone), ("ext", supplier.extensionNumber),
            ("fax", supplier.fax), ("email", supplier.email),
        ] { record["purch-" + field] = value }
        let delimiter = addressDelimiter
        if joiningAddressLines {
            let first = Cobol.rtrim(supplier.address1)
            let second = Cobol.rtrim(supplier.address2)
            let previous = addressLines(record)
            if creating || first != previous.first || second != previous.second {
                let address = second.isEmpty && first.contains(delimiter) ? first : first + String(delimiter) + second
                let width = record.raw("purch-address").count
                let bytes = SJIS.encode(address, size: max(width, address.utf8.count))
                guard bytes.dropFirst(width).allSatisfy({ $0 == 0x20 }) else { throw Error.invalidAddress }
                record.setRaw("purch-address", Array(bytes.prefix(width)))
            }
        } else {
            record["purch-addr1"] = supplier.address1
            record["purch-addr2"] = supplier.address2
        }
        let address = Array(record.raw("purch-address").prefix(92))
        let delimiterByte = SJIS.encode(String(delimiter), size: 1)[0]
        let separators = addressSeparators(in: address, delimiter: delimiterByte)
        guard (1...4).contains(separators.count), let first = separators.first, first <= 30 else {
            throw Error.invalidAddress
        }
        for (field, value, modulus) in [
            ("sortcode", supplier.sortCode, 1_000_000), ("accountno", supplier.accountNumber, 100_000_000),
            ("credit", supplier.paymentDays, 100), ("limit", supplier.creditLimit, 10_000_000),
            ("discount", supplier.discount, 10_000),
        ] as [(String, Int64, Int64)] { record.setInt("purch-" + field, abs(value % modulus)) }
        let key = Array(record.bytes.prefix(7))
        let notesKey = SJIS.encode("N" + code, size: 8)
        let hasNotes = !Cobol.rtrim(supplier.note1 + supplier.note2).isEmpty
        record.setInt("purch-notes-tag", hasNotes ? 1 : 0)
        if creating { store.write(suppliersPath, key: key, data: record.bytes) }
        else { store.rewrite(suppliersPath, key: key, data: record.bytes) }
        if hasNotes {
            let bytes = notesKey + SJIS.encode("", size: 30)
                + SJIS.encode(supplier.note1, size: 48) + SJIS.encode(supplier.note2, size: 48)
            if !store.rewrite(notesPath, key: notesKey, data: bytes) {
                store.write(notesPath, key: notesKey, data: bytes)
            }
        } else {
            store.delete(notesPath, key: notesKey)
        }
        return code
    }

    private func addressSeparators(in bytes: [UInt8], delimiter: UInt8) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            if (0x81...0x9f).contains(byte) || (0xe0...0xfc).contains(byte) {
                offset += 2
            } else {
                if byte == delimiter { offsets.append(offset) }
                offset += 1
            }
        }
        return offsets
    }

    private var addressDelimiter: Character {
        system.str("pl-delim").first.flatMap { $0 == " " ? nil : $0 } ?? "\\"
    }

    public func supplierAddressLines(_ supplier: Supplier) -> (first: String, second: String) {
        supplierRecord(supplier.code).map(addressLines) ?? (supplier.address1, supplier.address2)
    }

    private func addressLines(_ record: Record) -> (first: String, second: String) {
        let bytes = record.raw("purch-address")
        let delimiter = SJIS.encode(String(addressDelimiter), size: 1)[0]
        guard let cut = addressSeparators(in: bytes, delimiter: delimiter).first else {
            return (Cobol.rtrim(SJIS.decode(bytes[...])), "")
        }
        let first = Cobol.rtrim(SJIS.decode(bytes[..<cut]))
        let second = SJIS.decode(bytes[(cut + 1)...]).trimmingCharacters(in: .whitespaces)
        return (first, second)
    }

    public func removeSupplier(code: String, deactivate: Bool) throws {
        guard var record = supplierRecord(code) else { throw Error.supplierNotFound }
        guard record.int("purch-current") == 0, record.int("purch-unapplied") == 0 else {
            throw Error.supplierHasBalance
        }
        let key = Array(record.bytes.prefix(7))
        if deactivate {
            record.setInt("purch-status", 0)
            store.rewrite(suppliersPath, key: key, data: record.bytes)
        } else {
            store.delete(notesPath, key: SJIS.encode("N" + record.str("purch-key"), size: 8))
            store.delete(suppliersPath, key: key)
        }
    }

    public struct OpenItem: Identifiable {
        public let id: Int64
        public let reference: String
        public let balance: Int64
    }

    public func openItems(supplier: String) -> [OpenItem] {
        let key = SJIS.encode(supplier, size: 7)
        let runDate = system.int("run-date")
        return store.all(base + "openitm5.dat").compactMap { item in
            guard item.key.starts(with: key), item.data.count == PurchaseRecords.oiLayout.size else { return nil }
            let record = Record(PurchaseRecords.oiLayout, bytes: item.data)
            let type = record.int("oi-type")
            let gross = ["oi-net", "oi-carriage", "oi-vat", "oi-c-vat"].reduce(Int64(0)) { $0 + record.int($1) }
            let balance: Int64
            switch type {
            case 2:
                let eligible = record.int("oi-date") + record.int("oi-deduct-days") >= runDate
                balance = gross - record.int("oi-paid") - (eligible ? record.int("oi-deduct-amt") : 0)
            case 3:
                balance = gross + record.int("oi-paid")
            default:
                balance = 0
            }
            return OpenItem(id: record.int("oi-invoice"), reference: Cobol.rtrim(record.str("oi-ref")),
                            balance: balance)
        }
    }
}
