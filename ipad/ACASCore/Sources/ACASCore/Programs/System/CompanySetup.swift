import Foundation

public struct CompanySetup {
    public enum Error: Swift.Error { case invalidName, invalidDate, invalidField }
    public let context: BusinessContext
    private var file: RelativeFile {
        RelativeFile(context.store, path: "ledgers/acas/system.dat", recordSize: 1024)
    }

    public init(_ context: BusinessContext) { self.context = context }

    public var name: String {
        guard let data = file.read(1) else { return "" }
        return Cobol.rtrim(Record(SystemLayout.layout, bytes: data).str("usera"))
    }

    public func save(name: String) throws {
        var settings = settings
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, Cobol.rtrim(SJIS.decode(SJIS.encode(name, size: 32)[...])) == name else { throw Error.invalidName }
        try settings.setText(name, for: "usera")
        try save(settings)
    }

    public var settings: CompanySettings {
        if let existing = file.read(1) {
            return CompanySettings(record: Record(SystemLayout.layout, bytes: existing))
        }
        var record = SystemAuxRecords.initialSystem()
        let day = context.calendar.dateComponents([.year, .month, .day], from: context.now())
        let runDate = Maps04.integerOfDate(year: day.year!, month: day.month!, day: day.day!)
        for (field, value): (String, Int64) in [
            ("system-record-version-prime", 1), ("system-record-version-secondary", 1),
            ("date-form", 1), ("run-date", Int64(runDate)), ("op-system", 1), ("sales-range", 1),
            ("purchase-range", 2), ("next-batch", 1), ("sl-dunning", 1), ("sl-charges", 1),
            ("sl-credit", 30), ("invoicer", 2), ("maps-ser-nn", 9999),
            ("page-lines", 48), ("period", 3),
        ] { record.setInt(field, value) }
        record["sl-delim"] = "\\"
        record["sl-own-nos"] = "N"
        record["maps-ser-xx"] = "mp"
        return CompanySettings(record: record)
    }

    public var archivePaths: SystemReportPaths {
        guard let bytes = context.store.readRaw(Self.archivePathsKey),
              let paths = try? JSONDecoder().decode(SystemReportPaths.self, from: Data(bytes)) else { return .init() }
        return paths
    }

    public func prepareInitialRecord(_ settings: CompanySettings) throws {
        try context.store.transaction {
            guard file.read(1) == nil else { return }
            let name = Cobol.rtrim(settings.record.str("usera"))
            guard !name.isEmpty else { throw Error.invalidName }
            var record = self.settings.record
            record["usera"] = name
            record["user-code"] = LegacyCompanyCode.encode(name)
            record["pass-word"] = "CEJE"
            for field in ["level-1", "level-2", "level-3", "level-4", "level-5", "full-invoicing"] {
                record.setInt(field, settings.record.int(field))
            }
            record.setInt("page-lines", 0)
            record.setInt("period", 0)
            try file.write(1, record.bytes)
            try prepareAuxiliaryRecords()
        }
    }

    public func save(_ settings: CompanySettings, printReport: Bool = false,
                     archivePaths: SystemReportPaths? = nil) throws {
        var record = settings.record
        guard !Cobol.rtrim(record.str("usera")).isEmpty else { throw Error.invalidName }
        let paths = archivePaths ?? self.archivePaths
        guard paths.isValid else { throw Error.invalidField }
        if let archivePaths {
            let bytes = try JSONEncoder().encode(archivePaths)
            try context.store.writeRaw(Self.archivePathsKey, Array(bytes))
        }
        if let stored = file.read(1) {
            let initial = Record(SystemLayout.layout, bytes: stored)
            for field in ["user-code", "pass-word", "file-statuses", "sales-ledger", "purchase-ledger", "stock-control"] {
                record.setRaw(field, initial.raw(field))
            }
        } else {
            record["user-code"] = LegacyCompanyCode.encode(record.str("usera"))
            record["pass-word"] = "CEJE"
        }
        try file.write(1, record.bytes)
        try prepareAuxiliaryRecords()
        if printReport { try context.store.writeRaw(Self.reportPath, SystemSettingsReport.render(record, paths: paths)) }
    }

    private func prepareAuxiliaryRecords() throws {
        if file.read(2) == nil { try file.write(2, SystemAuxRecords.initialDefault()) }
        if file.read(3) == nil { try file.write(3, SystemAuxRecords.initialFinal()) }
        if file.read(4) == nil { try file.write(4, SystemAuxRecords.initialRecord4()) }
    }

    public static let reportPath = "ledgers/acas/prt-1"
    private static let archivePathsKey = "system/report-path-labels"

    func markFiles(_ positions: [Int], module: String) throws {
        guard let bytes = file.read(1) else { return }
        var record = Record(SystemLayout.layout, bytes: bytes)
        let start = record.layout.offset("file-statuses")
        for position in positions { record.bytes[start + position - 1] = 0x31 }
        record[module] = "Y"
        if record.bytes != bytes { try file.write(1, record.bytes) }
    }
}

private enum LegacyCompanyCode {
    static func encode(_ name: String) -> String {
        let alphabet = Array("CKQUAELSMWYIZJRPBXFVGNODTH".utf8)
        let raw = SJIS.encode(name, size: 32)
        var result = [UInt8](repeating: 32, count: 32)
        for position in 1...31 {
            let byte = raw[position - 1]
            let upper = (97...122).contains(byte) ? byte - 32 : byte
            guard let index = alphabet.firstIndex(of: upper) else { continue }
            var base = (2 * (position + 51) + position) / (2 * position)
            if base > 25 { base -= 26 }
            var value = abs(index + 1 + base - 27)
            if value > 26 { value -= 26 }
            if value > 0 { result[position - 1] = alphabet[value - 1] }
        }
        return String(decoding: result, as: UTF8.self)
    }
}
