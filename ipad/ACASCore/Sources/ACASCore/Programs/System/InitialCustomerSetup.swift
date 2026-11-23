public struct InitialCustomerSetup {
    public struct Contact {
        public var code = ""
        public var name = ""
        public var address = ""
        public var address2 = ""
        public var phone = ""
        public var email = ""

        public init() {}
    }

    public enum Error: Swift.Error { case invalidInput, duplicate, storage }

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func add(_ contact: Contact) throws {
        let code = contact.code.uppercased()
        guard contact.code.utf8.count == 6, contact.code.utf8.allSatisfy({ $0 < 128 }),
              let digit = Maps09.checkDigit(code) else { throw Error.invalidInput }

        let store = context.store
        let file = SalesProofRecords.salesFile(store)
        let ledger = SalesLedger(context)
        try store.withTransaction {
            var company = try ledger.systemRecord()
            guard !company.str("usera").isEmpty else { throw SalesLedger.Error.missingCompany }
            var record = Record(file.layout)
            for field in file.layout.order {
                if case .filler(let size) = field.type {
                    record.bytes.replaceSubrange(field.offset..<(field.offset + size), with: repeatElement(0, count: size))
                }
            }
            let key = code + String(digit)
            for (field, value) in [
                ("sales-key", key), ("sales-name", contact.name), ("sales-addr1", contact.address),
                ("sales-addr2", contact.address2), ("sales-phone", contact.phone), ("sales-email", contact.email),
            ] {
                guard let spec = file.layout.fields[field], case .x(let size) = spec.type,
                      !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                      Cobol.rtrim(SJIS.decode(SJIS.encode(value, size: size)[...])) == Cobol.rtrim(value)
                else { throw Error.invalidInput }
                record[field] = value
            }
            record.setInt("sales-status", 1)
            record.setInt("sales-create-date", company.int("run-date"))
            for (field, setting) in [
                ("late", "sl-charges"), ("dunning", "sl-dunning"), ("credit", "sl-credit"),
                ("discount", "sl-disc"), ("late-min", "sl-min"), ("late-max", "sl-max"), ("limit", "sl-limit"),
            ] { record.setInt("sales-" + field, company.int(setting)) }

            guard file.read(key: key) == nil else { throw Error.duplicate }
            guard file.write(record) == "00" else { throw Error.storage }
            let delivery = ledger.deliveryFile.path
            if !store.exists(delivery) { store.createIndexed(delivery) }
            guard store.kind(delivery) == "indexed" else { throw Error.storage }
            let original = company.bytes
            var flags = company.raw("file-statuses")
            flags[11] = 0x31
            flags[13] = 0x31
            company.setRaw("file-statuses", flags)
            company["sales-ledger"] = "Y"
            if original != company.bytes {
                try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: SystemLayout.layout.size)
                    .write(1, company.bytes)
            }
        }
    }
}
