import Foundation

public struct LedgerAccount: Identifiable {
    public let code: String
    public let branch: String
    public let name: String
    public let type: Int
    public let placement: String
    public let level: Int
    public let balance: Int64
    public let previousBalance: Int64
    public let quarterBalances: [Int64]

    public var id: String { code + branch }

    init(_ record: Record) {
        code = record.str("code")
        branch = record.str("branch")
        name = Cobol.rtrim(record.str("name"))
        type = Int(record.int("type"))
        placement = Cobol.rtrim(record.str("placement"))
        level = Int(record.int("level"))
        balance = record.int("balance")
        previousBalance = record.int("last")
        quarterBalances = (1...4).map { record.int("q\($0)") }
    }
}

public struct ChartOfAccounts {
    public enum Error: Swift.Error {
        case invalidCode, reservedCode, invalidPrefix, invalidName, invalidType, invalidPlacement, invalidLevel
        case missingHeader, missingAccount, duplicate, nonzeroBalance
    }

    static let path = "ledgers/acas/ledger.dat"
    private static let terminator = "99999999"
    static let layout: Layout = {
        let money = FieldType.comp3(digits: 10, scale: 2, signed: true)
        return Layout("ledger-record", [
            ("code", .n9(digits: 6, scale: 0, signed: false)),
            ("branch", .n9(digits: 2, scale: 0, signed: false)),
            ("type", .n9(digits: 1, scale: 0, signed: false)),
            ("placement", .x(1)),
            ("level", .n9(digits: 1, scale: 0, signed: false)),
            ("", .filler(5)), ("name", .x(24)),
            ("balance", money), ("last", money), ("q1", money), ("q2", money), ("q3", money), ("q4", money),
            ("", .filler(50)),
        ])
    }()
    private let context: BusinessContext
    private var file: IndexedFile {
        IndexedFile(context.store, path: Self.path, layout: Self.layout, keyLength: 8)
    }

    public init(_ context: BusinessContext) { self.context = context }

    public var accounts: [LedgerAccount] {
        file.allRecords().map(LedgerAccount.init).filter { $0.id != Self.terminator }
    }

    public func accounts(startingAt code: Int, branch: Int = 0) -> [LedgerAccount] {
        let key = Cobol.z(code, 6) + Cobol.z(branch, 2)
        return accounts.filter { $0.id >= key && !$0.code.hasPrefix("9999") }
    }

    public func account(code: String, branch: String = "00") -> LedgerAccount? {
        guard Self.isDigits(code, count: 6), Self.isDigits(branch, count: 2),
              code + branch != Self.terminator
        else { return nil }
        return file.read(key: code + branch).map(LedgerAccount.init)
    }

    public func prepare() {
        guard !context.store.exists(Self.path) else { return }
        var end = newRecord()
        end["code"] = "999999"
        end["branch"] = "99"
        end["placement"] = "0"
        let name = Self.layout.offset("name")
        end.bytes.replaceSubrange(name..<(name + 24), with: repeatElement(UInt8(0), count: 24))
        file.write(end)
    }

    public func add(code: String, branch: String = "00", name: String, type: Int, placement: String,
                    level: Int, amendScreenVisited: Bool = true) throws {
        let key = try validatedKey(code, branch: branch)
        var record = newRecord()
        record["code"] = code
        record["branch"] = String(key.suffix(2))
        let usesBranches = ["P", "B"].contains(CompanySetup(context).settings.text("p-c"))
        let headerBranch = usesBranches || amendScreenVisited ? String(key.suffix(2)) : "  "
        try apply(name: name, type: type, placement: placement, level: level, to: &record, headerBranch: headerBranch)
        prepare()
        guard file.write(record) == "00" else { throw Error.duplicate }
    }

    public func amend(code: String, branch: String = "00", name: String, type: Int, placement: String, level: Int) throws {
        let key = try validatedKey(code, branch: branch)
        guard var record = file.read(key: key) else { throw Error.missingAccount }
        try apply(name: name, type: type, placement: placement, level: level, to: &record)
        guard file.rewrite(record) == "00" else { throw Error.missingAccount }
    }

    public func delete(code: String, branch: String = "00") throws {
        let key = try validatedKey(code, branch: branch)
        guard let record = file.read(key: key) else { throw Error.missingAccount }
        guard record.int("balance") == 0 else { throw Error.nonzeroBalance }
        guard file.delete(key: Array(key.utf8)) == "00" else { throw Error.missingAccount }
    }

    private func newRecord() -> Record {
        var record = Record(Self.layout)
        for field in Self.layout.order {
            if case .filler(let size) = field.type {
                record.bytes.replaceSubrange(field.offset..<(field.offset + size), with: repeatElement(UInt8(0), count: size))
            }
        }
        return record
    }

    private func validatedKey(_ code: String, branch: String) throws -> String {
        guard Self.isDigits(code, count: 6), Self.isDigits(branch, count: 2),
              let prefix = Int(code.prefix(4)), prefix >= 1000 else { throw Error.invalidCode }
        guard prefix != 9999 else { throw Error.reservedCode }
        let settings = CompanySetup(context).settings
        guard let first = Int64(code.prefix(1)), first != settings.number("sales-range"),
              first != settings.number("purchase-range") else { throw Error.invalidPrefix }
        return code + (["P", "B"].contains(settings.text("p-c")) ? branch : "00")
    }

    private func apply(name: String, type: Int, placement: String, level: Int, to record: inout Record,
                       headerBranch: String? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Cobol.rtrim(SJIS.decode(SJIS.encode(name, size: 24)[...])) == name else { throw Error.invalidName }
        let code = record.str("code")
        let branch = record.str("branch")
        record["name"] = name
        let head = String(code.prefix(4))
        if code.suffix(2) != "00" {
            guard let header = file.read(key: head + "00" + (headerBranch ?? branch)) else { throw Error.missingHeader }
            record.setInt("type", header.int("type") == 9 ? 9 : 1)
            record["placement"] = header.str("placement")
            record.setInt("level", 0)
        } else {
            guard [0, 1, 9].contains(type) else { throw Error.invalidType }
            record.setInt("type", Int64(type))
            if type == 0 {
                let placement = placement.uppercased()
                guard placement.utf8.count == 1, let byte = placement.utf8.first, (65...90).contains(byte)
                else { throw Error.invalidPlacement }
                guard (1...4).contains(level) else { throw Error.invalidLevel }
                let digits = Array(head)
                let rank = digits.lastIndex(where: { $0 != "0" }).map { $0 + 1 } ?? 1
                if rank > 1 {
                    let parent = String(digits.prefix(rank - 1)) + String(repeating: "0", count: 5 - rank)
                    guard file.read(key: parent + "00" + branch) != nil else { throw Error.missingHeader }
                }
                record["placement"] = placement
                record.setInt("level", Int64(rank))
            }
        }
    }

    private static func isDigits(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}
