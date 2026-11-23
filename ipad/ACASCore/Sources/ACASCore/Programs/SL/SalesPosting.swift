public struct SalesPosting {
    public enum Error: Swift.Error {
        case missingWorkFile, missingAnalysis, invalidAnalysisLayout, invalidWorkFile, writeFailed
    }

    public struct Result {
        public let posted: [Int64]
        public let unprinted: Bool
    }

    static let workPath = "ledgers/acas/openitm2.dat"
    static let analysisPath = "ledgers/acas/analysis.dat"
    static let valuePath = "ledgers/acas/value.dat"
    public static let exportPath = SalesProofReport.exportPath
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func checkAvailability() throws {
        let store = context.store
        let invoices = SalesInvoices(context)
        let status = try invoices.settings().raw("file-statuses")[14]
        let hasInvoices = store.exists(invoices.file.path)
        guard status == 0x31 || hasInvoices else { throw Error.missingAnalysis }
        guard store.readRaw(Self.workPath) != nil || hasInvoices else { throw Error.missingWorkFile }
        guard status == 0x31 || status == 0x30 || status == 0x20,
              store.readRaw(Self.analysisPath) == nil,
              store.all(Self.analysisPath).allSatisfy({ $0.data.count == SalesAnalysisFiles.layout.size }) else {
            throw Error.invalidAnalysisLayout
        }
    }

    public func post() throws -> Result {
        let store = context.store
        let invoices = SalesInvoices(context)
        var posted: [Int64] = []
        var unprinted = false
        try store.withTransaction {
            try checkAvailability()
            var system = try invoices.settings()
            try SalesAnalysisFiles.initialize(store, system: &system)
            var monthly = Record(SalesPostingRecords.monthly, bytes: invoices.systemFile.read(4) ?? SystemAuxRecords.initialRecord4())
            var work = store.readRaw(Self.workPath) ?? []
            guard work.count % SalesOpenItems.layout.size == 0 else {
                throw Error.invalidWorkFile
            }
            let extraction = try extract(invoices, monthly: &monthly)
            unprinted = extraction.unprinted
            work += extraction.records.flatMap(\.bytes)
            var flags = system.raw("file-statuses")
            flags[17] = 0x30
            if flags[18] != 0x31 {
                store.deleteFile(SalesOpenItems.path)
                store.createIndexed(SalesOpenItems.path)
                flags[18] = 0x31
            }
            system.setRaw("file-statuses", flags)
            system.setInt("s-flag-i", 2)
            system.setInt("s-flag-a", 1)
            system["oi-3-flag"] = "Y"
            let report = InvoicePostingReport(store: store, system: system)
            let customers = SalesProofRecords.salesFile(store)
            let openItems = SalesOpenItems.file(store)
            let gl = system.int("level-1") == 1 ? SalesPaymentPosting.Ledger(store: store, system: &system, sales: true) : nil
            var deductions: Int64 = 0
            var deductionCount: Int64 = 0
            var missingCustomer = false
            for offset in stride(from: 0, to: work.count, by: SalesOpenItems.layout.size) {
                var item = Record(SalesOpenItems.layout, bytes: Array(work[offset..<offset + SalesOpenItems.layout.size]))
                let type = item.int("type")
                guard (1...3).contains(type) else { throw Error.invalidWorkFile }
                let key = item.raw("customer")
                let existing = customers.read(key: key)
                var customer = existing ?? Record(SalesProofRecords.salesLayout)
                if existing == nil {
                    missingCustomer = true
                    customer["sales-name"] = "!! Customer Unknown"
                    customer.setRaw("sales-key", key)
                }
                let goods = item.int("net") + item.int("extra")
                let net = goods + item.int("carriage") + item.int("discount") + item.int("deduction")
                let vat = item.int("tax") + item.int("extra-tax") + item.int("carriage-tax")
                let totalTax = vat + item.int("deduction-tax")
                let gross = net + totalTax
                try gl?.writeSale(item, customer: customer, net: net, tax: vat, system: &system)
                let oldBalance = customer.int("sales-current") - customer.int("sales-unapplied")
                let quarter = min(4, max(1, system.int("current-quarter")))
                let turnover = "turnover-q\(quarter)"
                customer.setInt(turnover, customer.int(turnover) + goods)
                let activity = customer.int("sales-activety")
                let previous = activity * customer.int("sales-average")
                let sum = (previous * 100 + goods) / 100
                if type == 1 || type == 2 {
                    customer.setInt("sales-activety", activity + 1)
                    if activity + 1 != 0 { customer.setInt("sales-average", sum / (activity + 1)) }
                    customer.setInt("sales-last-inv", item.int("date"))
                } else if previous != 0, activity != 0 {
                    customer.setInt("sales-average", sum / activity)
                }
                if type != 2 { customer.setInt("sales-last-pay", item.int("date")) }
                if type != 1 { customer.setInt("sales-current", customer.int("sales-current") + gross) }
                var deducted: Int64 = 0
                if type == 3 {
                    let applied = try applyCredit(&item, to: openItems, gross: gross)
                    deducted = applied.amount
                    deductionCount += applied.count
                    customer.setInt("sales-current", customer.int("sales-current") - deducted)
                }
                deductions += deducted
                if customer.int("sales-status") == 0 { customer.setInt("sales-status", 1) }
                if customer.int("sales-current") < 0 {
                    customer.setInt("sales-unapplied", customer.int("sales-unapplied") - customer.int("sales-current"))
                    customer.setInt("sales-current", 0)
                }
                let status = existing == nil ? customers.write(customer) : customers.rewrite(customer)
                guard status == "00", openItems.write(item) == "00" else { throw Error.writeFailed }
                report.add(item, name: customer.str("sales-name"), old: oldBalance,
                           new: customer.int("sales-current") - customer.int("sales-unapplied"), deducted: deducted, net: net, tax: totalTax)
                posted.append(item.int("invoice"))
            }
            monthly.setInt("credit-deductions", monthly.int("credit-deductions") + deductions)
            if deductions != 0 {
                try updateValue(code: "Szd", count: -deductionCount, amount: -deductions, creating: false)
            }
            try gl?.close(system: &system)
            report.finishMain(deductions: deductions)
            var unappliedCredits: Int64 = 0
            for var credit in openItems.allRecords() where credit.int("type") == 3 && credit.int("status") != 1 {
                let value = itemTotal(credit) + credit.int("paid")
                report.unapplied(credit, balance: value)
                unappliedCredits += value
                credit.setInt("paid", credit.int("paid") - value)
                credit.setInt("status", 1)
                guard openItems.rewrite(credit) == "00" else { throw Error.writeFailed }
            }
            monthly.setInt("unapplied-credits", monthly.int("unapplied-credits") + unappliedCredits)
            try report.close(unapplied: unappliedCredits, missingCustomer: missingCustomer)
            try store.writeRaw(Self.workPath, [])
            try invoices.systemFile.write(1, system.bytes)
            try invoices.systemFile.write(4, monthly.bytes)
        }
        return Result(posted: posted, unprinted: unprinted)
    }

    private func extract(_ invoices: SalesInvoices, monthly: inout Record) throws -> (records: [Record], unprinted: Bool) {
        let store = context.store
        var records: [Record] = []
        var unprinted = false
        var skip: [UInt8] = []
        var specials: [String: (Int64, Int64)] = [:]
        for row in store.all(invoices.file.path) {
            let number = Array(row.key.prefix(8))
            if number == skip { continue }
            if row.key.last != 0 {
                var line = Record(SalesProofRecords.ilLayout, bytes: row.data)
                guard !["Z", "z"].contains(line.str("il-update")), !line.str("il-product").hasPrefix("/") else { continue }
                let code = "S" + line.str("il-pa")
                let amount = line.str("il-type") == "3" ? -line.int("il-net") : line.int("il-net")
                try updateValue(code: code, count: 1, amount: amount)
                if code.last != " " {
                    line["il-update"] = "Z"
                    let bytes = line.bytes + row.data.dropFirst(line.layout.size)
                    guard store.rewrite(invoices.file.path, key: row.key, data: bytes) else { throw Error.writeFailed }
                }
                continue
            }
            var header = Record(SalesProofRecords.ihLayout, bytes: row.data)
            let type = header.int("ih-type")
            let analysed = ["Z", "z"].contains(header.str("ih-update"))
            let transferred = ["Z", "z"].contains(header.str("ih-status"))
            if analysed && transferred { continue }
            if type == 4 || header.str("ih-status") == "P" || header.str("ih-status-l") != "L" {
                skip = number
                if type != 4 { unprinted = true }
                continue
            }
            if !transferred {
                let item = extractItem(header)
                records.append(item)
                if type == 2 || type == 3 {
                    let field = type == 2 ? "invoices" : "credit-notes"
                    monthly.setInt(field, monthly.int(field) + (type == 2 ? itemTotal(item) : -itemTotal(item)))
                }
                header["ih-status"] = "Z"
                header["ih-status-a"] = "A"
            }
            if !analysed {
                let factor: Int64 = type == 3 ? -1 : 1
                let vat = header.int("ih-c-vat") + header.int("ih-vat") + header.int("ih-e-vat")
                for (code, value) in [(type == 1 ? "Svp" : "Svo", vat), ("Szc", header.int("ih-carriage")),
                                      ("Szd", header.int("ih-deduct-amt"))] where value != 0 {
                    let previous = specials[code, default: (0, 0)]
                    specials[code] = (previous.0 + 1, previous.1 + factor * value)
                }
                header["ih-update"] = "Z"
            }
            guard store.rewrite(invoices.file.path, key: row.key, data: header.bytes) else { throw Error.writeFailed }
        }
        for code in ["Svo", "Svp", "Szc", "Szd"] {
            let totals = specials[code, default: (0, 0)]
            try updateValue(code: code, count: totals.0, amount: totals.1)
        }
        return (records, unprinted)
    }

    private func extractItem(_ header: Record) -> Record {
        var item = Record(SalesOpenItems.layout)
        item.setRaw("customer", header.raw("ih-customer"))
        item["description"] = header.str("ih-order")
        for (field, source) in [("paid-current", "p-c"), ("invoice", "invoice"), ("date", "date"), ("type", "type"),
                                ("credit", "cr"), ("deduction-days", "deduct-days")] {
            item.setInt(field, header.int("ih-" + source))
        }
        let sign: Int64 = header.int("ih-type") == 3 ? -1 : 1
        for (field, source) in [("net", "net"), ("extra", "extra"), ("carriage", "carriage"), ("discount", "discount"),
                                ("tax", "vat"), ("extra-tax", "e-vat"), ("carriage-tax", "c-vat"),
                                ("deduction", "deduct-amt"), ("deduction-tax", "deduct-vat")] {
            item.setInt(field, sign * header.int("ih-" + source))
        }
        return item
    }

    private func updateValue(code: String, count: Int64, amount: Int64, creating: Bool = true) throws {
        let store = context.store
        let file = IndexedFile(store, path: Self.valuePath, layout: SalesPostingRecords.value, keyLength: 3)
        let parent = String(code.prefix(2)) + " "
        for key in (code == parent ? [code] : [code, parent]) {
            let existing = file.read(key: key)
            if existing == nil && !creating { break }
            var value = existing ?? Record(SalesPostingRecords.value)
            if existing == nil {
                let bytes = SJIS.encode(key, size: 3)
                if let analysis = store.read(Self.analysisPath, key: bytes) {
                    value.bytes.replaceSubrange(0..<36, with: analysis)
                } else {
                    value["code"] = key
                    value["description"] = "Emergency Name"
                    guard store.write(Self.analysisPath, key: bytes, data: Array(value.bytes.prefix(36))) else {
                        throw Error.writeFailed
                    }
                }
            }
            for field in ["count-this", "count-year"] { value.setInt(field, value.int(field) + count) }
            for field in ["value-this", "value-year"] { value.setInt(field, value.int(field) + amount) }
            guard (existing == nil ? file.write(value) : file.rewrite(value)) == "00" else { throw Error.writeFailed }
        }
    }

    private func itemTotal(_ item: Record) -> Int64 {
        SalesOpenItems.invoiceTotal(item) + item.int("deduction") + item.int("deduction-tax")
    }

    private func applyCredit(_ credit: inout Record, to file: IndexedFile, gross: Int64) throws -> (amount: Int64, count: Int64) {
        let target = credit.int("credit")
        var remaining = abs(gross) - credit.int("paid")
        let customer = credit.str("customer")
        let date = credit.int("date")
        let invoices = file.allRecords().filter { $0.str("customer") == customer && $0.int("type") == 2 && $0.int("status") == 0 }
        let ordered = invoices.filter { $0.int("invoice") == target } + invoices.filter { $0.int("invoice") != target }
        var deductions: Int64 = 0
        var count: Int64 = 0
        for var invoice in ordered where remaining > 0 {
            let balance = itemTotal(invoice) - invoice.int("paid")
            guard balance >= 0 else { continue }
            let deduction = invoice.int("date") + 1 + invoice.int("deduction-days") > date
                ? invoice.int("deduction") + invoice.int("deduction-tax") : 0
            let amount = max(0, min(remaining, balance - deduction))
            invoice.setInt("paid", invoice.int("paid") + amount)
            invoice.setInt("paid-current", invoice.int("paid-current") + amount)
            remaining -= amount
            credit.setInt("paid", credit.int("paid") + amount)
            if amount == balance - deduction {
                invoice.setInt("status", 1)
                if deduction > 0 {
                    invoice.setInt("deduction", 0)
                    invoice.setInt("deduction-tax", 0)
                    deductions += deduction
                    count += 1
                }
            }
            guard file.rewrite(invoice) == "00" else { throw Error.writeFailed }
        }
        if remaining == 0 { credit.setInt("status", 1) }
        return (deductions, count)
    }
}

private final class InvoicePostingReport {
    private let printer: SalesProofRecords.Printer
    private let system: Record
    private let limit: Int
    private var page = 0
    private var lines = 0
    private var totals = Array(repeating: (net: Int64(0), tax: Int64(0)), count: 4)

    init(store: FileStore, system: Record) {
        printer = SalesProofRecords.Printer(store)
        self.system = system
        limit = max(24, Int(system.int("page-lines")))
        headings()
    }

    private func headings(credits: Bool = false) {
        page += 1
        let header = Cobol.x("SL060 (3.01.14)", 54) + Cobol.x("Invoice Posting Report", 70) + "Page "
            + Pic.edit("zz9", value: Int64(page), scale: 0)
        let date = reportDate(system.int("run-date"))
        let company = Cobol.x(system.str("usera"), 122) + date
        if page == 1 {
            printer.before(1, header)
            printer.before(1, company)
        } else {
            printer.afterPage(header)
            printer.after(1, company)
            if credits { printer.after(1, Cobol.x("", 56) + "Un-Applied Credits") }
            printer.after(1, "")
        }
        if credits {
            printer.after(1, "--Customer--   Invoice      Bal C/F        Applied      Cr. Note          Type")
        } else {
            printer.after(1, Cobol.x(" Number     Date    <------------Customer------------>   Type  ", 64)
                + " Old Balance  New Balance   Dedn     Net         Vat       Gross")
        }
        printer.after(1, "")
        lines = credits ? 6 : 5
    }

    func add(_ item: Record, name: String, old: Int64, new: Int64, deducted: Int64, net: Int64, tax: Int64) {
        let type = Int(item.int("type"))
        let number = Pic.edit("z(7)9", value: item.int("invoice"), scale: 0)
        let date = reportDate(item.int("date"))
        let deduction = deducted == 0 ? Cobol.x("", 7) : Pic.edit("zzz9.99", value: deducted, scale: 2)
        let detail = number + " " + Cobol.x(date, 11) + Cobol.x(item.str("customer"), 9) + Cobol.x(name, 25)
            + "  " + Cobol.x(["", "Receipt", "Invoice", "CR. Note"][type], 9)
        let amounts = [old, new].map(amount).joined() + deduction + [net, tax, net + tax].map(amount).joined()
        printer.after(1, detail + amounts)
        totals[type].net += net
        totals[type].tax += tax
        lines += 1
        if lines > limit { headings() }
    }

    func finishMain(deductions: Int64) {
        if lines > limit - 7 { headings() }
        for (index, title) in ["Receipts", "Invoices", "Credit Notes"].enumerated() {
            let total = totals[index + 1]
            let amounts = [total.net, total.tax, total.net + total.tax].map(totalAmount).joined()
            printer.after(index == 0 ? 3 : 2, Cobol.x("", 11) + Cobol.x("Total  Posted", 14)
                + Cobol.x(title, 18) + amounts)
        }
        printer.after(2, Cobol.x("           Total  Amount Late Deductions", 43) + totalAmount(deductions))
        lines += 9
    }

    func unapplied(_ credit: Record, balance: Int64) {
        if lines > limit { headings(credits: true) }
        func field(_ key: String) -> String {
            let value = credit.int(key)
            return value == 0 ? Cobol.x("", 10) : Pic.edit("z(7)9", value: value, scale: 0) + "  "
        }
        func money(_ value: Int64) -> String {
            value == 0 ? Cobol.x("", 11) : Pic.edit("z(7)9.99", value: abs(value), scale: 2)
        }
        let columns = [field("invoice"), money(balance), money(credit.int("paid")), field("credit"), "CR. Note"]
        printer.after(1, Cobol.x(credit.str("customer"), 12) + columns.joined(separator: "    "))
        lines += 1
    }

    func close(unapplied: Int64, missingCustomer: Bool) throws {
        if lines > limit - 6 { headings(credits: true) }
        let total = unapplied == 0 ? "" : Pic.edit("z(7)9.99", value: abs(unapplied), scale: 2)
        printer.after(3, Cobol.x("", 24) + Cobol.x("Un-Applied Credits C/F ", 32) + total)
        if missingCustomer { printer.after(3, "SL134 Warning Record/s missing in Sales File") }
        try printer.close()
    }

    private func reportDate(_ day: Int64) -> String {
        guard (1...3_067_671).contains(day) else { return "" }
        return Maps04.format(Maps04.toDate(Int(day)), dateForm: Int(system.int("date-form")))
    }

    private func amount(_ value: Int64) -> String { Pic.edit("z(6)9.99cr", value: value, scale: 2) }
    private func totalAmount(_ value: Int64) -> String { Pic.edit("z(7)9.99cr", value: value, scale: 2) }
}
