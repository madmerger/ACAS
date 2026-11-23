import Foundation

extension BookkeepingService {
    public struct StatementSettings {
        public var headings: [String]
        public var signs: [String]
        public var appropriationAccount: Int
    }

    public var statementSettings: StatementSettings {
        let record = readLine(directory + "final.dat") ?? []
        let system = self.system
        let bytes = record.prefix(655) + Array(repeating: UInt8(ascii: " "), count: max(0, 655 - record.count))
        return StatementSettings(
            headings: (0..<26).map { Cobol.rtrim(SJIS.decode(bytes[($0 * 24)..<(($0 + 1) * 24)])) },
            signs: (624..<650).map { Cobol.rtrim(SJIS.decode(bytes[$0..<($0 + 1)])) },
            appropriationAccount: system.str("pl-app-created") == "1" ? Int(system.int("pl-approp-ac")) : 0
        )
    }

    public func saveStatementSettings(_ settings: StatementSettings) throws {
        guard settings.headings.count == 26, settings.signs.count == 26,
              (0...99999).contains(settings.appropriationAccount) else { throw Failure.invalidInput }
        if settings.appropriationAccount != 0 { _ = try accountRecord(settings.appropriationAccount) }
        func encode(_ field: String, width: Int) throws -> [UInt8] {
            let bytes = SJIS.encode(field, size: width)
            guard !field.contains(where: \.isNewline),
                  Cobol.rtrim(SJIS.decode(bytes[...])) == Cobol.rtrim(field) else { throw Failure.invalidInput }
            return bytes
        }
        var bytes = try settings.headings.flatMap { try encode($0, width: 24) }
        bytes += try settings.signs.flatMap { try encode($0, width: 1) }
        let path = directory + "final.dat"
        let trailing = (readLine(path) ?? []).dropFirst(650).prefix(5)
        bytes += trailing + Array(repeating: UInt8(ascii: " "), count: 5 - trailing.count)
        try store.transaction {
            try writeLine(path, bytes)
            if settings.appropriationAccount != statementSettings.appropriationAccount {
                var row = system
                row["pl-app-created"] = settings.appropriationAccount == 0 ? "0" : "1"
                row.setInt("pl-approp-ac", Int64(settings.appropriationAccount))
                try writeLine(systemPath, row.bytes)
            }
        }
    }
}
