import Foundation

public struct CompanySetup {
    public enum Error: Swift.Error { case invalidName }
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
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, Cobol.rtrim(SJIS.decode(SJIS.encode(name, size: 32)[...])) == name else { throw Error.invalidName }
        var record: Record
        if let existing = file.read(1) {
            record = Record(SystemLayout.layout, bytes: existing)
        } else {
            record = SystemAuxRecords.initialSystem()
            let day = context.calendar.dateComponents([.year, .month, .day], from: context.now())
            let runDate = Maps04.integerOfDate(year: day.year!, month: day.month!, day: day.day!)
            for (field, value): (String, Int64) in [
                ("system-record-version-prime", 1), ("system-record-version-secondary", 1),
                ("date-form", 1), ("run-date", Int64(runDate)), ("op-system", 1), ("sales-range", 1),
                ("purchase-range", 2), ("next-batch", 1), ("sl-dunning", 1), ("sl-charges", 1),
                ("sl-credit", 30), ("invoicer", 2), ("maps-ser-nn", 9999),
            ] { record.setInt(field, value) }
            record["sl-delim"] = "\\"
            record["sl-own-nos"] = "N"
            record["maps-ser-xx"] = "mp"
        }
        record["usera"] = name
        file.write(1, record.bytes)
        if file.read(2) == nil { file.write(2, SystemAuxRecords.initialDefault()) }
        if file.read(3) == nil { file.write(3, SystemAuxRecords.initialFinal()) }
        if file.read(4) == nil { file.write(4, SystemAuxRecords.initialRecord4()) }
    }
}
