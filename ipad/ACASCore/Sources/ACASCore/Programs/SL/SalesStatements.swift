import Foundation

public struct SalesStatements {
    public enum Error: Swift.Error { case missingOpenItems, invalidInput }

    public struct Entry: Identifiable {
        public var id: String { customer }
        public let customer: String
        public let name: String
        public let balance: Int64
    }

    public static let exportPath = "ledgers/acas/sales-statements.prt"
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func prepare() throws -> Date {
        let invoices = SalesInvoices(context)
        var day = 0
        try context.store.withTransaction {
            var system = try invoices.settings()
            guard system.raw("file-statuses")[18] == 0x31, context.store.exists(SalesOpenItems.path) else {
                throw Error.missingOpenItems
            }
            try SalesOpenItemSort.prepare(context.store, system: &system)
            if system.int("date-form") == 0 { system.setInt("date-form", 1) }
            day = Int(system.int("run-date"))
            try invoices.systemFile.write(1, system.bytes)
        }
        guard (1...3_067_671).contains(day) else { return context.now() }
        let date = Maps04.dateOfInteger(day)
        return context.calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) ?? context.now()
    }

    public func generate(date: Date, customer: String, minimum: Int64, message1: String, message2: String) throws -> [Entry] {
        let store = context.store
        let system = try SalesInvoices(context).settings()
        guard system.raw("file-statuses")[18] == 0x31, store.exists(SalesOpenItems.path) else { throw Error.missingOpenItems }
        let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        let code = customer.uppercased()
        let low = SJIS.encode(code, size: 7)
        guard Maps04.validYMD(year, month, day), (0...99_999_999).contains(minimum),
              Cobol.rtrim(SJIS.decode(low[...])) == Cobol.rtrim(code), !message2.hasPrefix("<"),
              [message1, message2].allSatisfy({ SJIS.decode(SJIS.encode($0, size: 64)[...]).trimmingCharacters(in: .whitespaces)
                  == $0.trimmingCharacters(in: .whitespaces) }) else { throw Error.invalidInput }
        let payDay = Int64(Maps04.integerOfDate(year: year, month: month, day: day))
        let dateForm = Int(system.int("date-form"))
        func dateText(_ day: Int64) -> String {
            guard (1...3_067_671).contains(day) else { return "" }
            return Maps04.format(Maps04.toDate(Int(day)), dateForm: dateForm)
        }
        let statementDate = dateText(payDay)
        let limited = low.contains { $0 != 0x20 }
        let high = low.map { $0 == 0x20 ? 0x5a : $0 }
        let raw = store.readRaw(SalesOpenItemSort.path) ?? []
        let width = SalesOpenItems.layout.size
        let items = stride(from: 0, to: raw.count - raw.count % width, by: width).map {
            Record(SalesOpenItems.layout, bytes: Array(raw[$0..<($0 + width)]))
        }
        let delimiter = system.raw("sl-delim")[0]
        func fixed(_ value: String, _ size: Int) -> [UInt8] { SJIS.encode(value, size: size) }
        func fixed(_ value: [UInt8], _ size: Int) -> [UInt8] {
            Array(value.prefix(size)) + repeatElement(0x20, count: max(0, size - value.count))
        }
        func blank(_ size: Int) -> [UInt8] { Array(repeating: 0x20, count: size) }
        func amount(_ value: Int64, wide: Bool = false) -> [UInt8] {
            Array(Pic.edit(wide ? "z(7)9.99cr" : "z(6)9.99cr", value: value, scale: 2).utf8)
        }
        func number(_ value: Int64) -> [UInt8] {
            value == 0 ? blank(8) : Array(Pic.edit("z(7)9", value: value, scale: 0).utf8)
        }
        var output: [UInt8] = []
        func line(_ bytes: [UInt8], after: Int = 1) {
            output += Array(repeating: 0x0a, count: after) + fixed(bytes, 132)
        }
        func detail(_ invoice: Int64, _ date: String, _ description: [UInt8], _ total: Int64, _ remaining: Int64) {
            let key = number(invoice)
            let first = blank(2) + key + blank(3) + fixed(date, 11) + fixed(description, 31)
            line(first + amount(total) + blank(3) + key + amount(remaining, wide: true))
        }
        var cursor = 0
        var entries: [Entry] = []
        for record in SalesProofRecords.salesFile(store).allRecords() {
            let key = record.raw("sales-key")
            if limited && (key.lexicographicallyPrecedes(low) || high.lexicographicallyPrecedes(key)) { continue }
            let unapplied = record.int("sales-unapplied")
            let current = record.int("sales-current") - unapplied
            guard current != 0, minimum == 0 || current >= minimum else { continue }
            let addresses = (record.raw("sales-addr1") + record.raw("sales-addr2"))
                .split(separator: delimiter, maxSplits: 5, omittingEmptySubsequences: false).map(Array.init)
            func address(_ index: Int) -> [UInt8] { fixed(index < addresses.count ? addresses[index] : [], 32) }
            func header() {
                line(blank(24) + fixed(system.raw("usera"), 32))
                for index in 1...4 {
                    let company = system.raw(index == 1 ? "usera" : "address-\(index - 1)")
                    line(blank(24) + fixed(system.raw("address-\(index)"), 24) + blank(21) + fixed(company, 23))
                }
                line(blank(9) + fixed(record.raw("sales-name"), 32), after: 2)
                let bothDates = fixed(statementDate, 10) + blank(3) + fixed(statementDate, 10)
                line(blank(9) + address(0) + blank(15) + bothDates + blank(5) + key)
                for index in 1...3 { line(blank(9) + address(index)) }
                line(blank(9) + address(4) + blank(18) + key)
                line([], after: 3)
            }
            header()
            var ageing = [-unapplied, 0, 0, 0]
            var count = 0
            if unapplied != 0 {
                detail(0, statementDate, Array("Unapplied Credit Balance".utf8), -unapplied, -unapplied)
                count += 1
            }
            var lastTotal: Int64 = 0
            var lastRemaining: Int64 = 0
            while cursor < items.count {
                let item = items[cursor]
                let itemKey = item.raw("customer")
                if key.lexicographicallyPrecedes(itemKey) { break }
                cursor += 1
                let type = item.int("type")
                guard itemKey == key, type != 1, type != 4 else { continue }
                let paid = item.int("paid")
                let gross = SalesOpenItems.invoiceTotal(item) + item.int("deduction") + item.int("deduction-tax")
                var outstanding: Int64 = 0
                var description: [UInt8]
                switch type {
                case 2:
                    outstanding = gross - paid
                    let currentPayment = item.int("paid-current")
                    lastTotal = outstanding == 0 && currentPayment == 0 ? gross : outstanding + currentPayment
                    lastRemaining = outstanding
                    let text = item.raw("description")
                    if text.allSatisfy({ $0 == 0x20 }) {
                        description = Array("Goods".utf8)
                    } else {
                        let end = text.indices.dropLast().first { text[$0] == 0x20 && text[$0 + 1] == 0x20 } ?? text.count
                        description = Array("Goods As Per - ".utf8) + text.prefix(end)
                    }
                case 3:
                    lastTotal = gross
                    lastRemaining = gross + paid
                    description = Array("Credit Note Re. Inv - ".utf8)
                        + Pic.edit("z(7)9", value: item.int("credit"), scale: 0).utf8
                default:
                    if type == 5 || type == 6 {
                        lastTotal = -abs(paid)
                        outstanding = lastTotal + abs(item.int("net"))
                        lastRemaining = outstanding
                    }
                    description = Array((type == 6 ? "Unapplied Credit Allocated" : "Payment. Received With Thanks").utf8)
                }
                let age = payDay - item.int("date")
                ageing[age < 30 ? 0 : age < 60 ? 1 : age < 90 ? 2 : 3] += outstanding
                count += 1
                if count > 28 {
                    line([], after: 8)
                    header()
                    count = 1
                }
                detail(type == 5 || type == 6 ? 0 : item.int("invoice"), dateText(item.int("date")),
                       description, lastTotal, lastRemaining)
            }
            var skip = 32 - count
            if skip >= 6 {
                line(blank(1) + fixed(message1, 64), after: skip - 4)
                line(blank(1) + fixed(message2, 64))
                skip = 3
            }
            let total = ageing.reduce(0, +)
            let first = amount(ageing[0]) + blank(2) + amount(ageing[1]) + blank(1) + amount(ageing[2])
            let last = blank(1) + amount(ageing[3]) + blank(1) + amount(total) + blank(12) + amount(total)
            line(first + last, after: skip)
            line([], after: 4)
            entries.append(Entry(customer: Cobol.rtrim(record.str("sales-key")),
                                 name: Cobol.rtrim(record.str("sales-name")), balance: total))
            if cursor == items.count { break }
        }
        try store.withTransaction {
            try store.writeRaw(Self.exportPath, output.isEmpty ? [] : output + [0x0a])
            try store.writeRaw(SalesOpenItemSort.path, [])
        }
        return entries
    }
}
