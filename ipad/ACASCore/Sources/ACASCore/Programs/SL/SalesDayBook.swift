public struct SalesDayBook {
    public struct Entry: Identifiable {
        public let id: SalesInvoices.Number
        public let customer: String
        public let name: String
        public let kind: SalesInvoices.Kind
        public let net: Int64
        public let tax: Int64
        public var gross: Int64 { net + tax }
    }

    public static let exportPath = SalesProofReport.exportPath
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generate() throws -> [Entry]? {
        let store = context.store
        let invoices = SalesInvoices(context)
        let customers = SalesProofRecords.salesFile(store)
        let system = try invoices.settings()
        guard store.exists(invoices.file.path), store.exists(customers.path) else { return nil }
        let p = SalesProofRecords.Printer(store)
        let limit = Int(system.int("page-lines"))
        var page: Int64 = 0
        var lines = 0
        func date(_ day: Int64) -> String {
            guard (1...3_067_671).contains(day) else { return Cobol.x("", 10) }
            return Maps04.format(Maps04.toDate(Int(day)), dateForm: Int(system.int("date-form")))
        }
        func fixed(_ label: String, _ bytes: Int) -> String {
            SJIS.decode(SJIS.encode(label, size: bytes)[...])
        }
        func heading(details: Bool) {
            page += 1
            let first = Cobol.x("SL140 (3.01.09)", 62) + Cobol.x("Day Book", 62)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            let second = fixed(system.str("usera"), 62) + Cobol.x("", 60) + date(system.int("run-date"))
            if page == 1 {
                p.before(1, first)
                p.before(1, second)
            } else {
                p.afterPage(first)
                p.after(1, second)
                p.after(1, "")
            }
            lines = 2
            if details {
                p.after(2, Cobol.x(" Number   ---Date--- <------------Customer------------>", 74)
                    + "<---Net-->  <---Vat-->  <--Gross->")
                p.after(1, "")
                lines += 3
            }
        }
        func money(_ value: Int64) -> String { Pic.edit("z(6)9.99cr", value: value, scale: 2) }
        let types = ["", "Receipt", "Invoice", "Cr. Note"]
        var entries: [Entry] = []
        var totals = Array(repeating: Array(repeating: Int64(0), count: 7), count: 4)
        var customer = Record(SalesProofRecords.salesLayout)
        heading(details: true)
        for row in store.all(invoices.file.path) where row.key.last == 0 {
            let record = Record(SalesProofRecords.ihLayout, bytes: row.data)
            let type = Int(record.int("ih-type"))
            guard (1...3).contains(type), record.str("ih-day-book-flag") != "B",
                  ["z", "Z"].contains(record.str("ih-status")),
                  let kind = SalesInvoices.Kind(rawValue: Int64(type)) else { continue }
            if lines > limit { heading(details: true) }
            if let found = customers.read(key: record.raw("ih-customer")) { customer = found }
            let factor: Int64 = type == 3 ? -1 : 1
            let goods = factor * record.int("ih-net")
            let discount = factor * (record.int("ih-discount") + record.int("ih-extra"))
            let deduction = factor * record.int("ih-deduct-amt")
            let carriage = factor * record.int("ih-carriage")
            let net = goods + discount + deduction + carriage
            let tax = factor * (record.int("ih-vat") + record.int("ih-c-vat") + record.int("ih-e-vat"))
            let entry = Entry(id: invoices.number(record), customer: Cobol.rtrim(record.str("ih-customer")),
                              name: Cobol.rtrim(customer.str("sales-name")), kind: kind, net: net, tax: tax)
            entries.append(entry)
            let amounts = [goods, discount, deduction, carriage, net, tax, entry.gross]
            for (index, amount) in amounts.enumerated() {
                totals[type - 1][index] += amount
                totals[3][index] += amount
            }
            let number = Pic.edit("z(7)9", value: entry.id.value, scale: 0)
            let rowDate = date(record.int("ih-date"))
            let detail = fixed(entry.customer, 8) + fixed(entry.name, 25) + Cobol.x("", 3)
                + Cobol.x(types[type], 11) + Cobol.x("", 6)
            p.after(1, number + "  " + rowDate + " " + detail + [net, tax, entry.gross].map(money).joined())
            lines += 1
        }
        heading(details: false)
        p.after(2, Cobol.x("", 23) + "Goods     Discount   Prompt Pay     Carriage          Net          Vat        Gross")
        p.after(1, "")
        for (title, amounts) in zip(["Receipts", "Invoices", "Credit Notes", "    Totals"], totals) {
            p.after(2, Cobol.x(title, 17) + amounts.map { Pic.edit("z(7)9.99cr", value: $0, scale: 2) }.joined())
        }
        try p.close()
        return entries
    }
}
