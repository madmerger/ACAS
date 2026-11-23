import Foundation

public struct SalesDunning {
    public enum Error: Swift.Error { case missingOpenItems, dateNotAccepted }

    static let letterPaths = ["letter.001", "letter.002", "letter.003"]
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func prepare() throws -> Date {
        let store = context.store
        let invoices = SalesInvoices(context)
        var day: Int?
        try store.withTransaction {
            var system = try invoices.settings()
            guard system.raw("file-statuses")[18] == 0x31 else {
                if system.str("oi-3-flag") != "N" {
                    system["oi-3-flag"] = "Y"
                    try invoices.systemFile.write(1, system.bytes)
                }
                return
            }
            guard store.exists(SalesOpenItems.path) else { return }
            try SalesOpenItemSort.prepare(store, system: &system)
            if system.int("date-form") == 0 { system.setInt("date-form", 1) }
            day = Int(system.int("run-date"))
            for path in Self.letterPaths { try store.writeRaw(path, []) }
            try invoices.systemFile.write(1, system.bytes)
        }
        guard let day else { throw Error.missingOpenItems }
        guard (1...3_067_671).contains(day) else { return context.now() }
        let date = Maps04.dateOfInteger(day)
        return context.calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) ?? context.now()
    }

    public func confirmDate(_: Date) throws {
        // SL190 accepts into ws-date, then validates the untouched ws-test-date.
        throw Error.dateNotAccepted
    }
}

enum SalesOpenItemSort {
    static let path = "ledgers/acas/oisort.wrk"

    static func prepare(_ store: FileStore, system: inout Record) throws {
        guard system.str("oi-3-flag") != "N" else { return }
        let items = SalesOpenItems.file(store).allRecords().sorted { lhs, rhs in
            if lhs.raw("customer") != rhs.raw("customer") {
                return lhs.raw("customer").lexicographicallyPrecedes(rhs.raw("customer"))
            }
            for field in ["date", "invoice", "type"] where lhs.int(field) != rhs.int(field) {
                return lhs.int(field) < rhs.int(field)
            }
            return false
        }
        try store.writeRaw(path, items.flatMap(\.bytes))
        system["oi-3-flag"] = "N"
    }
}
