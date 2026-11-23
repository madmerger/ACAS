import Foundation

public struct LedgerDefault: Identifiable {
    public let id: Int
    public let account: String
    public let transactionCode: String
    public let tax: LedgerDefaultTax?
}

public enum LedgerDefaultTax: String, CaseIterable {
    case input = "I"
    case noTax = "N"
    case output = "O"
}

public struct GeneralLedgerSetup {
    public enum Error: Swift.Error { case missingCompany, invalidDate, invalidDefault }

    private let context: BusinessContext
    private var system: RelativeFile {
        RelativeFile(context.store, path: "ledgers/acas/system.dat", recordSize: 1024)
    }

    public init(_ context: BusinessContext) { self.context = context }

    public func start(year: Int, month: Int, day: Int) throws {
        guard Maps04.validYMD(year, month, day) else { throw Error.invalidDate }
        guard let bytes = system.read(1) else { throw Error.missingCompany }
        var setup = Record(SystemLayout.layout, bytes: bytes)
        setup.setInt("run-date", Int64(Maps04.integerOfDate(year: year, month: month, day: day)))
        try system.write(1, setup.bytes)
    }

    public var defaults: [LedgerDefault] {
        let record = Record(Self.layout, bytes: system.read(2) ?? SystemAuxRecords.initialDefault())
        return (1...33).map { number in
            LedgerDefault(id: number,
                          account: Cobol.z(record.int("account\(number)"), 6),
                          transactionCode: Cobol.rtrim(record.str("code\(number)")),
                          tax: LedgerDefaultTax(rawValue: record.str("tax\(number)")))
        }
    }

    @discardableResult
    public func saveDefault(number: Int, account: String, transactionCode: String, tax: LedgerDefaultTax) throws -> Bool {
        guard let before = system.read(2) else { throw Error.missingCompany }
        guard (1...32).contains(number), account.utf8.count == 6, account.utf8.allSatisfy({ (48...57).contains($0) }),
              let code = Int64(account),
              !transactionCode.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Cobol.rtrim(SJIS.decode(SJIS.encode(transactionCode, size: 2)[...])) == Cobol.rtrim(transactionCode)
        else { throw Error.invalidDefault }
        var record = Record(Self.layout, bytes: before)
        record.setInt("account\(number)", code)
        let exists = ChartOfAccounts(context).account(code: account) != nil
        if exists {
            record["code\(number)"] = transactionCode
            record["tax\(number)"] = tax.rawValue
        }
        try system.write(2, record.bytes)
        return exists
    }

    private static let layout = Layout(
        "default-record",
        (1...33).map { ("account\($0)", FieldType.comp(digits: 6, scale: 2, signed: false)) } +
        (1...33).map { ("code\($0)", FieldType.x(2)) } +
        (1...33).map { ("tax\($0)", FieldType.x(1)) } +
        [("", .filler(1024 - 231))]
    )
}
