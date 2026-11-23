import Foundation

public enum LedgerDirection: String, CaseIterable {
    case debit = "DR"
    case credit = "CR"
}

public struct JournalLine: Identifiable {
    public let id = UUID()
    public let date: DateComponents
    public let account: String
    public let branch: String
    public let amount: Int64
    public let memo: String

    public init(date: DateComponents, account: String, branch: String = "00", amount: Int64, memo: String) {
        self.date = date
        self.account = account
        self.branch = branch
        self.amount = amount
        self.memo = memo
    }
}

public struct LedgerBatchDraft {
    public let cycle: Int
    public let defaultNumber: Int
    public let direction: LedgerDirection
    public let date: DateComponents
    public var description = ""
    public var expectedItems = 0
    public var gross: Int64 = 0
    public var tax: Int64 = 0

    public init(cycle: Int, defaultNumber: Int, direction: LedgerDirection, date: DateComponents) {
        self.cycle = cycle
        self.defaultNumber = defaultNumber
        self.direction = direction
        self.date = date
    }
}

public struct LedgerBatch: Identifiable {
    public let id: Int
    public let description: String
    public let cycle: Int
    public let items: Int
    public let gross: Int64
    public let closed: Bool
    public let posted: Bool

    fileprivate init(_ record: Record) {
        id = Int(record.int("number"))
        cycle = Int(record.int("cycle"))
        description = Cobol.rtrim(record.str("description"))
        items = Int(record.int("items"))
        gross = record.int("input-gross")
        closed = record.int("status") == 1
        posted = record.int("cleared") != 0
    }
}

public struct LedgerBatches {
    public enum Error: Swift.Error {
        case missingCompany, cycle, missingDefault, date, items, amount, account, text, capacity, storage
    }

    private static let batchPath = "ledgers/acas/batch.dat"
    private static let postingPath = "ledgers/acas/posting.dat"
    private static let money = FieldType.comp3(digits: 11, scale: 2, signed: false)
    private static let lineMoney = FieldType.n9(digits: 10, scale: 2, signed: true)
    private static let bin = FieldType.native(bytes: 4, signed: true)

    private static func number(_ key: String, _ digits: Int) -> (String, FieldType) {
        (key, .n9(digits: digits, scale: 0, signed: false))
    }

    static let batchLayout = Layout("batch-record", [
        number("ledger", 1), number("number", 5), number("items", 2), number("status", 1),
        number("cleared", 1), number("cycle", 2), ("entered", bin), ("proofed", bin), ("posted", bin), ("stored", bin),
        ("input-gross", money), ("input-vat", money), ("actual-gross", money), ("actual-vat", money),
        ("description", .x(24)), number("default", 2), ("direction", .x(2)), number("default-account", 6),
        number("default-branch", 2), ("default-code", .x(2)), ("default-vat", .x(1)), number("start", 5),
    ])
    static let postingLayout = Layout("posting-record", [
        number("batch", 5), number("sequence", 5), ("code", .x(2)), ("date", .x(8)),
        number("debit", 6), number("debit-branch", 2), number("credit", 6), number("credit-branch", 2),
        ("amount", lineMoney), ("memo", .x(32)), number("vat-account", 6), number("vat-branch", 2),
        ("vat-side", .x(2)), ("vat-amount", lineMoney),
    ])

    private let context: BusinessContext
    private var system: RelativeFile { RelativeFile(context.store, path: "ledgers/acas/system.dat", recordSize: 1024) }
    private var batches: IndexedFile { IndexedFile(context.store, path: Self.batchPath, layout: Self.batchLayout, keyLength: 6) }
    private var postings: RelativeFile { RelativeFile(context.store, path: Self.postingPath, recordSize: Self.postingLayout.size) }

    public init(_ context: BusinessContext) { self.context = context }

    public var all: [LedgerBatch] {
        batches.allRecords().filter { $0.int("ledger") == 1 }.map(LedgerBatch.init)
    }

    public func prepare() throws {
        try context.store.transaction { try prepareFiles() }
    }

    private func prepareFiles() throws {
        if !context.store.exists(Self.batchPath) {
            var end = Record(Self.batchLayout)
            end.setInt("ledger", 9)
            end.setInt("number", 99999)
            end.setInt("cycle", 99)
            guard batches.write(end) == "00" else { throw Error.storage }
        }
        if !postings.exists { try postings.write(1, Record(Self.postingLayout).bytes) }
    }

    public func add(_ draft: LedgerBatchDraft, lines: [JournalLine]) throws -> Int {
        try context.store.transaction { try insert(draft, lines: lines) }
    }

    private func insert(_ draft: LedgerBatchDraft, lines: [JournalLine]) throws -> Int {
        guard let bytes = system.read(1) else { throw Error.missingCompany }
        var settings = Record(SystemLayout.layout, bytes: bytes)
        let cycle = Int(settings.int("scycle"))
        guard (cycle...cycle + 1).contains(draft.cycle) else { throw Error.cycle }
        let chart = ChartOfAccounts(context)
        guard (1...32).contains(draft.defaultNumber),
              let template = GeneralLedgerSetup(context).defaults.first(where: { $0.id == draft.defaultNumber }),
              chart.account(code: template.account) != nil else { throw Error.missingDefault }
        guard (0...99).contains(draft.expectedItems), (1...99).contains(lines.count) else { throw Error.items }
        guard (0..<100_000_000_000).contains(draft.gross), (0...draft.gross).contains(draft.tax) else { throw Error.amount }
        let entered = try Self.date(draft.date)
        let number = Int(settings.int("next-batch"))
        let start = Int(settings.int("postings")) + 1
        guard (1..<32_767).contains(number), (1..<32_767).contains(start),
              start + lines.count <= 32_767 else { throw Error.capacity }
        let branchEnabled = ["P", "B"].contains(settings.str("p-c"))

        var batch = Record(Self.batchLayout)
        for (field, value): (String, Int64) in [
            ("ledger", 1), ("number", Int64(number)), ("start", Int64(start)), ("cycle", Int64(draft.cycle)),
            ("entered", Int64(entered)), ("items", Int64(draft.expectedItems)), ("input-gross", draft.gross),
            ("input-vat", draft.tax), ("default", Int64(draft.defaultNumber)),
            ("default-account", Int64(template.account) ?? 0),
        ] { batch.setInt(field, value) }
        batch["default-code"] = template.transactionCode
        batch["default-vat"] = template.tax?.rawValue ?? ""
        batch["direction"] = draft.direction.rawValue
        batch["description"] = try Self.checked(draft.description, width: 24)

        let records = try lines.enumerated().map { index, line -> Record in
            let branch = branchEnabled ? line.branch : "00"
            guard chart.account(code: line.account, branch: branch) != nil else { throw Error.account }
            guard line.amount != 0, (-9_999_999_999...9_999_999_999).contains(line.amount) else { throw Error.amount }
            let date = Maps04.dateOfInteger(try Self.date(line.date))
            var posting = Record(Self.postingLayout)
            posting.setInt("batch", Int64(number))
            posting.setInt("sequence", Int64(index + 1))
            posting["code"] = template.transactionCode
            posting["date"] = Cobol.z(date.day, 2) + "/" + Cobol.z(date.month, 2) + "/" + Cobol.z(date.year % 100, 2)
            let debit = draft.direction == .debit
            posting["debit"] = debit ? line.account : template.account
            posting["credit"] = debit ? template.account : line.account
            posting["debit-branch"] = debit ? branch : "00"
            posting["credit-branch"] = debit ? "00" : branch
            posting.setInt("amount", line.amount)
            posting["memo"] = try Self.checked(line.memo, width: 32)
            posting["vat-side"] = draft.direction.rawValue
            return posting
        }
        guard batches.read(key: batches.key(of: batch)) == nil else { throw Error.storage }
        try prepareFiles()
        for (index, record) in records.enumerated() { try postings.write(start + index + 1, record.bytes) }
        guard batches.write(batch) == "00" else { throw Error.storage }
        settings.setInt("next-batch", Int64(number + 1))
        settings.setInt("postings", Int64(start + records.count - 1))
        try system.write(1, settings.bytes)
        return number
    }

    private static func date(_ components: DateComponents) throws -> Int {
        guard let year = components.year, let month = components.month, let day = components.day,
              Maps04.validYMD(year, month, day) else { throw Error.date }
        return Maps04.integerOfDate(year: year, month: month, day: day)
    }

    private static func checked(_ value: String, width: Int) throws -> String {
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Cobol.rtrim(SJIS.decode(SJIS.encode(value, size: width)[...])) == Cobol.rtrim(value)
        else { throw Error.text }
        return value
    }
}
