import Foundation

public struct SalesAnalysis {
    public enum Error: Swift.Error {
        case invalidLayout, invalidInput, missingGroup, groupUsed, duplicate, missingCode, writeFailed
        case invalidDescription, invalidPrintCode
        case unsupportedDescription, unsupportedPrintCode
    }

    public struct Code: Identifiable {
        public var id: String { ledger + group }
        public let ledger: String
        public let group: String
        public let account: Int64
        public let description: String
        public let printCode: String
        public var isGroup: Bool { group.count == 1 && account == 0 }
    }

    public struct Totals: Identifiable {
        public var id: String { code.id }
        public let code: Code
        public let counts: [Int64]
        public let values: [Int64]
    }

    public static let exportPath = SalesProofReport.exportPath
    static let layout = SalesAnalysisFiles.layout
    private let context: BusinessContext
    private var files: SalesInvoices { SalesInvoices(context) }
    private var store: FileStore { context.store }
    private var analysis: IndexedFile { IndexedFile(store, path: SalesPosting.analysisPath, layout: Self.layout, keyLength: 3) }
    private var values: IndexedFile { IndexedFile(store, path: SalesPosting.valuePath, layout: SalesPostingRecords.value, keyLength: 3) }

    public init(_ context: BusinessContext) { self.context = context }

    public func prepare() throws {
        try store.withTransaction {
            var system = try files.settings()
            guard system.raw("file-statuses")[14] != 0x31 else { return }
            try validateRegistration()
            do {
                try SalesAnalysisFiles.initialize(store, system: &system)
            } catch SalesPosting.Error.invalidAnalysisLayout {
                throw Error.invalidLayout
            } catch SalesPosting.Error.writeFailed {
                throw Error.writeFailed
            }
            try files.systemFile.write(1, system.bytes)
        }
    }

    public func codes(allLedgers: Bool = false) throws -> [Code] {
        try validAnalysis()
        return analysis.allRecords().map(code(from:)).filter { allLedgers || $0.ledger == "S" }
    }

    public func validateRegistration() throws {
        try validAnalysis()
    }

    public func save(group: String, account: Int64, description: String, printCode: String, replacing: Bool = false) throws {
        let group = Cobol.rtrim(group)
        guard (1...2).contains(group.utf8.count), group.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
              (0...999_999).contains(account) else { throw Error.invalidInput }
        try validate(description, width: 24, overflow: .invalidDescription, unsupported: .unsupportedDescription)
        try validate(printCode, width: 3, overflow: .invalidPrintCode, unsupported: .unsupportedPrintCode)
        let key = "S" + group
        try store.withTransaction {
            try validAnalysis()
            let exists = analysis.read(key: key) != nil
            if !replacing {
                guard !exists else { throw Error.duplicate }
                if group.count == 2 {
                    guard let parent = analysis.read(key: "S" + String(group.prefix(1))) else { throw Error.missingGroup }
                    guard parent.int("account") == 0 else { throw Error.groupUsed }
                }
            } else if !exists {
                throw Error.missingCode
            }
            var row = Record(Self.layout)
            row["code"] = key
            row.setInt("account", account)
            row["description"] = description
            row["print"] = printCode
            guard (replacing ? analysis.rewrite(row) : analysis.write(row)) == "00" else { throw Error.writeFailed }
        }
    }

    public func delete(group: String) throws {
        try validAnalysis()
        guard analysis.delete(key: SJIS.encode("S" + group, size: 3)) == "00" else { throw Error.writeFailed }
    }

    public func printCodes(allLedgers: Bool) throws -> [Code] {
        let entries = try codes(allLedgers: allLedgers)
        let system = try files.settings()
        let irs = system.str("irs-instead") == "Y"
        let printer = SalesProofRecords.Printer(store)
        var page: Int64 = 0
        var lines = 0
        func headings() {
            page += 1
            let first = Cobol.x("SL070 (3.01.11)", 33) + Cobol.x("Product Analysis Codes", 39)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            if page == 1 {
                printer.before(1, first)
            } else {
                printer.afterPage(first)
                printer.after(1, "")
            }
            printer.after(1, fixed(system.str("usera"), 30) + Cobol.x("", 40) + date(system))
            printer.after(2, Cobol.x(allLedgers ? "Lgr" : "", 4)
                + Cobol.x("Code    Gl.Nos.      <-----Description------>   Print", 59) + "-Type-")
            lines = 5
        }
        var warning = false
        var ledger = " "
        headings()
        for entry in entries {
            if entry.isGroup {
                printer.after(1, "")
                lines += 1
                if allLedgers { ledger = entry.ledger }
            } else {
                ledger = " "
            }
            if lines > 70 { headings() }
            if entry.group.count == 2 && entry.account == 0 { warning = true }
            let account = irs ? entry.account : entry.account / 100
            let accountText = account == 0 ? Cobol.x("", 6) : Cobol.z(account, 6)
            let fields = " " + ledger + Cobol.x("", 3) + Cobol.x(entry.group, 7) + accountText
            let detail = fixed(entry.description, 24) + Cobol.x("", 4) + fixed(entry.printCode, 3)
            printer.after(1, fields + Cobol.x("", 7) + detail + Cobol.x("", 7) + (entry.isGroup ? "Group" : "Detail"))
            lines += 1
            if lines > 70 { headings() }
        }
        if warning { printer.after(2, "Warning: One or more P.A. codes contain a zero value for General Ledger numbers") }
        try printer.close(terminateLine: !entries.isEmpty)
        return entries
    }

    public func printTotals() throws -> [Totals]? {
        var result: [Totals]?
        try store.withTransaction {
            var system = try files.settings()
            system.setInt("s-flag-a", 0)
            try files.systemFile.write(1, system.bytes)
            guard store.exists(values.path) else { return }
            guard store.all(values.path).allSatisfy({ $0.data.count == SalesPostingRecords.value.size }) else {
                throw Error.invalidLayout
            }
            let entries = values.allRecords().filter {
                let code = code(from: $0)
                return code.ledger == "S" && (code.group.count == 1 || $0.int("value-this") != 0 || $0.int("value-year") != 0)
            }.map { row in
                Totals(code: code(from: row), counts: ["this", "last", "year"].map { row.int("count-" + $0) },
                       values: ["this", "last", "year"].map { row.int("value-" + $0) })
            }
            try totalsReport(entries, system: system)
            result = entries
        }
        return result
    }

    private func totalsReport(_ entries: [Totals], system: Record) throws {
        let printer = SalesProofRecords.Printer(store)
        let configuredLines = Int(system.int("page-lines"))
        let limit = configuredLines > 28 ? configuredLines : 48
        var lines = limit
        var page: Int64 = 0
        var ratio: Int64 = 0
        func headings() {
            guard lines >= limit else { return }
            page += 1
            let first = Cobol.x("SL130 (3.01.07)", 58) + Cobol.x("Sales  Analysis", 64)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            let second = fixed(system.str("usera"), 52) + Cobol.x("", 70) + date(system)
            if page == 1 {
                printer.before(1, first)
                printer.before(1, second)
            } else {
                printer.afterPage(first)
                printer.after(1, second)
                printer.after(1, "")
            }
            printer.after(2, Cobol.x("Analysis  Type    <-----Description------>   <------", 52)
                + Cobol.x("-Transactions------->   <----------------A", 42) + "mount----------------->  % Period Mvmt")
            printer.after(1, Cobol.x("  Code", 45)
                + "Current   Previous   Y. to D      Current      Previous    Year To Date  Trans. Amount")
            printer.after(1, "")
            lines = 6
        }
        func percent(_ pair: [Int64], picture: String, width: Int) -> String {
            if pair[1] != 0 { ratio = (abs(pair[0] * 10_000 / pair[1])) % 100_000_000 }
            return edited(picture, ratio, width: width, scale: 2)
        }
        headings()
        for entry in entries {
            if entry.code.isGroup {
                headings()
                printer.after(1, "")
                lines += 1
            }
            let prefix = Cobol.x("", 3) + Cobol.x(entry.code.group, 6) + Cobol.x(entry.code.isGroup ? "Group" : " Detail", 9)
            let counts = zip(entry.counts, [5, 6, 4]).map { edited("zzzz9", $0.0, width: 5, scale: 0) + Cobol.x("", $0.1) }.joined()
            let amounts = zip(entry.values, [13, 14, 14]).map { edited($0.1 == 13 ? "z(7)9.99cr" : "z(8)9.99cr", $0.0, width: $0.1, scale: 2) }.joined()
            let movement = percent(entry.counts, picture: "z(4)9.99", width: 8)
                + percent(entry.values, picture: "zzz9.99", width: 7)
            printer.after(1, prefix + fixed(entry.code.description, 28) + counts + amounts + movement)
            lines += 1
            if lines > limit { headings() }
        }
        try printer.close()
    }

    private func validAnalysis() throws {
        guard let kind = store.kind(analysis.path) else { return }
        guard kind == "indexed", store.all(analysis.path).allSatisfy({ $0.data.count == Self.layout.size })
        else { throw Error.invalidLayout }
    }

    private func code(from row: Record) -> Code {
        let key = row.str("code")
        return Code(ledger: String(key.prefix(1)), group: Cobol.rtrim(String(key.dropFirst())),
                    account: row.int("account"), description: Cobol.rtrim(row.str("description")),
                    printCode: Cobol.rtrim(row.str("print")))
    }

    private func date(_ system: Record) -> String {
        Maps04.format(Maps04.toDate(Int(system.int("run-date"))), dateForm: Int(system.int("date-form")))
    }

    private func fixed(_ text: String, _ size: Int) -> String { SJIS.decode(SJIS.encode(text, size: size)[...]) }

    private func validate(_ text: String, width: Int, overflow: Error, unsupported: Error) throws {
        let text = Cobol.rtrim(text)
        var byteCount = 0
        for character in text {
            if let ascii = character.asciiValue, ascii >= 0x20 {
                byteCount += 1
            } else {
                let value = String(character)
                guard let bytes = value.data(using: .shiftJIS),
                      SJIS.decode(Array(bytes)[...]) == value else { throw unsupported }
                byteCount += bytes.count
            }
        }
        guard byteCount <= width else { throw overflow }
    }

    private func edited(_ picture: String, _ value: Int64, width: Int, scale: Int) -> String {
        value == 0 ? Cobol.x("", width) : Pic.edit(picture, value: value, scale: scale)
    }

}
