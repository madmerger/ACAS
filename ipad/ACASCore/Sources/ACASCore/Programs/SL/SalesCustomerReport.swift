import Foundation

public struct SalesCustomerReport {
    public enum Kind { case listing, alphabetical, turnover }

    public enum Status: CaseIterable, Hashable { case all, active, dormant }

    public enum Relation: CaseIterable, Hashable {
        case less, greater, equal

        fileprivate func matches(_ value: Int64, _ threshold: Int64) -> Bool {
            switch self {
            case .less: value < threshold
            case .greater: value > threshold
            case .equal: value == threshold
            }
        }

        fileprivate var heading: String {
            switch self {
            case .less: "< "
            case .greater: "> "
            case .equal: "= "
            }
        }
    }

    public struct Filter {
        public var code = ""
        public var status = Status.all
        public var creditDays: (Relation, Int64)?
        public var invoiceCount: (Relation, Int64)?
        public var averageValue: (Relation, Int64)?
        public var overdueDays: (Relation, Int64)?
        public var creationDate: (Relation, Date)?
        public init() {}
    }

    public static let exportPath = "ledgers/acas/prt-1"
    private let context: BusinessContext
    public init(_ context: BusinessContext) { self.context = context }

    public func prepareTurnover() throws {
        try context.store.writeRaw(Self.exportPath, [])
    }

    public func generate(_ filter: Filter, kind: Kind = .listing) throws -> [SalesLedger.Customer] {
        let ledger = SalesLedger(context)
        let system = try ledger.systemRecord()
        let prefix = filter.code.uppercased()
        let low = SJIS.encode(prefix, size: 6) + [0x20]
        guard Cobol.rtrim(SJIS.decode(low[...])) == Cobol.rtrim(prefix),
              (0...99).contains(filter.creditDays?.1 ?? 0),
              [filter.invoiceCount, filter.averageValue, filter.overdueDays]
                .allSatisfy({ (0...99_999).contains($0?.1 ?? 0) }) else {
            throw SalesLedger.Error.invalidField
        }
        let high = low.map { $0 == 0x20 ? 0x5a : $0 }
        let runDay = system.int("run-date")
        var creationDay: Int64 = 0
        if let (_, date) = filter.creationDate {
            let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
            let y = parts.year ?? 0, m = parts.month ?? 0, d = parts.day ?? 0
            guard Maps04.validYMD(y, m, d) else { throw SalesLedger.Error.invalidDate }
            creationDay = Int64(Maps04.integerOfDate(year: y, month: m, day: d))
        }
        var matching = SalesProofRecords.salesFile(context.store).allRecords().filter { record in
            let key = record.raw("sales-key")
            let status = record.int("sales-status")
            if !Cobol.rtrim(prefix).isEmpty {
                if kind == .alphabetical {
                    guard !key.lexicographicallyPrecedes(high), !low.lexicographicallyPrecedes(key) else { return false }
                } else {
                    guard !key.lexicographicallyPrecedes(low), !high.lexicographicallyPrecedes(key) else { return false }
                }
            }
            guard filter.status != .active || status != 0,
                  filter.status != .dormant || status != 1 else { return false }
            for (criterion, field) in [(filter.creditDays, "sales-credit"), (filter.invoiceCount, "sales-activety"),
                                       (filter.averageValue, "sales-average")] {
                if let (relation, threshold) = criterion, !relation.matches(record.int(field), threshold) { return false }
            }
            if let (relation, threshold) = filter.overdueDays, record.int("sales-current") > 0,
               !relation.matches(runDay - record.int("sales-last-inv"), threshold) { return false }
            return filter.creationDate?.0.matches(record.int("sales-create-date"), creationDay) ?? true
        }
        let dateForm = Int(system.int("date-form"))
        let heading = Self.heading(filter, code: prefix, creationDay: creationDay, dateForm: dateForm)
        let date = Maps04.format(Maps04.toDate(Int(runDay)), dateForm: dateForm)
        let configuredLines = Int(system.int("page-lines"))
        let pageLines = configuredLines > 28 ? configuredLines : 48
        if kind == .turnover {
            try writeTurnover(matching, system: system, date: date, dateForm: dateForm, pageLines: pageLines)
            return matching.map(ledger.customer(from:))
        }
        if kind == .alphabetical {
            matching.sort { $0.raw("sales-name").lexicographicallyPrecedes($1.raw("sales-name")) }
        }
        let delimiter = system.raw("sl-delim")[0]
        var spool = [UInt8]()
        var page = 0
        var lineCount = 0
        func line(_ bytes: [UInt8]) { spool += [0x0a] + Self.fit(bytes, 132) }
        func headings() {
            page += 1
            let first = (kind == .alphabetical
                ? Self.fit("SL160 (3.01.16)", 51) + Self.fit("Customer Alphabetical Listing", 73)
                : Self.fit("SL010 (3.01.20)", 57) + Self.fit("Customer Listing", 67))
                + Self.fit("Page " + Pic.edit("zz9", value: Int64(page % 1000), scale: 0), 8)
            let third = Self.fit(system.raw("usera"), 40) + Self.fit("Report On : ", 12)
                + Self.fit(heading, 70) + Self.fit(date, 10)
            if page == 1 {
                spool += first + [0x0a] + third + [0x0a]
            } else {
                spool += [0x0c] + first
                line(third)
                line([])
            }
            line(Self.fit("Customer  Status    <---------------Name & Address-------------->     ----Telephone"
                          + "---- -----Fax-----     Late       Credit", 127) + Self.fit(" Disc", 5))
            line(Self.fit(" Number   ------", 104) + Self.fit("Chg  Let   Limit/Days    %", 28))
            line([])
            lineCount = 6
        }
        func address(_ first: [UInt8], _ second: [UInt8], replacing: Bool = true) {
            let bytes = Self.fit(first + second, 112)
            line(Self.fit([], 20) + (replacing ? bytes.map { $0 == delimiter ? 0x2c : $0 } : bytes))
        }
        headings()
        for record in matching {
            if lineCount > pageLines { headings() }
            if lineCount > pageLines - (kind == .alphabetical ? 3 : 5) { headings() }
            let status = record.int("sales-status") == 1 ? "Active" : "Dormant"
            let phone = record.raw("sales-phone")
            let ext = record.raw("sales-ext")
            let printedPhone: [UInt8]
            if ext.allSatisfy({ $0 == 0x20 }) {
                printedPhone = phone
            } else {
                let end = Self.doubleSpaceIndex(phone) ?? phone.count
                printedPhone = Array(phone.prefix(max(0, end - 1))) + [0x78] + ext
            }
            let late = record.int("sales-late") == 1 ? "Y" : ""
            let dunning = record.int("sales-dunning") == 1 ? "Y" : ""
            let contact = Self.fit(printedPhone, 18) + record.raw("sales-fax") + Self.fit("", 4)
            let terms = Self.fit(late, 5) + Self.fit(dunning, 3)
                + Self.numeric("z(6)9", record.int("sales-limit"))
                + Self.numeric("zzz9bbb", record.int("sales-credit"))
                + Self.numeric("z9.99", record.int("sales-discount"), scale: 2)
            line(Self.fit(record.raw("sales-key"), 10) + Self.fit(status, 10)
                 + Self.fit(record.raw("sales-name"), 50) + contact + terms)
            address(record.raw("sales-addr1"), record.raw("sales-addr2"))
            let identifier = record.raw("sales-key")
            if record.int("delivery-tag") > 0 {
                let delivery = ledger.deliveryFile.read(key: [0x44] + identifier)
                let name = delivery?.raw("name") ?? Self.fit("Record Not Found", 30)
                line(Self.fit("   Delivery Address", 20) + Self.fit(name, 50))
                address(delivery?.raw("address1") ?? [], delivery?.raw("address2") ?? [], replacing: delivery != nil)
                lineCount += 2
            }
            if record.int("notes-tag") > 0 {
                let note = ledger.deliveryFile.read(key: [0x4e] + identifier)
                let text = note.map { $0.raw("address1") + $0.raw("address2") } ?? Self.fit("Record Not Found", 96)
                address(Array("Notes: ".utf8) + text.prefix(Self.doubleSpaceIndex(text) ?? text.count), [], replacing: false)
                lineCount += 1
            }
            line([])
            lineCount += 3
            if kind == .alphabetical, lineCount > pageLines { headings() }
        }
        try context.store.withTransaction {
            try context.store.writeRaw(Self.exportPath, spool + [0x0a])
            if kind == .alphabetical { try context.store.writeRaw("custsort.tmp", []) }
        }
        return matching.map(ledger.customer(from:))
    }

    private func writeTurnover(_ records: [Record], system: Record, date: String, dateForm: Int, pageLines: Int) throws {
        let p = SalesProofRecords.Printer(context.store)
        var page: Int64 = 0
        var lines = 0
        func headings() {
            page += 1
            let first = Cobol.x("SL180 (3.01.08)", 51) + Cobol.x("Sales Ledger Turnover Report", 73)
                + "Page " + Pic.edit("zz9", value: page % 1000, scale: 0)
            let user = SJIS.decode(Self.fit(system.raw("usera"), 51)[...])
            let second = user + Cobol.x("", 71) + date
            if page == 1 {
                p.before(1, first)
                p.before(1, second)
            } else {
                p.afterPage(first)
                p.after(1, second)
                p.after(1, "")
            }
            p.after(2, Cobol.x("", 38)
                + "Credit Terms  <------------- T u r n o v e r ------------> <--S A L E S-->  <--Date Of Last-->")
            p.after(1, Cobol.x("Acct No          Name", 38)
                + "Days   Limit  Mvmt Average   Qtr 1   Qtr 2   Qtr 3   Qtr 4 Current    Last  Invoice    Payment")
            p.after(1, "")
            lines = 6
        }
        func shortDate(_ day: Int64) -> String {
            guard (1...3_067_671).contains(day) else { return Cobol.x("", 8) }
            let full = Maps04.format(Maps04.toDate(Int(day)), dateForm: dateForm)
            return dateForm == 3 ? String(full.dropFirst(2)) : String(full.prefix(6) + full.suffix(2))
        }
        func signed(_ value: Int64, _ width: Int = 8) -> String {
            let digits = String(value % Cobol.pow10(width - 1))
            return Cobol.x("", max(0, width - digits.count)) + digits
        }
        headings()
        for record in records {
            let key = SJIS.decode(Self.fit(record.raw("sales-key"), 8)[...])
            let name = SJIS.decode(record.raw("sales-name")[...])
            let terms = Pic.edit("zzz9", value: record.int("sales-credit"), scale: 0)
                + Pic.edit("z(7)9", value: record.int("sales-limit"), scale: 0)
            let activity = signed(record.int("sales-activety"), 6) + signed(record.int("sales-average"))
            let quarters = (1...4).map { signed(record.int("turnover-q\($0)") / 100) }.joined()
            let balance = signed((record.int("sales-current") - record.int("sales-unapplied")) / 100)
                + signed(record.int("sales-last") / 100)
            let dates = "  " + Cobol.x(shortDate(record.int("sales-last-inv")), 10)
                + shortDate(record.int("sales-last-pay"))
            p.after(1, key + name + terms + activity + quarters + balance + dates)
            lines += 1
            if lines > pageLines { headings() }
        }
        try p.close()
    }

    private static func heading(_ filter: Filter, code: String, creationDay: Int64, dateForm: Int) -> String {
        let matched = filter.status != .all || filter.creditDays != nil || filter.invoiceCount != nil
            || filter.averageValue != nil || filter.overdueDays != nil || !Cobol.rtrim(code).isEmpty
        var report = matched ? "Matched" : "All"
        switch filter.status {
        case .all: break
        case .active: report += " Live"
        case .dormant: report += " Dormant"
        }
        for (term, pic, label) in [(filter.creditDays, "z9", "Days Credit"), (filter.invoiceCount, "zzzz9", "Invoices"),
                                   (filter.averageValue, "zzzz9", "Av. Value"), (filter.overdueDays, "zzzz9", "Days Overdue")] {
            if let (relation, number) = term { report += " " + relation.heading + Pic.edit(pic, value: number, scale: 0) + " " + label }
        }
        if let (relation, _) = filter.creationDate {
            report += " " + relation.heading + Maps04.format(Maps04.toDate(Int(creationDay)), dateForm: dateForm) + " Entry Date"
        }
        if !Cobol.rtrim(code).isEmpty { report += "  Keys Matching - " + code }
        return report
    }

    private static func fit(_ text: String, _ size: Int) -> [UInt8] { SJIS.encode(text, size: size) }

    private static func fit(_ bytes: [UInt8], _ size: Int) -> [UInt8] {
        Array(bytes.prefix(size)) + repeatElement(0x20, count: max(0, size - bytes.count))
    }

    private static func numeric(_ pic: String, _ value: Int64, scale: Int = 0) -> [UInt8] {
        let width = Pic.size(pic)
        return fit(value == 0 ? "" : Pic.edit(pic, value: value, scale: scale), width)
    }

    private static func doubleSpaceIndex(_ bytes: [UInt8]) -> Int? {
        bytes.indices.dropLast().first { bytes[$0] == 0x20 && bytes[$0 + 1] == 0x20 }
    }
}
