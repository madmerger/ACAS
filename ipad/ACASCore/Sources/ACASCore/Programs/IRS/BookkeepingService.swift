import Foundation

public struct BookkeepingService {
    public enum Failure: Error {
        case invalidInput, duplicateAccount, missingAccount, missingDefault, missingPosting, wrongPassword, accountArchiveTooLarge
    }

    public struct Configuration {
        public var operatorName = ""
        public var client = ""
        public var street = ""
        public var city = ""
        public var country = ""
        public var postcode = ""
        public var start: Date
        public var end: Date
        public var taxRate: Int64 = 0
        public var printDestination = ""

        init(date: Date) { start = date; end = date }
    }

    public enum Category: String, CaseIterable {
        case assets = "R", liabilities = "U", income = "A", expense = "E", other = "C"
    }

    public struct Account: Identifiable {
        public let code: Int
        public let child: Int
        public let name: String
        public let category: Category?
        public let debit: Int64
        public let credit: Int64
        public var id: String { "\(code)-\(child)" }
    }

    public enum DefaultTax: String, CaseIterable {
        case none = "N"
        case input = "I"
        case output = "O"
    }

    public struct DefaultAccount: Identifiable {
        public let id: Int
        public let account: Int
        public let label: String
        public let tax: DefaultTax
    }

    public struct Posting: Identifiable {
        public let id: Int
        public let debit: Int
        public let credit: Int
        public let amount: Int64
        public let description: String
    }

    let context: BusinessContext
    let directory = "ledgers/irs/"
    var store: FileStore { context.store }
    var accountsPath: String { directory + "acnts.dat" }
    var postPath: String { directory + "post.dat" }
    var systemPath: String { directory + "system.dat" }
    var defaultsPath: String { directory + "dflt.dat" }

    public init(_ context: BusinessContext) { self.context = context }
    public var today: Date { context.now() }
    var system: Record { Record(BookkeepingRecords.systemLayout, bytes: readLine(systemPath) ?? Record(BookkeepingRecords.systemLayout).bytes) }

    func readLine(_ path: String) -> [UInt8]? {
        store.readRaw(path).map { Array($0.prefix { $0 != 0x0a }) }
    }

    func writeLine(_ path: String, _ bytes: [UInt8]) throws {
        let count = bytes.lastIndex { $0 != 0x20 }.map { $0 + 1 } ?? 0
        try store.writeRaw(path, Array(bytes.prefix(count)) + [0x0a])
    }

    func dateString(_ date: Date) -> String {
        let fields = context.calendar.dateComponents([.year, .month, .day], from: date)
        return Cobol.z(fields.day ?? 0, 2) + "/" + Cobol.z(fields.month ?? 0, 2)
            + "/" + Cobol.z((fields.year ?? 0) % 100, 2)
    }

    private func date(_ display: String) -> Date? {
        let parts = display.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let year = parts[2] < 60 ? 2000 + parts[2] : 1900 + parts[2]
        guard Maps04.validYMD(year, parts[1], parts[0]) else { return nil }
        return context.calendar.date(from: DateComponents(year: year, month: parts[1], day: parts[0]))
    }

    public var configuration: Configuration {
        let row = system
        var value = Configuration(date: today)
        value.operatorName = Cobol.rtrim(row.str("suser"))
        value.client = Cobol.rtrim(row.str("client"))
        value.street = Cobol.rtrim(row.str("address-1"))
        value.city = Cobol.rtrim(row.str("address-2"))
        value.country = Cobol.rtrim(row.str("address-3"))
        value.postcode = Cobol.rtrim(row.str("address-4"))
        value.start = date(row.str("start-date")) ?? today
        value.end = date(row.str("end-date")) ?? today
        value.taxRate = row.int("vat")
        value.printDestination = Cobol.rtrim(row.str("print-spool-name"))
        return value
    }

    public func authenticateSettings(password: String) throws -> Configuration {
        try verifyPassword(password, against: system)
        return configuration
    }

    public func save(_ configuration: Configuration, password: String, newPassword: String? = nil) throws {
        var row = system
        try verifyPassword(password, against: row)
        if let newPassword {
            let bytes = SJIS.encode(newPassword, size: 4)
            guard !Cobol.rtrim(newPassword).isEmpty,
                  Cobol.rtrim(SJIS.decode(bytes[...])) == newPassword else { throw Failure.invalidInput }
            row.setRaw("pass-word", bytes)
        }
        guard !configuration.client.isEmpty, configuration.start <= configuration.end,
              (0...9999).contains(configuration.taxRate) else { throw Failure.invalidInput }
        for (field, text) in [
            ("suser", configuration.operatorName), ("client", configuration.client), ("address-1", configuration.street),
            ("address-2", configuration.city), ("address-3", configuration.country), ("address-4", configuration.postcode),
            ("print-spool-name", configuration.printDestination),
        ] {
            let bytes = SJIS.encode(text, size: row.raw(field).count)
            guard Cobol.rtrim(SJIS.decode(bytes[...])) == Cobol.rtrim(text) else { throw Failure.invalidInput }
            row.setRaw(field, bytes)
        }
        row["run-date"] = dateString(today)
        row["start-date"] = dateString(configuration.start)
        row["end-date"] = dateString(configuration.end)
        for (field, value) in [
            ("fn-1", "acnts.dat"), ("fn-2", "system.dat"), ("fn-3", "dflt.dat"), ("fn-4", "post.dat"),
            ("fn-5", "prn"), ("system-ops", "6"), ("system-work-group", ""),
        ] { row[field] = value }
        row.setInt("vat", configuration.taxRate)
        for field in ["pass-value", "save-sequ", "first-time-flag"] { row.setInt(field, 0) }
        try writeLine(systemPath, row.bytes)
    }

    func verifyPassword(_ password: String, against row: Record) throws {
        let encoded = SJIS.encode(password, size: 4)
        guard Cobol.rtrim(SJIS.decode(encoded[...])) == Cobol.rtrim(password),
              encoded == row.raw("pass-word") else { throw Failure.wrongPassword }
    }

    func accountKey(_ base: Int, _ child: Int = 0) -> [UInt8] {
        Array((Cobol.z(base, 5) + Cobol.z(child, 5)).utf8)
    }

    func accountRecord(_ base: Int, _ child: Int = 0) throws -> Record {
        guard (1...99999).contains(base), let bytes = store.read(accountsPath, key: accountKey(base, child))
        else { throw Failure.missingAccount }
        return Record(BookkeepingRecords.nlLayout, bytes: bytes)
    }

    func postingAccount(_ code: Int) throws -> Record {
        let row = try accountRecord(code)
        let resolved = row.str("type") == "S" ? try accountRecord(Int(row.int("pointer")), code) : row
        guard resolved.str("type") == "O" else { throw Failure.missingAccount }
        return resolved
    }

    public var accounts: [Account] {
        store.all(accountsPath).compactMap {
            let row = Record(BookkeepingRecords.nlLayout, bytes: $0.data)
            guard row.str("type") == "O" else { return nil }
            return Account(code: Int(row.int("owning")), child: Int(row.int("sub-nominal")),
                           name: Cobol.rtrim(row.str("name")), category: Category(rawValue: row.str("ac")),
                           debit: row.int("dr"), credit: row.int("cr"))
        }
    }

    public func saveAccount(code: Int, child: Int = 0, name: String, category: Category, editing: Bool) throws {
        guard (1...99999).contains(code), (0...99999).contains(child), child != code, !name.isEmpty,
              Cobol.rtrim(SJIS.decode(SJIS.encode(name, size: 24)[...])) == name else { throw Failure.invalidInput }
        let key = accountKey(code, child)
        var row = editing ? try accountRecord(code, child) : Record(BookkeepingRecords.nlLayout)
        if child != 0, !editing {
            _ = try accountRecord(code)
            guard store.read(accountsPath, key: accountKey(child)) == nil else { throw Failure.duplicateAccount }
        }
        row.setInt("owning", Int64(code))
        row.setInt("sub-nominal", Int64(child))
        row["type"] = "O"
        row["name"] = name
        row["ac"] = category.rawValue
        if editing {
            guard store.rewrite(accountsPath, key: key, data: row.bytes) else { throw Failure.missingAccount }
        } else {
            guard store.write(accountsPath, key: key, data: row.bytes) else { throw Failure.duplicateAccount }
            if child != 0 {
                row.setInt("pointer", Int64(code))
                row.setInt("owning", Int64(child))
                row.setInt("sub-nominal", 0)
                row["type"] = "S"
                store.write(accountsPath, key: accountKey(child), data: row.bytes)
            }
        }
    }

    var defaultBytes: [UInt8] {
        let raw = readLine(defaultsPath) ?? [UInt8](repeating: 0x30, count: 256)
        return Array(raw.prefix(256)) + [UInt8](repeating: 0x20, count: max(0, 256 - raw.count))
    }

    public var defaults: [DefaultAccount] {
        let config = defaultBytes
        return (1...32).map { index in
            let offset = index - 1
            let number = Cobol.numval(SJIS.decode(config[(5 * offset)..<(5 * offset + 5)])).0
            let label = Cobol.rtrim(SJIS.decode(config[(160 + 2 * offset)..<(162 + 2 * offset)]))
            let taxCode = SJIS.decode(config[(224 + offset)..<(225 + offset)])
            return DefaultAccount(id: index, account: Int(number), label: number == 0 && label == "00" ? "" : label,
                                  tax: taxCode == "Y" ? .input : (DefaultTax(rawValue: taxCode) ?? .none))
        }
    }

    public func saveDefault(slot: Int, account: Int, label: String, tax: DefaultTax) throws {
        guard (1...32).contains(slot), (0...99999).contains(account) else { throw Failure.invalidInput }
        if account != 0 { _ = try accountRecord(account) }
        let reserved: [Int: String] = [30: "OB", 31: "VI", 32: "VO"]
        let name = reserved[slot] ?? label.uppercased()
        guard Cobol.rtrim(SJIS.decode(SJIS.encode(name, size: 2)[...])) == name else { throw Failure.invalidInput }
        let index = slot - 1
        var bytes = defaultBytes
        bytes.replaceSubrange((5 * index)..<(5 * index + 5), with: Array(Cobol.z(account, 5).utf8))
        bytes.replaceSubrange((160 + 2 * index)..<(162 + 2 * index), with: SJIS.encode(name, size: 2))
        let taxCode = reserved[slot] == nil ? tax : .none
        bytes[224 + index] = SJIS.encode(taxCode.rawValue, size: 1)[0]
        try writeLine(defaultsPath, bytes)
    }
}
