import Foundation

public struct PurchaseTransfer {
    public enum BookkeepingDestination: String {
        case dedicated = "ledgers/irs/"
        case shared = "ledgers/acas/"
    }

    public struct Invoice {
        public let number: Int
        public let supplier: String
        public let net: Int64
        public let tax: Int64
        public let date: Date?

        public init(number: Int, supplier: String, net: Int64, tax: Int64, date: Date? = nil) {
            self.number = number
            self.supplier = supplier
            self.net = net
            self.tax = tax
            self.date = date
        }
    }

    public enum Failure: Error { case unconfigured, invalidInvoice, duplicateBatch, postingAreaInUse, noSequence, saveFailed }

    private let context: BusinessContext
    private let directory = "ledgers/acas/"
    private var store: FileStore { context.store }

    private struct PostedInvoice {
        let invoice: Invoice
        let date: Int
        let supplierCode: [UInt8]
        let oldBalance: Int64
        let newBalance: Int64
    }

    public init(_ context: BusinessContext) { self.context = context }

    public func postPending() throws -> [String] {
        try store.transaction { try savePending() }
    }

    private func savePending() throws -> [String] {
        let invoicePath = directory + "pinvoice.dat"
        let supplierPath = directory + "purchled.dat"
        let settings = RelativeFile(store, path: directory + "system.dat", recordSize: 1024)
        guard let bytes = settings.read(1) else { throw Failure.unconfigured }
        let config = Record(SystemLayout.layout, bytes: bytes)
        let quarter = config.int("current-quarter")
        guard (1...4).contains(quarter), config.int("level-1") == 1 else { throw Failure.unconfigured }
        let quarterField = "turnover-q\(quarter)"
        var posted: [PostedInvoice] = []
        var headers: [([UInt8], [UInt8])] = []
        var openItems: [[UInt8]] = []
        var suppliers: [[UInt8]: Record] = [:]
        for (key, raw) in store.all(invoicePath) where key.count == 9 && key.last == 0 {
            var invoice = Record(PeriodRecords.pihLayout, bytes: raw)
            guard invoice.str("status").uppercased() == "P" else { continue }
            guard invoice.int("test") == 0, invoice.int("type") == 2 else { continue }
            let supplierKey = invoice.raw("supplier")
            guard let supplierRaw = store.read(supplierPath, key: supplierKey)
            else { throw Failure.invalidInvoice }
            var supplier = suppliers[supplierKey] ?? Record(PeriodRecords.purchLayout, bytes: supplierRaw)
            let goods = invoice.int("net")
            let net = goods + invoice.int("carriage")
            let tax = invoice.int("vat") + invoice.int("c-vat")
            let activity = supplier.int("activety")
            let nextActivity = activity + 1
            guard nextActivity > 0, nextActivity <= Int64(Int32.max) else { throw Failure.invalidInvoice }
            let oldBalance = supplier.int("current") - supplier.int("unapplied")
            let current = supplier.int("current") + net + tax
            supplier.setInt("activety", nextActivity)
            let priorTotal = Decimal(activity) * Decimal(supplier.int("average"))
            let wholeTotal = NSDecimalNumber(decimal: priorTotal + Decimal(goods) / 100).int64Value
            supplier.setInt("average", wholeTotal / nextActivity)
            supplier.setInt("last-inv", invoice.int("date"))
            supplier.setInt(quarterField, supplier.int(quarterField) + goods)
            supplier.setInt("current", max(0, current))
            if current < 0 { supplier.setInt("unapplied", supplier.int("unapplied") - current) }
            if supplier.int("status") == 0 { supplier.setInt("status", 1) }
            suppliers[supplierKey] = supplier
            let invoiceDay = Int(invoice.int("date"))
            let d = Maps04.dateOfInteger(invoiceDay)
            guard Maps04.validYMD(d.year, d.month, d.day),
                  let invoiceDate = context.calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day))
            else { throw Failure.invalidInvoice }
            let entry = Invoice(number: Int(invoice.int("invoice")), supplier: Cobol.rtrim(supplier.str("name")),
                                net: net, tax: tax, date: invoiceDate)
            posted.append(PostedInvoice(invoice: entry, date: invoiceDay, supplierCode: supplierKey,
                                        oldBalance: oldBalance, newBalance: supplier.int("current") - supplier.int("unapplied")))
            var openItem = Record(PeriodRecords.poiLayout)
            openItem.setRaw("batch", [UInt8](repeating: 0, count: 6))
            openItem.setRaw("unapplied", [0])
            for field in ["supplier", "ref", "order"] { openItem.setRaw(field, invoice.raw(field)) }
            for field in ["invoice", "date", "type", "net", "carriage", "vat", "c-vat",
                          "deduct-days", "deduct-amt", "days", "cr"] {
                openItem.setInt(field, invoice.int(field))
            }
            openItems.append(openItem.bytes)
            invoice["status"] = "z"
            invoice["update"] = "z"
            headers.append((key, invoice.bytes + raw.dropFirst(invoice.bytes.count)))
        }
        let date = context.now()
        let batches = try write(posted.map(\.invoice), processingDate: date, bookkeepingDestination: .dedicated)
        for (key, bytes) in headers {
            guard store.rewrite(invoicePath, key: key, data: bytes) else { throw Failure.saveFailed }
        }
        for (key, supplier) in suppliers {
            guard store.rewrite(supplierPath, key: key, data: supplier.bytes) else { throw Failure.saveFailed }
        }
        if !posted.isEmpty {
            let openItemPath = directory + "openitm5.dat"
            for bytes in openItems {
                guard store.write(openItemPath, key: Array(bytes.prefix(11)), data: bytes) else { throw Failure.saveFailed }
            }
            guard let bytes = settings.read(1) else { throw Failure.saveFailed }
            var system = Record(SystemLayout.layout, bytes: bytes)
            system.setInt("p-flag-i", 2)
            system["oi-5-flag"] = "Y"
            var statuses = system.raw("file-statuses")
            statuses[28] = 0x31
            system.setRaw("file-statuses", statuses)
            try settings.write(1, system.bytes)
            try store.writeRaw(directory + "prt-1", postingReport(posted, settings: config, date: date))
        }
        return batches
    }

    private func postingReport(_ posted: [PostedInvoice], settings: Record, date: Date) -> [UInt8] {
        let form = Int(settings.int("date-form"))
        let pageLines = Int(settings.int("page-lines"))
        let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
        let today = Maps04.integerOfDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
        func printedDate(_ day: Int) -> String { Maps04.format(Maps04.toDate(day), dateForm: form) }
        func detailAmount(_ value: Int64) -> String { Pic.edit("z(6)9.99cr", value: value, scale: 2) }
        func totalAmount(_ value: Int64) -> String { Pic.edit("z(7)9.99cr", value: value, scale: 2) }
        func total(_ title: String, _ net: Int64, _ tax: Int64) -> [UInt8] {
            let amounts = totalAmount(net) + totalAmount(tax) + totalAmount(net + tax)
            return SJIS.encode(String(repeating: " ", count: 11) + Cobol.x("Total  Posted", 14)
                + Cobol.x(title, 18) + amounts, size: 132)
        }
        var lines: [[UInt8]] = []
        var page = 0
        var lineCount = 0
        func headings() {
            page += 1
            let pageBreak: [UInt8] = page > 1 ? [0x0c] : []
            lines.append(pageBreak + SJIS.encode(Cobol.x("PL060 (3.01.07)", 54) + Cobol.x("Invoice Posting Report", 70)
                + "Page " + Pic.edit("zz9", value: Int64(page), scale: 0), size: 132))
            lines.append(SJIS.encode(settings.str("usera"), size: 122) + SJIS.encode(printedDate(today), size: 10))
            lines.append([])
            lines.append(SJIS.encode(" Number     Date    <------------Supplier------------>    Type  "
                + " Old Balance  New Balance            Net         Vat       Gross", size: 132))
            lines.append(SJIS.encode("", size: 132))
            lineCount = 5
        }
        headings()
        var net: Int64 = 0
        var tax: Int64 = 0
        for row in posted {
            let entry = row.invoice
            net += entry.net
            tax += entry.tax
            let supplier = row.supplierCode + [0x20, 0x20]
            let identity = Pic.edit("z(7)9b", value: Int64(entry.number), scale: 0)
                + Cobol.x(printedDate(row.date), 11)
            let amounts = detailAmount(row.oldBalance) + detailAmount(row.newBalance)
                + String(repeating: " ", count: 7) + detailAmount(entry.net)
                + detailAmount(entry.tax) + detailAmount(entry.net + entry.tax)
            let details = SJIS.encode(identity, size: 20) + supplier + SJIS.encode(entry.supplier, size: 25)
            lines.append(details + SJIS.encode("  " + Cobol.x("Invoice", 9) + amounts, size: 132 - details.count))
            lineCount += 1
            if lineCount > pageLines { headings() }
        }
        if lineCount > pageLines - 7 { headings() }
        lines += [[], [], total("Receipts", 0, 0), [], total("Invoices", net, tax), [], total("Credit Notes", 0, 0)]
        return lines.flatMap { $0 + [0x0a] }
    }

    public func write(_ invoices: [Invoice], processingDate: Date,
                      bookkeepingDestination: BookkeepingDestination = .dedicated) throws -> [String] {
        guard !invoices.isEmpty else { return [] }
        let settings = RelativeFile(store, path: directory + "system.dat", recordSize: 1024)
        guard let raw = settings.read(1) else { throw Failure.unconfigured }
        var system = Record(SystemLayout.layout, bytes: raw)
        let useIRS = system.str("irs-instead") == "Y"
        let posting = RelativeFile(store, path: directory + "posting.dat", recordSize: TransferRecords.postLayout.size)
        let batchPath = directory + "batch.dat"
        let beginning = system.int("next-batch")
        let count = invoices.count / 99 + 1
        var rowNumber = Int(system.int("postings")) + 1
        guard beginning > 0, beginning + Int64(count) <= Int64(Int16.max),
              rowNumber > 0, useIRS || rowNumber + invoices.count + count - 1 <= Int(Int16.max)
        else { throw Failure.noSequence }
        let postingDates = try invoices.map { invoice in
            let dates = context.calendar.dateComponents([.year, .month, .day], from: invoice.date ?? processingDate)
            guard let year = dates.year, let month = dates.month, let day = dates.day,
                  Maps04.validYMD(year, month, day) else { throw Failure.invalidInvoice }
            return Cobol.z(day, 2) + "/" + Cobol.z(month, 2) + "/" + Cobol.z(year % 100, 2)
        }
        let limit: Int64 = useIRS ? 999_999_999 : 9_999_999_999
        guard invoices.allSatisfy({
            (0...99_999_999).contains($0.number) && (-limit...limit).contains($0.net)
                && (-limit...limit).contains($0.tax)
        }) else { throw Failure.invalidInvoice }
        let keys = (0..<count).map { "2" + Cobol.z(beginning + Int64($0), 5) }
        guard keys.allSatisfy({ store.read(batchPath, key: Array($0.utf8)) == nil }) else { throw Failure.duplicateBatch }
        if !useIRS, invoices.indices.contains(where: { posting.read(rowNumber + $0 + $0 / 99) != nil }) {
            throw Failure.postingAreaInUse
        }

        var handedOff: [UInt8] = []
        var legend = [UInt8](repeating: 0x20, count: 32)
        for (index, key) in keys.enumerated() {
            let chunk = invoices[(index * 99)..<min(invoices.count, (index + 1) * 99)]
            let batchNumber = beginning + Int64(index)
            var batch = Record(TransferRecords.batchLayout)
            batch.setInt("ledger", 2)
            batch.setInt("batch-nos", batchNumber)
            batch.setInt("bcycle", system.int("scycle"))
            batch.setInt("entered", system.int("run-date"))
            batch.setInt("batch-start", Int64(rowNumber))
            batch.setInt("items", Int64(chunk.count))
            batch["description"] = "Purchase Ledger Invoices"
            batch["convention"] = "DR"
            batch["batch-def-code"] = "PL"
            batch["batch-def-vat"] = "I"
            var net: Int64 = 0
            var tax: Int64 = 0
            for (offset, invoice) in chunk.enumerated() {
                let date = postingDates[index * 99 + offset]
                net = abs(net + invoice.net) % 100_000_000_000
                tax = abs(tax + invoice.tax) % 100_000_000_000
                let description = Array("\(invoice.number) : ".utf8) + SJIS.encode(invoice.supplier, size: 30)
                let length = min(legend.count, description.count)
                legend.replaceSubrange(0..<length, with: description.prefix(length))
                if useIRS {
                    var record = Record(BookkeepingRecords.ledgerPostLayout)
                    record.setInt("batch", batchNumber)
                    record.setInt("post-number", Int64(offset + 1))
                    record["code"] = "PL"
                    record["date"] = date
                    record.setInt("dr", system.int("bl-purch-ac"))
                    record.setInt("cr", system.int("p-creditors"))
                    BookkeepingRecords.setSigned(&record, "amount", invoice.net)
                    record.setRaw("legend", legend)
                    record.setInt("vat-ac-def", 31)
                    record["vat-side"] = "DR"
                    BookkeepingRecords.setSigned(&record, "vat-amount", invoice.tax)
                    handedOff += record.bytes
                } else {
                    var record = Record(TransferRecords.postLayout)
                    record.setInt("batch", batchNumber)
                    record.setInt("post-number", Int64(offset + 1))
                    record["post-code"] = "PL"
                    record["post-date"] = date
                    record.setInt("post-dr", system.int("bl-purch-ac"))
                    record.setInt("post-cr", system.int("p-creditors"))
                    record.setInt("post-amount", invoice.net)
                    record.setRaw("post-legend", legend)
                    record.setInt("vat-ac", system.int("vat-ac"))
                    record["post-vat-side"] = "DR"
                    record.setInt("vat-amount", invoice.tax)
                    try posting.write(rowNumber, record.bytes)
                    rowNumber += 1
                }
            }
            for field in ["input-gross", "actual-gross"] { batch.setInt(field, net) }
            for field in ["input-vat", "actual-vat"] { batch.setInt(field, tax) }
            guard store.write(batchPath, key: batch.raw("batch-key"), data: batch.bytes) else { throw Failure.saveFailed }
            if !useIRS, index < keys.count - 1 { rowNumber += 1 }
        }
        if useIRS {
            try store.appendRaw(bookkeepingDestination.rawValue + "postings2irs.dat", handedOff)
        } else {
            system.setInt("postings", Int64(rowNumber))
        }
        system.setInt("next-batch", beginning + Int64(count))
        try settings.write(1, system.bytes)
        return keys
    }
}
