public struct SalesPaymentProof {
    public static let exportPath = SalesProofReport.exportPath
    static let sortedPath = "ledgers/acas/oisort.wrk"
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generate() throws -> [SalesPayments.Pending] {
        let store = context.store
        var payments: [SalesPayments.Pending] = []
        try store.withTransaction {
            var system = try SalesLedger(context).systemRecord()
            guard system.int("s-flag-p") != 0 else { throw SalesPayments.Error.unavailable }
            let sorted = Self.sortedRecords(in: store)
            try store.writeRaw(Self.sortedPath, sorted.flatMap(\.bytes))
            payments = try printReport(sorted, system: system)
            system["oi-3-flag"] = "Y"
            system.setInt("s-flag-p", 2)
            try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        }
        return payments
    }

    static func sortedRecords(in store: FileStore) -> [Record] {
        func key(_ r: Record) -> [Int64] {
            [r.int("batch"), r.int("item"), -r.int("type"), r.int("date"), r.int("invoice")]
        }
        return SalesOpenItems.file(store).allRecords().enumerated().filter { _, r in
            r.int("type") != 1 && r.int("type") != 3 && (r.int("batch") != 0 || r.int("item") != 0)
        }.sorted { a, b in
            let left = key(a.element), right = key(b.element)
            return left == right ? a.offset < b.offset : left.lexicographicallyPrecedes(right)
        }.map(\.element)
    }

    private func printReport(_ sorted: [Record], system: Record) throws -> [SalesPayments.Pending] {
        let store = context.store
        let printer = SalesProofRecords.Printer(store)
        let customers = SalesProofRecords.salesFile(store)
        let pageLines = Int(system.int("page-lines"))
        var lines = 0
        var page: Int64 = 0
        var result: [SalesPayments.Pending] = []
        var customer = ""
        var applied: Int64 = 0
        var total = Totals()
        var journals = Totals()
        let space = SalesProofRecords.spaces
        func date(_ day: Int64) -> String {
            Maps04.format(Maps04.toDate(Int(day)), dateForm: Int(system.int("date-form")))
        }
        func headings() {
            page = (page + 1) % 100
            let heading = Cobol.x("SL095 (3.01.07)", 48) + Cobol.x("Payment And Journal Proof Report", 76)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            let company = system.raw("usera")
            let subheading = company + Array(repeating: UInt8(0x20), count: 122 - company.count)
                + SJIS.encode(date(system.int("run-date")), size: 10)
            if page == 1 {
                printer.before(1, heading)
                printer.before(1, subheading)
            } else {
                printer.afterPage(heading)
                printer.after(1, subheading)
                printer.after(1, "")
            }
            printer.after(2, Cobol.x("  Batch  Tp  Pay Date  <-------------Customer------------->", 61)
                + "  Value    Approp.    Ded'n    <--------Payment Appropriation--------->")
            printer.after(1, space(22) + Cobol.x(" A/C               Name", 70) + "Invoice   Date      Approp.     Balance ")
            lines = 6
        }
        printer.open()
        headings()
        for record in sorted {
            let type = record.int("type")
            let paid = record.int("paid")
            let account = record.str("customer")
            if type == 2 {
                guard paid != 0, account == customer else { continue }
                let net = SalesOpenItems.invoiceTotal(record) + record.int("deduction") + record.int("deduction-tax")
                let invoice = Self.edited("z(7)9", record.int("invoice"), width: 8, digits: 8, scale: 0) + " "
                let appropriation = Self.edited("z(5)9.99", min(applied, paid), width: 9, digits: 8)
                let balance = Self.edited("z(7)9.99cr", abs(net) % 100_000_000 - paid, width: 13, digits: 10, signed: true)
                printer.after(1, space(91) + invoice + date(record.int("date")) + appropriation + balance)
                lines += 1
                if lines > pageLines { headings() }
            } else if (type == 5 || type == 6), record.int("status") == 0 {
                customer = account
                applied = record.int("net")
                let deduction = record.int("deduction")
                let journal = type == 6
                let batch = record.int("batch")
                let item = record.int("item")
                result.append(SalesPayments.Pending(customer: account, batch: batch, item: item, amount: paid,
                                                    journal: journal, deduction: deduction))
                if journal { journals.add(paid: paid, applied: applied, deducted: deduction) }
                else { total.add(paid: paid, applied: applied, deducted: deduction) }
                let batchLabel = Self.edited("z(4)9", batch, width: 5, digits: 5, scale: 0)
                    + "/" + (item == 0 ? space(4) : Cobol.z(item, 3) + " ")
                let name = customers.read(key: record.raw("customer")).map { Array($0.raw("sales-name").prefix(29)) }
                    ?? SJIS.encode("!! Customer Unknown", size: 29)
                let paidText = Self.edited("z(5)9.99", paid, width: 9, digits: 8) + "  "
                let appliedText = Self.edited("z(5)9.99", applied, width: 9, digits: 8) + "  "
                let deductionText = Self.edited("z(3)9.99", deduction, width: 7, digits: 6) + "  "
                if lines > pageLines { headings() }
                let prefix = batchLabel + (journal ? "J " : "P ") + Cobol.x(date(record.int("date")), 11)
                let accountBytes = record.raw("customer") + [0x20]
                let amounts = paidText + appliedText + deductionText
                printer.after(2, SJIS.encode(prefix, size: 22) + accountBytes + name + SJIS.encode(amounts, size: 73))
                lines += 2
            }
        }
        if lines > pageLines - 8 { headings() }
        func printTotal(_ label: String, _ values: Totals, after: Int) {
            printer.after(after, space(30) + label + " Totals")
            printer.after(1, space(30) + "**************")
            let rows = [("Payments", values.paid, 3), ("Appropriations", values.applied, 1),
                        ("Unapplied Cash", values.paid - values.applied, 1), ("Deductions Taken", values.deducted, 2)]
            for (caption, value, spacing) in rows {
                let printed = Pic.edit("z(6)9.99", value: Cobol.truncate(value, digits: 9, signed: false), scale: 2)
                printer.after(spacing, space(23) + Cobol.x(Cobol.x(caption, 16), 17) + printed)
            }
        }
        printTotal("Payment", total, after: 4)
        printTotal("Journal", journals, after: 2)
        try printer.close()
        return result
    }

    private static func edited(_ pic: String, _ value: Int64, width: Int, digits: Int, scale: Int = 2, signed: Bool = false) -> String {
        let number = Cobol.truncate(value, digits: digits, signed: signed)
        return number == 0 ? SalesProofRecords.spaces(width) : Cobol.x(Pic.edit(pic, value: number, scale: scale), width)
    }

    private struct Totals {
        var paid: Int64 = 0
        var applied: Int64 = 0
        var deducted: Int64 = 0

        mutating func add(paid: Int64, applied: Int64, deducted: Int64) {
            self.paid = Cobol.truncate(self.paid + paid, digits: 9)
            self.applied = Cobol.truncate(self.applied + applied, digits: 9)
            self.deducted = Cobol.truncate(self.deducted + deducted, digits: 9)
        }
    }
}
