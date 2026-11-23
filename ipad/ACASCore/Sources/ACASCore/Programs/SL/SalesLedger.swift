import Foundation

public struct SalesLedger {
    public enum Error: Swift.Error {
        case missingCompany, invalidDate, invalidCode, duplicateCustomer, missingCustomer
        case invalidField, invalidAddress, outstandingBalance
    }

    public struct Customer: Identifiable {
        public var id: String { code }
        public var code = ""
        public var name = ""
        public var address1 = ""
        public var address2 = ""
        public var phone = ""
        public var extensionNumber = ""
        public var email = ""
        public var fax = ""
        public var deliveryName = ""
        public var deliveryAddress1 = ""
        public var deliveryAddress2 = ""
        public var notes1 = ""
        public var notes2 = ""
        public var lateCharges = false
        public var dunning = false
        public var emailInvoice = false
        public var emailStatement = false
        public var emailLetters = false
        public fileprivate(set) var active = true
        public fileprivate(set) var balance: Int64 = 0
        public fileprivate(set) var unapplied: Int64 = 0

        fileprivate var textFields: [(String, String)] {
            [("sales-name", name), ("sales-addr1", address1), ("sales-addr2", address2),
             ("sales-phone", phone), ("sales-ext", extensionNumber), ("sales-email", email), ("sales-fax", fax)]
        }
    }

    private let context: BusinessContext
    public init(_ context: BusinessContext) { self.context = context }

    private var systemFile: RelativeFile {
        RelativeFile(context.store, path: "ledgers/acas/system.dat", recordSize: 1024)
    }

    private var salesFile: IndexedFile { SalesProofRecords.salesFile(context.store) }

    private static let deliveryLayout = Layout("delivery-record", [
        ("key", .x(8)), ("name", .x(30)), ("address1", .x(48)), ("address2", .x(48)),
    ])

    private var deliveryFile: IndexedFile {
        IndexedFile(context.store, path: "ledgers/acas/delivery.dat", layout: Self.deliveryLayout, keyLength: 8)
    }

    private func systemRecord() throws -> Record {
        guard let bytes = systemFile.read(1) else { throw Error.missingCompany }
        return Record(SystemLayout.layout, bytes: bytes)
    }

    public var currentDate: Date { context.now() }

    public func setProcessingDate(_ date: Date) throws {
        var system = try systemRecord()
        let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = parts.year, let m = parts.month, let d = parts.day, Maps04.validYMD(y, m, d) else {
            throw Error.invalidDate
        }
        system.setInt("run-date", Int64(Maps04.integerOfDate(year: y, month: m, day: d)))
        if system.int("date-form") == 0 { system.setInt("date-form", 1) }
        systemFile.write(1, system.bytes)
    }

    public func newCustomer() throws -> Customer {
        let system = try systemRecord()
        var customer = Customer()
        customer.lateCharges = system.int("sl-charges") == 1
        customer.dunning = system.int("sl-dunning") == 1
        return customer
    }

    public func customers() -> [Customer] { salesFile.allRecords().map(customer(from:)) }

    public func customer(code: String) throws -> Customer { customer(from: try customerRecord(code)) }

    public func register(_ customer: Customer) throws -> Customer {
        let code = customer.code.uppercased()
        guard code.count == 6, let check = Maps09.checkDigit(code) else { throw Error.invalidCode }
        let file = salesFile
        let key = code + String(check)
        guard file.read(key: key) == nil else { throw Error.duplicateCustomer }

        var system = try systemRecord()
        var record = Record(SalesProofRecords.salesLayout)
        for field in record.layout.order {
            if case .filler(let size) = field.type {
                record.bytes.replaceSubrange(field.offset..<(field.offset + size), with: repeatElement(0, count: size))
            }
        }
        record["sales-key"] = key
        for (target, source) in [
            ("sales-credit", "sl-credit"), ("sales-discount", "sl-disc"), ("sales-late-min", "sl-min"),
            ("sales-late-max", "sl-max"), ("sales-limit", "sl-limit"), ("sales-create-date", "run-date"),
        ] {
            record.setInt(target, system.int(source))
        }
        record.setInt("sales-status", 1)
        try apply(customer, to: &record, system: system)

        if system.raw("sales-ledger") != [0x59] {
            var flags = system.raw("file-statuses")
            flags[11] = 0x31
            flags[13] = 0x31
            system.setRaw("file-statuses", flags)
            system["sales-ledger"] = "Y"
            systemFile.write(1, system.bytes)
        }
        context.store.createIndexed(deliveryFile.path)
        guard file.write(record) == "00" else { throw Error.duplicateCustomer }
        saveDelivery(of: customer, key: key)
        return self.customer(from: record)
    }

    public func update(_ customer: Customer) throws {
        var record = try customerRecord(customer.code)
        try apply(customer, to: &record, system: systemRecord())
        guard salesFile.rewrite(record) == "00" else { throw Error.missingCustomer }
        saveDelivery(of: customer, key: Cobol.rtrim(record.str("sales-key")))
    }

    public func closeCustomer(code: String, permanently: Bool) throws {
        var record = try customerRecord(code)
        guard record.int("sales-current") == 0, record.int("sales-unapplied") == 0 else { throw Error.outstandingBalance }
        let file = salesFile
        if permanently {
            let key = file.key(of: record)
            guard file.delete(key: key) == "00" else { throw Error.missingCustomer }
            let delivery = deliveryFile
            for type: UInt8 in [0x44, 0x4e] { delivery.delete(key: [type] + key) }
        } else {
            record.setInt("sales-status", 0)
            guard file.rewrite(record) == "00" else { throw Error.missingCustomer }
        }
    }

    private func customerRecord(_ code: String) throws -> Record {
        let key = code.uppercased()
        guard key.count == 7, key.utf8.count == 7, let record = salesFile.read(key: key) else {
            throw Error.missingCustomer
        }
        return record
    }

    private func customer(from record: Record) -> Customer {
        var customer = Customer()
        func value(_ field: String) -> String { Cobol.rtrim(record.str(field)) }
        customer.code = value("sales-key")
        customer.name = value("sales-name")
        customer.address1 = value("sales-addr1")
        customer.address2 = value("sales-addr2")
        customer.phone = value("sales-phone")
        customer.extensionNumber = value("sales-ext")
        customer.email = value("sales-email")
        customer.fax = value("sales-fax")
        customer.active = record.int("sales-status") == 1
        customer.lateCharges = record.int("sales-late") == 1
        customer.dunning = record.int("sales-dunning") == 1
        customer.emailInvoice = record.int("email-invoice") == 1
        customer.emailStatement = record.int("email-statement") == 1
        customer.emailLetters = record.int("email-letters") == 1
        customer.balance = record.int("sales-current")
        customer.unapplied = record.int("sales-unapplied")

        let delivery = deliveryFile
        if record.int("delivery-tag") != 0, let address = delivery.read(key: "D" + customer.code) {
            customer.deliveryName = Cobol.rtrim(address.str("name"))
            customer.deliveryAddress1 = Cobol.rtrim(address.str("address1"))
            customer.deliveryAddress2 = Cobol.rtrim(address.str("address2"))
        }
        if record.int("notes-tag") != 0, let notes = delivery.read(key: "N" + customer.code) {
            customer.notes1 = Cobol.rtrim(notes.str("address1"))
            customer.notes2 = Cobol.rtrim(notes.str("address2"))
        }
        return customer
    }

    private func apply(_ customer: Customer, to record: inout Record, system: Record) throws {
        for (field, value) in customer.textFields {
            record[field] = value
            guard Cobol.rtrim(record.str(field)) == Cobol.rtrim(value) else { throw Error.invalidField }
        }
        for (value, size) in [(customer.deliveryName, 30), (customer.deliveryAddress1, 48),
                              (customer.deliveryAddress2, 48), (customer.notes1, 48), (customer.notes2, 48)] {
            guard Cobol.rtrim(SJIS.decode(SJIS.encode(value, size: size)[...])) == Cobol.rtrim(value) else {
                throw Error.invalidField
            }
        }
        let delimiter = system.raw("sl-delim")[0]
        func validAddress(_ bytes: [UInt8]) -> Bool {
            let separators = bytes.indices.filter { bytes[$0] == delimiter }
            return (1...4).contains(separators.count) && separators[0] <= 30
        }
        guard validAddress(record.raw("sales-addr1") + record.raw("sales-addr2")) else { throw Error.invalidAddress }
        if hasDelivery(customer) || !Cobol.rtrim(customer.deliveryName).isEmpty {
            guard validAddress(SJIS.encode(customer.deliveryAddress1, size: 48) +
                               SJIS.encode(customer.deliveryAddress2, size: 48)) else { throw Error.invalidAddress }
        }
        for (field, flag) in [
            ("sales-late", customer.lateCharges), ("sales-dunning", customer.dunning), ("email-invoice", customer.emailInvoice),
            ("email-statement", customer.emailStatement), ("email-letters", customer.emailLetters),
            ("delivery-tag", hasDelivery(customer)), ("notes-tag", hasNotes(customer)),
        ] { record.setInt(field, flag ? 1 : 0) }
    }

    private func hasDelivery(_ customer: Customer) -> Bool {
        !(Cobol.rtrim(customer.deliveryAddress1).isEmpty && Cobol.rtrim(customer.deliveryAddress2).isEmpty)
    }

    private func hasNotes(_ customer: Customer) -> Bool {
        !(Cobol.rtrim(customer.notes1).isEmpty && Cobol.rtrim(customer.notes2).isEmpty)
    }

    private func saveDelivery(of customer: Customer, key: String) {
        let file = deliveryFile
        for (type, exists, name, first, second) in [
            ("D", hasDelivery(customer), customer.deliveryName, customer.deliveryAddress1, customer.deliveryAddress2),
            ("N", hasNotes(customer), "", customer.notes1, customer.notes2),
        ] {
            let fullKey = type + key
            if exists {
                var record = Record(Self.deliveryLayout)
                record["key"] = fullKey
                record["name"] = name
                record["address1"] = first
                record["address2"] = second
                if file.write(record) == "22" { file.rewrite(record) }
            } else {
                file.delete(key: SJIS.encode(fullKey, size: 8))
            }
        }
    }
}
