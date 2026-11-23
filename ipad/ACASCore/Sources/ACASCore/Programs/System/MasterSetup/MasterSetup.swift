import Foundation

public struct MasterContact {
    public var code = ""
    public var name = ""
    public var address = ""
    public var address2 = ""
    public var phone = ""
    public var email = ""

    public init() {}
}

public struct MasterStockItem {
    public var code = ""
    public var abbreviation = ""
    public var name = ""
    public var location = ""
    public var held: Int64 = 0
    public var reorderPoint: Int64 = 0
    public var reorderQuantity: Int64 = 0
    public var onOrder: Int64 = 0
    public var retail: Int64 = 0
    public var cost: Int64 = 0
    public var value: Int64 = 0

    public init() {}
}

public struct MasterSetup {
    public enum ContactKind { case customer, supplier }
    public enum Error: Swift.Error { case missingCompany, invalidInput, duplicate, storage }

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func add(_ contact: MasterContact, as kind: ContactKind) throws {
        let company = try companySettings()
        let code = contact.code.uppercased()
        guard contact.code.utf8.count == 6, contact.code.utf8.allSatisfy({ $0 < 128 }),
              let digit = Maps09.checkDigit(code) else { throw Error.invalidInput }
        let file: IndexedFile
        let prefix: String
        switch kind {
        case .customer:
            file = SalesProofRecords.salesFile(context.store)
            prefix = "sales"
        case .supplier:
            file = IndexedFile(context.store, path: "ledgers/acas/purchled.dat", layout: MasterRecordLayout.supplier, keyLength: 7)
            prefix = "purch"
        }
        var record = MasterRecordLayout.initialRecord(file.layout)
        try put(code + String(digit), into: &record, field: prefix + "-key", required: true)
        try put(contact.name, into: &record, field: prefix + "-name")
        for (suffix, value) in [
            ("addr1", contact.address), ("addr2", contact.address2), ("phone", contact.phone), ("email", contact.email),
        ] {
            try put(value, into: &record, field: prefix + "-" + suffix)
        }
        record.setInt(prefix + "-status", 1)
        record.setInt(prefix + "-create-date", company.number("run-date"))
        if kind == .customer {
            for (field, setting) in [
                ("late", "sl-charges"), ("dunning", "sl-dunning"), ("credit", "sl-credit"),
                ("discount", "sl-disc"), ("late-min", "sl-min"), ("late-max", "sl-max"), ("limit", "sl-limit"),
            ] { record.setInt("sales-" + field, company.number(setting)) }
        } else {
            record.setInt("purch-credit", company.number("age-to-pay"))
        }
        try write(record, to: file)
        let delivery = "ledgers/acas/delivery.dat"
        if !context.store.exists(delivery) { context.store.createIndexed(delivery) }
        guard context.store.exists(delivery) else { throw Error.storage }
        switch kind {
        case .customer: try CompanySetup(context).markFiles([12, 14], module: "sales-ledger")
        case .supplier: try CompanySetup(context).markFiles([14, 22], module: "purchase-ledger")
        }
    }

    public func add(_ item: MasterStockItem) throws {
        let company = try companySettings()
        let file = IndexedFile(context.store, path: "ledgers/acas/stockctl.dat", layout: MasterRecordLayout.stock, keyLength: 13)
        var record = MasterRecordLayout.initialRecord(file.layout)
        try put(item.code.uppercased(), into: &record, field: "code", required: true)
        try put(item.abbreviation.uppercased(), into: &record, field: "abbreviation", required: true)
        try put(item.name, into: &record, field: "name")
        try put(item.location, into: &record, field: "location")
        guard !file.allRecords().contains(where: { $0.str("abbreviation") == record.str("abbreviation") })
        else { throw Error.duplicate }
        record["services"] = "N"
        for (field, value, digits) in [
            ("held", item.held, 6), ("reorder-point", item.reorderPoint, 6), ("reorder-quantity", item.reorderQuantity, 6),
            ("on-order", item.onOrder, 6), ("retail", item.retail, 9), ("cost", item.cost, 11), ("value", item.value, 11),
        ] {
            guard value >= 0, value < Cobol.pow10(digits) else { throw Error.invalidInput }
            record.setInt(field, value)
        }
        if company.number("stk-averaging") == 1 && item.value == 0 {
            record.setInt("value", item.held * item.cost / 100 % Cobol.pow10(11))
        }
        try MasterAnalysisSetup.prepare(context.store)
        try write(record, to: file)
        try CompanySetup(context).markFiles([11, 13, 15], module: "stock-control")
    }

    private func companySettings() throws -> CompanySettings {
        let setup = CompanySetup(context)
        guard !setup.name.isEmpty else { throw Error.missingCompany }
        return setup.settings
    }

    private func put(_ value: String, into record: inout Record, field: String, required: Bool = false) throws {
        guard let spec = record.layout.fields[field], case .x(let size) = spec.type,
              !required || !value.trimmingCharacters(in: .whitespaces).isEmpty,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Cobol.rtrim(SJIS.decode(SJIS.encode(value, size: size)[...])) == Cobol.rtrim(value)
        else { throw Error.invalidInput }
        record[field] = value
    }

    private func write(_ record: Record, to file: IndexedFile) throws {
        guard file.read(key: file.key(of: record)) == nil else { throw Error.duplicate }
        guard file.write(record) == "00" else { throw Error.storage }
    }
}
