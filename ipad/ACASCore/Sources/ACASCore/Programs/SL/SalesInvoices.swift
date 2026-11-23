import Foundation

public struct SalesInvoices {
    public enum Error: Swift.Error {
        case missingCompany, missingCustomer, missingInvoice, invalidInput, duplicate, locked, empty, writeFailed
        case unverifiedCreditTarget, invalidCreditTarget
    }
    public enum Kind: Int64, CaseIterable, Identifiable {
        case receipt = 1, invoice, creditNote, proForma
        public var id: Int64 { rawValue }
    }

    public struct Line: Identifiable {
        public let id = UUID()
        public var product = ""
        public var analysis = ""
        public var description = ""
        public var quantity: Int64 = 1
        public var unit: Int64 = 0
        public var discount: Int64 = 0
        public var taxCode: Int64 = 0
        public init() {}
    }

    public struct Number: Hashable {
        public let value: Int64
        public let suffix: String
        public var display: String { Cobol.z(value, 8) + Cobol.rtrim(suffix) }
        public init(value: Int64, suffix: String = "") { self.value = value; self.suffix = suffix }
    }

    public struct Draft {
        public var customer = ""
        public var kind = Kind.invoice
        public var date: Date
        public var reference = ""
        public var order = ""
        public var description = ""
        public var creditedInvoice: Int64 = 0
        public var creditedInvoiceSuffix = ""
        public var requestedNumber: Int64?
        public var lines = [Line()]
        public init(date: Date) { self.date = date }
    }

    public struct Invoice: Identifiable {
        public let id: Number
        public let customer: String
        public let kind: Kind
        public let net: Int64
        public let tax: Int64
        public let printed: Bool
        public var total: Int64 { net + tax }
    }

    let context: BusinessContext
    static let recordSize = 134
    public init(_ context: BusinessContext) { self.context = context }
    var file: IndexedFile { SalesProofRecords.invoiceFile(context.store) }
    var systemFile: RelativeFile { RelativeFile(context.store, path: "ledgers/acas/system.dat", recordSize: 1024) }

    func settings() throws -> Record {
        guard let data = systemFile.read(1) else { throw Error.missingCompany }
        return Record(SystemLayout.layout, bytes: data)
    }

    public var processingDate: Date {
        guard let record = try? settings(), let date = date(for: record.int("run-date")) else { return context.now() }
        return date
    }

    public var usesOwnNumbers: Bool { (try? settings().str("sl-own-nos")) == "Y" }

    func date(for day: Int64) -> Date? {
        guard (1...3_067_671).contains(day) else { return nil }
        let parts = Maps04.dateOfInteger(Int(day))
        return context.calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }

    func key(_ number: Number, line: Int = 0) -> [UInt8] {
        Array(Cobol.z(number.value, 8).utf8) + SJIS.encode(number.suffix, size: 1) + [UInt8(line)]
    }

    func header(_ number: Number) -> Record? { file.read(key: key(number)) }
    func lineRecords(_ number: Number, header: Record) -> [Record] {
        let count = Int(header.int("ih-lines"))
        guard (1...40).contains(count) else { return [] }
        return (1...count).compactMap { index in
            context.store.read(file.path, key: key(number, line: index)).map {
                Record(SalesProofRecords.ilLayout, bytes: $0)
            }
        }
    }

    func number(_ header: Record) -> Number {
        Number(value: header.int("ih-invoice"), suffix: Cobol.rtrim(header.str("ih-letter")))
    }

    func summary(_ header: Record) -> Invoice {
        Invoice(id: number(header), customer: Cobol.rtrim(header.str("ih-customer")),
                kind: Kind(rawValue: header.int("ih-type")) ?? .invoice,
                net: ["ih-net", "ih-extra", "ih-carriage", "ih-deduct-amt"].reduce(0) { $0 + header.int($1) },
                tax: ["ih-vat", "ih-e-vat", "ih-c-vat", "ih-deduct-vat"].reduce(0) { $0 + header.int($1) },
                printed: header.str("ih-status") != "P" && header.str("ih-status-l") == "L")
    }

    public func invoices() -> [Invoice] {
        context.store.all(file.path).filter { $0.key.last == 0 }.map {
            summary(Record(SalesProofRecords.ihLayout, bytes: $0.data))
        }
    }

    public func draft(for number: Number) throws -> Draft {
        guard let header = header(number) else { throw Error.missingInvoice }
        var draft = Draft(date: date(for: header.int("ih-date")) ?? processingDate)
        draft.customer = Cobol.rtrim(header.str("ih-customer"))
        draft.kind = Kind(rawValue: header.int("ih-type")) ?? .invoice
        draft.reference = Cobol.rtrim(header.str("ih-ref"))
        draft.order = Cobol.rtrim(header.str("ih-order"))
        draft.description = Cobol.rtrim(header.str("ih-description"))
        draft.creditedInvoice = header.int("ih-cr") & 0x00ff_ffff
        draft.lines = lineRecords(number, header: header).map { record in
            var line = Line()
            line.product = Cobol.rtrim(record.str("il-product"))
            line.analysis = Cobol.rtrim(record.str("il-pa"))
            line.description = Cobol.rtrim(record.str("il-description"))
            line.quantity = record.int("il-qty")
            line.unit = record.int("il-unit")
            line.discount = record.int("il-discount")
            line.taxCode = record.int("il-vat-code")
            return line
        }
        return draft
    }

    private static let openItemCreditLayout = Layout("open-item-credit", [
        ("key", .x(7)), ("invoice", .native(bytes: 4, signed: true)), ("", .filler(10)),
        ("type", .n9(digits: 1, scale: 0, signed: false)), ("", .filler(72)),
        ("status", .n9(digits: 1, scale: 0, signed: false)), ("", .filler(19)),
    ])

    private func validateCreditTarget(_ draft: Draft, customer: String, replacing existing: Number?, confirmed: Bool) throws {
        guard draft.kind == .creditNote, draft.creditedInvoice != 0 else { return }
        guard draft.creditedInvoice < 99_999_999 else { throw Error.invalidInput }
        if let existing {
            let suffix = draft.creditedInvoiceSuffix.uppercased()
            guard ["", "A", "B", "C"].contains(suffix) else { throw Error.invalidInput }
            let number = Number(value: draft.creditedInvoice, suffix: suffix)
            guard key(number) != key(existing) else { throw Error.invalidCreditTarget }
            if let target = header(number) {
                guard target.int("ih-type") == Kind.invoice.rawValue, Cobol.rtrim(target.str("ih-customer")) == customer else {
                    throw Error.invalidCreditTarget
                }
                return
            }
        } else {
            var record = Record(Self.openItemCreditLayout)
            record["key"] = customer
            record.setInt("invoice", draft.creditedInvoice)
            let key = Array(record.bytes.prefix(11))
            if let bytes = context.store.read("ledgers/acas/openitm3.dat", key: key) {
                let target = Record(Self.openItemCreditLayout, bytes: bytes)
                guard bytes.count == Self.openItemCreditLayout.size,
                      target.int("type") == Kind.invoice.rawValue, target.int("status") != 1 else {
                    throw Error.invalidCreditTarget
                }
                return
            }
        }
        guard confirmed else { throw Error.unverifiedCreditTarget }
    }

    public func save(_ draft: Draft, replacing existing: Number? = nil, confirmingUnknownCreditTarget: Bool = false) throws -> Invoice {
        var system = try settings()
        let customer = draft.customer.uppercased()
        guard customer.utf8.count == 7, let account = SalesProofRecords.salesFile(context.store).read(key: customer),
              account.int("sales-status") == 1 else { throw Error.missingCustomer }
        let day = context.calendar.dateComponents([.year, .month, .day], from: draft.date)
        guard let y = day.year, let m = day.month, let d = day.day, Maps04.validYMD(y, m, d),
              (1...40).contains(draft.lines.count), (0...99_999_999).contains(draft.creditedInvoice) else {
            throw Error.invalidInput
        }
        try validateCreditTarget(draft, customer: customer, replacing: existing, confirmed: confirmingUnknownCreditTarget)
        let dateNumber = Maps04.integerOfDate(year: y, month: m, day: d)
        let sequential = system.int("next-invoice")
        let ownNumber = system.str("sl-own-nos") == "Y" ? draft.requestedNumber : nil
        let requested = ownNumber ?? sequential
        guard (0...99_999_999).contains(requested) else { throw Error.invalidInput }
        let number: Number
        var header: Record
        if let existing {
            guard let current = self.header(existing) else { throw Error.missingInvoice }
            guard ["P", "I"].contains(current.str("ih-status")) else { throw Error.locked }
            number = existing
            header = current
            header["ih-status-p"] = " "
        } else {
            let candidates = (ownNumber == nil ? [""] : ["", "A", "B", "C"]).map { Number(value: requested, suffix: $0) }
            guard let available = candidates.first(where: { self.header($0) == nil }) else { throw Error.duplicate }
            number = available
            header = Record(SalesProofRecords.ihLayout)
        }
        let oldCount = Int(header.int("ih-lines"))
        func set(_ field: String, _ value: String, in record: inout Record) throws {
            record[field] = value
            guard Cobol.rtrim(record.str(field)) == Cobol.rtrim(value) else { throw Error.invalidInput }
        }
        try set("ih-ref", draft.reference, in: &header)
        try set("ih-order", draft.order, in: &header)
        try set("ih-description", draft.description, in: &header)
        header.setInt("ih-invoice", number.value)
        header["ih-letter"] = number.suffix
        header["ih-customer"] = customer
        header["ih-status"] = "P"
        header.setInt("ih-date", Int64(dateNumber))
        header.setInt("ih-type", draft.kind.rawValue)
        header.setInt("ih-cr", draft.kind == .creditNote ? draft.creditedInvoice : 0)
        header.setInt("ih-lines", Int64(draft.lines.count))
        let days = draft.kind == .invoice ? account.int("sales-credit") : draft.kind == .proForma ? system.int("pf-retention") : 0
        header.setInt("ih-days", days)
        var net: Int64 = 0, tax: Int64 = 0
        let details = try draft.lines.enumerated().map { index, line -> Record in
            var record = Record(SalesProofRecords.ilLayout)
            record.setInt("il-invoice", number.value)
            record["il-letter"] = number.suffix
            record.setInt("il-line", Int64(index + 1))
            try set("il-product", line.product, in: &record)
            try set("il-pa", line.analysis, in: &record)
            try set("il-description", line.description, in: &record)
            let comment = line.product.hasPrefix("/")
            guard !line.description.isEmpty, comment || (!line.product.isEmpty && (1...32_767).contains(line.quantity)
                && (1...999_999_999).contains(line.unit) && (0...9_999).contains(line.discount)
                && (0...3).contains(line.taxCode)) else { throw Error.invalidInput }
            let value = comment ? 0 : line.quantity * line.unit
            guard value < 1_000_000_000 else { throw Error.invalidInput }
            let discounted = value - ((value * line.discount / 100) % 1_000_000_000) / 100
            let vat = comment || line.taxCode == 0 ? 0 :
                Cobol.rescaleRounded(discounted * system.int("vat-rate-\(line.taxCode)"), from: 6, to: 2) % 1_000_000_000
            if !comment {
                record["il-type"] = String(draft.kind.rawValue)
                record.setInt("il-qty", line.quantity)
                record.setInt("il-unit", line.unit)
                record.setInt("il-discount", line.discount)
                record.setInt("il-net", discounted)
                record.setInt("il-vat", vat)
                record.setInt("il-vat-code", line.taxCode)
            }
            net = (net + discounted) % 1_000_000_000
            tax = (tax + vat) % 1_000_000_000
            return record
        }
        header.setInt("ih-net", net)
        header.setInt("ih-vat", tax)
        let store = context.store
        let path = file.path
        if existing == nil {
            guard store.write(path, key: key(number), data: Array(header.bytes.prefix(Self.recordSize))) else { throw Error.duplicate }
        } else {
            guard store.rewrite(path, key: key(number), data: Array(header.bytes.prefix(Self.recordSize))) else { throw Error.missingInvoice }
        }
        for (index, record) in details.enumerated() {
            let key = key(number, line: index + 1)
            let data = record.bytes + repeatElement(0x20, count: Self.recordSize - record.bytes.count)
            let written = store.read(path, key: key) == nil
                ? store.write(path, key: key, data: data) : store.rewrite(path, key: key, data: data)
            guard written else { throw Error.writeFailed }
        }
        if oldCount > details.count && oldCount <= 40 {
            for index in (details.count + 1)...oldCount { store.delete(path, key: key(number, line: index)) }
        }
        if existing == nil {
            if system.int("first-sl-inv") == 0 { system.setInt("first-sl-inv", number.value) }
            system.setInt("next-invoice", sequential + 1)
        }
        var statuses = system.raw("file-statuses")
        statuses[15] = 0x31
        statuses[18] = 0x31
        system.setRaw("file-statuses", statuses)
        system.setInt("s-flag-i", 1)
        try systemFile.write(1, system.bytes)
        return summary(header)
    }

    public func delete(_ number: Number) throws {
        guard let header = header(number) else { throw Error.missingInvoice }
        guard number.value != 0, !["z", "Z"].contains(header.str("ih-status")) else { throw Error.locked }
        let store = context.store
        let path = file.path
        guard store.delete(path, key: key(number)) else { throw Error.missingInvoice }
        let count = Int(header.int("ih-lines"))
        if (1...40).contains(count) {
            for line in 1...count { store.delete(path, key: key(number, line: line)) }
        }
        try store.appendRaw("ledgers/acas/delinvno.dat",
                        header.raw("ih-invoice") + header.raw("ih-date") + header.raw("ih-customer"))
    }
}
