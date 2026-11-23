import Foundation

extension PurchaseLedger {
    @discardableResult
    public func postTransactions() throws -> [Transaction] {
        try store.withTransaction { try PurchasePosting(self).post() }
    }
}

private final class PurchasePosting {
    typealias R = PurchaseRecords
    let ledger: PurchaseLedger
    var system: Record
    var totals: Record
    var batch: Record?
    var postingNumber: Int
    var printPage = 0
    var printLines = 0
    var reportNet = [Int64](repeating: 0, count: 4)
    var reportTax = [Int64](repeating: 0, count: 4)
    let reportTypes = ["", "Receipt", "Invoice", "Cr. Note"]
    let printer: PurchasePrinter
    var store: FileStore { ledger.store }
    var archivePath: String { ledger.base + "openitm5.dat" }
    var pageLength: Int { max(8, Int(system.int("page-lines"))) }
    var usesGL: Bool { system.int("level-1") == 1 }
    var usesIRS: Bool { system.str("irs-instead") == "Y" }

    init(_ ledger: PurchaseLedger) {
        self.ledger = ledger
        self.system = ledger.system
        self.totals = Record(R.sys4Layout, bytes: ledger.systemFile.read(4) ?? SystemAuxRecords.initialRecord4())
        self.postingNumber = max(1, Int(system.int("postings") + 1))
        self.printer = PurchasePrinter(ledger)
    }

    func post() throws -> [PurchaseLedger.Transaction] {
        let stagingPath = ledger.base + "openitm4.dat"
        let staged = store.readRaw(stagingPath) ?? []
        let size = R.oiLayout.size
        guard staged.count.isMultiple(of: size) else { throw PurchaseLedger.Error.invalidTransaction }
        var keys = Set<[UInt8]>()
        var items: [(header: Record?, item: Record, staged: Bool)] = []
        for offset in stride(from: 0, to: staged.count, by: size) {
            let item = Record(R.oiLayout, bytes: Array(staged[offset..<(offset + size)]))
            let key = openKey(item)
            guard (1...3).contains(item.int("oi-type")) else { throw PurchaseLedger.Error.invalidTransaction }
            guard keys.insert(key).inserted, store.read(archivePath, key: key) == nil else {
                throw PurchaseLedger.Error.duplicateTransaction
            }
            let header = ledger.header(item.int("oi-invoice")).flatMap {
                $0.raw("ih-supplier") == item.raw("oi-supplier") && $0.str("ih-status").uppercased() == "Z" ? $0 : nil
            }
            items.append((header, item, true))
        }
        let headers = ledger.headers().filter { $0.str("ih-status").uppercased() != "Z" }
        for header in headers {
            guard ledger.decodeTransaction(header) != nil else { throw PurchaseLedger.Error.invalidTransaction }
            let item = openItem(header)
            let key = openKey(item)
            guard keys.insert(key).inserted, store.read(archivePath, key: key) == nil else {
                throw PurchaseLedger.Error.duplicateTransaction
            }
            items.append((header, item, false))
        }
        guard !items.isEmpty else { return [] }
        guard items.allSatisfy({ ledger.supplierRecord($0.item.str("oi-supplier")) != nil }) else {
            throw PurchaseLedger.Error.supplierNotFound
        }
        if usesGL {
            let chunks = (items.count - 1) / 99
            for offset in 0...chunks {
                let number = system.int("next-batch") + Int64(offset)
                let key = Array(("2" + Cobol.z(abs(number) % 100_000, 5)).utf8)
                guard store.read(ledger.base + "batch.dat", key: key) == nil else { throw PurchaseLedger.Error.duplicateTransaction }
            }
        }
        head(credits: false)
        PurchaseAnalysisPosting(ledger).accumulate(headers: items.compactMap { $0.staged ? nil : $0.header })
        for (header, storedItem, staged) in items {
            var item = storedItem
            if usesGL { try writePosting(item) }
            if item.int("oi-type") == 3 { allocateCredit(&item) }
            updateSupplier(item, tally: !staged)
            store.write(archivePath, key: openKey(item), data: item.bytes)
            if var header {
                header["ih-status"] = "z"
                header["ih-update"] = "z"
                store.rewrite(ledger.invoicePath, key: ledger.invoiceKey(item.int("oi-invoice")), data: header.bytes)
            }
        }
        closeBatch()
        if printLines > pageLength - 7 { head(credits: false) }
        let categories = ["Receipts", "Invoices", "Credit Notes"]
        for i in 1...3 {
            let text = Cobol.x("", 11) + Cobol.x("Total  Posted", 14) + Cobol.x(categories[i - 1], 18)
                + figure(reportNet[i], digits: 8) + figure(reportTax[i], digits: 8)
                + figure(reportNet[i] + reportTax[i], digits: 8)
            printer.write(text, after: i == 1 ? 3 : 2)
        }
        finishUnappliedCredits()
        try printer.close()
        try store.writeRaw(stagingPath, [])
        system.setInt("p-flag-i", 2)
        system.setInt("p-flag-a", 1)
        system["oi-5-flag"] = "Y"
        ledger.setFileFlag(29, in: &system)
        try ledger.systemFile.write(1, system.bytes)
        var retained = ledger.systemFile.read(4) ?? SystemAuxRecords.initialRecord4()
        retained.replaceSubrange(0..<totals.bytes.count, with: totals.bytes)
        try ledger.systemFile.write(4, retained)
        return items.compactMap { item in
            guard item.header != nil else { return nil }
            return ledger.header(item.item.int("oi-invoice")).flatMap(ledger.decodeTransaction)
        }
    }

    private func openKey(_ item: Record) -> [UInt8] { Array(item.bytes.prefix(11)) }

    private func openItem(_ header: Record) -> Record {
        var item = Record(R.oiLayout)
        item["oi-supplier"] = header.str("ih-supplier")
        for field in ["invoice", "date", "type", "days", "deduct-amt", "deduct-days", "cr"] {
            item.setInt("oi-" + field, header.int("ih-" + field))
        }
        for field in ["order", "ref"] { item["oi-" + field] = header.str("ih-" + field) }
        let sign: Int64 = header.int("ih-type") == 3 ? -1 : 1
        for field in ["net", "vat", "carriage", "c-vat"] {
            item.setInt("oi-" + field, sign * header.int("ih-" + field))
        }
        return item
    }

    private func figure(_ value: Int64, digits: Int = 7) -> String {
        R.cr("z(\(digits - 1))9.99cr", value, int: digits)
    }

    private func goods(_ item: Record) -> Int64 { item.int("oi-net") }
    private func net(_ item: Record) -> Int64 { Cobol.truncate(goods(item) + item.int("oi-carriage"), digits: 9) }
    private func tax(_ item: Record) -> Int64 { Cobol.truncate(item.int("oi-vat") + item.int("oi-c-vat"), digits: 9) }
    private func gross(_ item: Record) -> Int64 { Cobol.truncate(net(item) + tax(item), digits: 9) }

    private func addTotal(_ name: String, _ value: Int64) {
        totals.setInt(name, Cobol.truncate(totals.int(name) + value, digits: 10))
    }

    private func updateSupplier(_ item: Record, tally: Bool) {
        guard var supplier = ledger.supplierRecord(item.str("oi-supplier")) else { return }
        let type = Int(item.int("oi-type")), quarter = system.int("current-quarter")
        let value = gross(item)
        let old = supplier.int("purch-current") - supplier.int("purch-unapplied")
        if (1...4).contains(quarter) {
            let field = "turnover-q\(quarter)"
            supplier.setInt(field, Cobol.truncate(supplier.int(field) + goods(item), digits: 10))
        }
        let activity = supplier.int("purch-activety"), average = supplier.int("purch-average")
        if type == 3 {
            if activity != 0 && average != 0 {
                supplier.setInt("purch-average", (activity * average + goods(item) / 100) / activity)
            }
            supplier.setInt("purch-last-pay", item.int("oi-date"))
        } else {
            let count = activity + 1
            supplier.setInt("purch-activety", count)
            if count != 0 { supplier.setInt("purch-average", (activity * average + goods(item) / 100) / count) }
            supplier.setInt("purch-last-inv", item.int("oi-date"))
            if type == 1 { supplier.setInt("purch-last-pay", item.int("oi-date")) }
        }
        if type != 1 {
            let current = Cobol.truncate(supplier.int("purch-current") + value, digits: 10)
            supplier.setInt("purch-current", max(0, current))
            if current < 0 {
                supplier.setInt("purch-unapplied", Cobol.truncate(supplier.int("purch-unapplied") - current, digits: 10))
            }
            if tally { addTotal(type == 2 ? "pl-invoices-this-month" : "pl-credit-notes-this-month", abs(value)) }
        }
        supplier.setInt("purch-status", 1)
        store.rewrite(ledger.suppliersPath, key: Array(supplier.bytes.prefix(7)), data: supplier.bytes)
        reportNet[type] = Cobol.truncate(reportNet[type] + net(item), digits: 9)
        reportTax[type] = Cobol.truncate(reportTax[type] + tax(item), digits: 9)
        let new = supplier.int("purch-current") - supplier.int("purch-unapplied")
        let line = Pic.edit("z(7)9", value: item.int("oi-invoice"), scale: 0) + " "
            + Cobol.x(ledger.reportDate(item.int("oi-date")), 11) + Cobol.x(item.str("oi-supplier"), 9)
            + Cobol.x(supplier.str("purch-name"), 25) + "  " + Cobol.x(reportTypes[type], 9)
            + figure(old) + figure(new) + Cobol.x("", 7) + figure(net(item)) + figure(tax(item)) + figure(value)
        printer.write(line, after: 1)
        printLines += 1
        if printLines > pageLength { head(credits: false) }
    }

    private func head(credits: Bool) {
        printPage += 1
        let title = Cobol.x("PL060 (3.01.07)", 54) + Cobol.x("Invoice Posting Report", 70)
            + "Page " + Pic.edit("zz9", value: Int64(printPage % 1000), scale: 0)
        let company = Cobol.x(system.str("usera"), 54) + Cobol.x("", 68) + ledger.reportDate(system.int("run-date"))
        if printPage == 1 {
            printer.writeBefore(title, before: 1)
            printer.writeBefore(company, before: 1)
        } else {
            printer.writePage(title)
            printer.write(company, after: 1)
            if credits { printer.write(Cobol.x("", 56) + "Unapplied Credits", after: 1) }
            printer.write("", after: 1)
        }
        let columns = credits ? " Supplier     Folio       Amount       Applied       Reference       Type"
            : " Number     Date    <------------Supplier------------>    Type   Old Balance  New Balance            Net         Vat       Gross"
        printer.write(columns, after: 1)
        printer.write("", after: 1)
        printLines = credits ? 6 : 5
    }

    private func allocateCredit(_ credit: inout Record) {
        let supplier = Array(credit.bytes.prefix(7))
        let target = credit.int("oi-cr")
        let items = store.all(archivePath).filter { $0.key.starts(with: supplier) }.map { Record(R.oiLayout, bytes: $0.data) }
        var remaining = -gross(credit)
        for var invoice in items.filter({ $0.int("oi-invoice") == target }) + items.filter({ $0.int("oi-invoice") != target }) {
            guard remaining > 0, invoice.int("oi-status") != 1, invoice.int("oi-type") == 2 else { continue }
            let balance = gross(invoice) - invoice.int("oi-paid")
            let applied = min(remaining, max(0, balance))
            invoice.setInt("oi-paid", invoice.int("oi-paid") + applied)
            invoice.setInt("oi-p-c", invoice.int("oi-p-c") + applied)
            credit.setInt("oi-paid", credit.int("oi-paid") + applied)
            if balance == applied { invoice.setInt("oi-status", 1) }
            store.rewrite(archivePath, key: openKey(invoice), data: invoice.bytes)
            remaining -= applied
        }
        if remaining == 0 { credit.setInt("oi-status", 1) }
    }

    private func finishUnappliedCredits() {
        let outstanding = store.all(archivePath).map { Record(R.oiLayout, bytes: $0.data) }
            .filter { $0.int("oi-status") != 1 && $0.int("oi-type") == 3 }
        guard !outstanding.isEmpty else { return }
        head(credits: true)
        var balance: Int64 = 0
        for var item in outstanding {
            let amount = Cobol.truncate(gross(item) + item.int("oi-paid"), digits: 9)
            balance = Cobol.truncate(balance + amount, digits: 9)
            printer.write(Cobol.x(item.str("oi-supplier"), 12) + " " + String(item.int("oi-invoice")) + " "
                          + figure(amount) + " " + figure(item.int("oi-paid")), after: 1)
            printLines += 1
            if printLines > pageLength { head(credits: true) }
            item.setInt("oi-paid", item.int("oi-paid") - amount)
            item.setInt("oi-status", 1)
            store.rewrite(archivePath, key: openKey(item), data: item.bytes)
        }
        addTotal("pl-cn-unappl-this-month", balance)
        printer.write(Cobol.x("", 24) + Cobol.x("Unapplied credits carried forward", 32) + figure(balance, digits: 8), after: 3)
    }

    private func startBatch() -> Record {
        var batch = Record(R.batchLayout)
        let next = system.int("next-batch")
        batch.setInt("batch-nos", abs(next) % 100_000)
        system.setInt("next-batch", next + 1)
        batch.setInt("ledger", 2)
        batch.setInt("bcycle", abs(system.int("scycle")) % 100)
        batch.setInt("entered", system.int("run-date"))
        batch["description"] = "Purchase Ledger Invoices"
        batch["convention"] = "DR"
        batch["batch-def-code"] = "PL"
        batch["batch-def-vat"] = "I"
        batch.setInt("batch-start", Int64(postingNumber) % 100_000)
        return batch
    }

    private func closeBatch() {
        guard let batch else { return }
        store.write(ledger.base + "batch.dat", key: Array(batch.bytes.prefix(6)), data: batch.bytes)
        if !usesIRS { system.setInt("postings", Int64(postingNumber)) }
        self.batch = nil
    }

    private func writePosting(_ item: Record) throws {
        var batch = batch ?? startBatch()
        let count = batch.int("items") + 1
        batch.setInt("items", count)
        var row = Record(R.postLayout)
        row.setInt("batch", batch.int("batch-nos"))
        row.setInt("post-number", count)
        row["post-code"] = "PL"
        let date = Maps04.toDate(Int(item.int("oi-date")))
        row["post-date"] = String(date.prefix(6)) + String(date.suffix(2))
        row.setInt("post-dr", abs(system.int("bl-purch-ac")) % 1_000_000)
        row.setInt("post-cr", abs(system.int("p-creditors")) % 1_000_000)
        row.setInt("vat-ac", abs(system.int("vat-ac")) % 1_000_000)
        row["post-vat-side"] = "DR"
        row.setInt("post-amount", net(item))
        row.setInt("vat-amount", tax(item))
        let name = ledger.supplierRecord(item.str("oi-supplier"))?.str("purch-name") ?? ""
        row["post-legend"] = String(item.int("oi-invoice")) + " : " + name
        for field in ["input-gross", "actual-gross"] { batch.setInt(field, abs(batch.int(field) + net(item)) % 100_000_000_000) }
        for field in ["input-vat", "actual-vat"] { batch.setInt(field, abs(batch.int(field) + tax(item)) % 100_000_000_000) }
        if usesIRS {
            var bytes = Array(row.bytes.prefix(20))
            bytes += Array(Cobol.z(row.int("post-dr") % 100_000, 5).utf8) + Array(Cobol.z(row.int("post-cr") % 100_000, 5).utf8)
            bytes += R.signLeading(net(item), digits: 9) + row.raw("post-legend")
            bytes += Array("31DR".utf8) + R.signLeading(tax(item), digits: 9)
            try store.appendRaw(ledger.base + "postings2irs.dat", bytes)
        } else {
            try RelativeFile(store, path: ledger.base + "posting.dat", recordSize: R.postLayout.size).write(postingNumber, row.bytes)
            postingNumber += 1
        }
        self.batch = batch
        if count == 99 { closeBatch() }
    }
}
