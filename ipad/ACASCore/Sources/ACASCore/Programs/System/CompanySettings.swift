import Foundation

public struct CompanySettings {
    var record: Record

    public func text(_ key: String) -> String { Cobol.rtrim(record.str(key)) }
    public func number(_ key: String) -> Int64 { record.int(key) }

    public mutating func setText(_ value: String, for key: String) throws {
        let value = Self.uppercaseFields.contains(key) ? value.uppercased() : value
        guard let field = record.layout.fields[key], case .x(let width) = field.type,
              !["user-code", "pass-word", "file-statuses", "rdbms-passwd"].contains(key),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Cobol.rtrim(SJIS.decode(SJIS.encode(value, size: width)[...])) == Cobol.rtrim(value)
        else { throw CompanySetup.Error.invalidField }
        record[key] = value
    }

    private static let uppercaseFields: Set<String> = [
        "p-c", "p-c-level", "p-c-grouped", "comps", "ledger-2nd-index", "m-v", "arch", "vat",
        "irs-instead", "sl-own-nos", "sl-stock-link", "sl-vat-printed", "sl-comp-head-inv", "sl-comp-head-stat",
        "sl-comp-head-lets", "sl-comp-head-pick", "pl-stock-link", "stk-period-cur", "stk-period-dat",
    ]

    public mutating func setNumber(_ value: Int64, for key: String) throws {
        guard let field = record.layout.fields[key], value >= 0 else { throw CompanySetup.Error.invalidField }
        let maxValue: Int64
        switch field.type {
        case .native(let bytes, let signed): maxValue = (1 << (8 * bytes - (signed ? 1 : 0))) - 1
        case .n9(let digits, _, _), .comp(let digits, _, _), .comp3(let digits, _, _):
            maxValue = Cobol.pow10(digits) - 1
        default: throw CompanySetup.Error.invalidField
        }
        guard value <= maxValue, key != "sl-credit" || value <= 99 else {
            throw CompanySetup.Error.invalidField
        }
        switch key {
        case "page-lines": record.setInt(key, value <= 28 ? 48 : value)
        case "period": record.setInt(key, value == 13 || value == 6 ? value : 3)
        default: record.setInt(key, value)
        }
    }

    public mutating func setDate(year: Int, month: Int, day: Int, for key: String) throws {
        guard ["start-date", "end-date"].contains(key), Maps04.validYMD(year, month, day)
        else { throw CompanySetup.Error.invalidDate }
        record.setInt(key, Int64(Maps04.integerOfDate(year: year, month: month, day: day)))
    }
}

public struct SystemReportPaths: Codable {
    public let incompleteRecords: String
    public let ledgers: String

    public init(incompleteRecords: String = "", ledgers: String = "") {
        self.incompleteRecords = incompleteRecords
        self.ledgers = ledgers
    }

    public var isValid: Bool {
        [incompleteRecords, ledgers].allSatisfy { label in
            label.utf8.count <= 1024 && !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
    }
}
