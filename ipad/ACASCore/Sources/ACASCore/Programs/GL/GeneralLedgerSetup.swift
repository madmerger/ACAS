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

public struct TemporaryLedgerDefault {
    public let account: String
    public let code: String
    public let tax: LedgerDefaultTax

    public init(account: String, code: String, tax: LedgerDefaultTax) {
        self.account = account
        self.code = code
        self.tax = tax
    }
}

public struct GeneralLedgerSetup {
    public enum Error: Swift.Error { case missingCompany, invalidDate, invalidDefault, invalidPassword }

    private let context: BusinessContext
    private var system: RelativeFile {
        RelativeFile(context.store, path: "ledgers/acas/system.dat", recordSize: 1024)
    }

    public init(_ context: BusinessContext) { self.context = context }

    public var processingDate: Date {
        let stored = Int(CompanySetup(context).settings.number("run-date"))
        guard stored > 0 else { return context.now() }
        let date = Maps04.dateOfInteger(stored)
        return context.calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))
            ?? context.now()
    }

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

    public func resetDefaults(password: String) throws {
        let alphabet = Array("CKQUAELSMWYIZJRPBXFVGNODTH".utf8)
        let input = Array(password.uppercased().utf8)
        guard input.count == 4 else { throw Error.invalidPassword }
        var encoded = Array(repeating: UInt8(32), count: 4)
        for (index, byte) in input.enumerated() {
            guard let letter = alphabet.firstIndex(of: byte) else { throw Error.invalidPassword }
            let position = abs(letter + 1 + (index + 1) * (index + 1) + 3 - 26)
            if position != 0 { encoded[3 - index] = alphabet[position - 1] }
        }
        try context.store.transaction {
            guard let setup = system.read(1), var defaults = system.read(2) else { throw Error.missingCompany }
            guard Record(SystemLayout.layout, bytes: setup).raw("pass-word") == encoded
            else { throw Error.invalidPassword }
            defaults.replaceSubrange(0..<231, with: SystemAuxRecords.initialDefault().prefix(231))
            try system.write(2, defaults)
        }
    }

    @discardableResult
    public func saveDefault(number: Int, account: String, transactionCode: String, tax: LedgerDefaultTax) throws -> Bool {
        guard (1...32).contains(number) else { throw Error.invalidDefault }
        return try writeDefault(number: number, account: account, transactionCode: transactionCode, tax: tax)
    }

    func writeDefault(number: Int, account: String, transactionCode: String, tax: LedgerDefaultTax,
                      branch: String = "00", requireAccount: Bool = false) throws -> Bool {
        guard let before = system.read(2) else { throw Error.missingCompany }
        guard account.utf8.count == 6, account.utf8.allSatisfy({ (48...57).contains($0) }),
              let code = Int64(account),
              !transactionCode.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Cobol.rtrim(SJIS.decode(SJIS.encode(transactionCode, size: 2)[...])) == Cobol.rtrim(transactionCode)
        else { throw Error.invalidDefault }
        var record = Record(Self.layout, bytes: before)
        record.setInt("account\(number)", code)
        let exists = ChartOfAccounts(context).account(code: account, branch: branch) != nil
        if requireAccount && !exists { throw Error.invalidDefault }
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
