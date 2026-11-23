import Foundation

public struct LedgerBatchStatus {
    public struct Row: Identifiable {
        public enum Ledger: Int64 { case general = 1, purchases, sales }
        public enum State: String { case open, waiting, processed, archived }

        public let ledger: Ledger
        public let number: Int64
        public let state: State
        public let day: Int64
        public let items: Int64
        public let expectedGross: Int64
        public let expectedTax: Int64
        public let actualGross: Int64
        public let actualTax: Int64
        public var id: String { "\(ledger.rawValue)-\(number)" }
    }

    public static let reportPath = "ledgers/acas/prt-1"
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    private var settings: CompanySettings { CompanySetup(context).settings }

    public var cycle: Int64 { settings.number("scycle") }

    public var rows: [Row] {
        let company = settings
        let cycle = company.number("scycle")
        let batches = IndexedFile(context.store, path: "ledgers/acas/batch.dat", layout: LedgerBatches.batchLayout, keyLength: 6)
        var day = company.number("run-date")
        return batches.allRecords().compactMap { record in
            guard record.int("cycle") == cycle, let ledger = Row.Ledger(rawValue: record.int("ledger")) else { return nil }
            let state: Row.State
            if record.int("status") == 0 {
                state = .open
            } else {
                switch record.int("cleared") {
                case 1: state = .processed
                case 2: state = .archived
                default: state = .waiting
                }
            }
            if let last = ["stored", "posted", "proofed", "entered"].map({ record.int($0) }).first(where: { $0 > 0 }) {
                day = last
            }
            return Row(ledger: ledger, number: record.int("number"), state: state, day: day, items: record.int("items"),
                       expectedGross: record.int("input-gross"), expectedTax: record.int("input-vat"),
                       actualGross: record.int("actual-gross"), actualTax: record.int("actual-vat"))
        }
    }

    public func generateReport() throws {
        let company = settings
        let dateForm = Int(company.number("date-form"))
        let pageLines = Int(company.number("page-lines"))
        var output: [UInt8] = []
        var page: Int64 = 0
        var lineCount = 0
        func after(_ lines: Int, _ text: String) {
            output += [UInt8](repeating: 10, count: lines) + SJIS.encode(text, size: 132)
        }
        func headings() {
            page += 1
            if page != 1 { output.append(12) }
            output += SJIS.encode(Cobol.x("gl060 (3.00.04)", 31) + Cobol.x("Batch Status Report", 41)
                                   + "Page -" + Pic.edit("z9", value: page, scale: 0), size: 132)
            let today = Self.date(company.number("run-date"), form: dateForm)
            after(1, "Cycle - " + Pic.edit("z9", value: cycle, scale: 0) + Cobol.x("", 60) + today)
            if page != 1 { after(1, "") } else { output.append(10) }
            after(1, Cobol.x("Ledger  Batch  Status       Last", 48) + "---------Batch Controls---------")
            after(1, Cobol.x("------  -----  ------     Activity", 48) + "Items  ---Gross---- -----VAT----")
            after(1, "")
            lineCount = 6
        }
        func amounts(_ label: String, _ items: Int64, _ gross: Int64, _ tax: Int64) -> String {
            Cobol.x(label, 9) + Pic.edit("z9bbbb", value: items, scale: 0)
                + Pic.edit("z(8)9.99b", value: gross, scale: 2)
                + (tax == 0 ? Cobol.x("", 12) : Pic.edit("z(8)9.99", value: tax, scale: 2))
        }
        headings()
        for row in rows {
            let ledgers = [Row.Ledger.general: " G/L", .purchases: " P/L", .sales: " S/L"]
            let header = Cobol.x(ledgers[row.ledger]!, 8) + Pic.edit("z(4)9bb", value: row.number, scale: 0)
                + Cobol.x(row.state.rawValue.capitalized, 11) + Cobol.x(Self.date(row.day, form: dateForm), 14)
            after(2, header + amounts("Header", row.items, row.expectedGross, row.expectedTax))
            lineCount += 2
            if lineCount > pageLines { headings() }
            after(1, Cobol.x("", 40) + amounts("Actual", row.items, row.actualGross, row.actualTax))
            lineCount += 1
        }
        try context.store.writeRaw(Self.reportPath, output)
    }

    private static func date(_ day: Int64, form: Int) -> String {
        day > 0 ? Maps04.format(Maps04.toDate(Int(day)), dateForm: form) : ""
    }
}
