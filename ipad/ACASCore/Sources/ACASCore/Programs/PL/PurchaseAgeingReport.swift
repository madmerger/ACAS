import Foundation

extension PurchaseLedger {
    public enum PurchaseReportError: Swift.Error {
        case missingOpenItems, proofRequired, invalidMinimum
    }

    var supplierSortPath: String { base + "suppsort.inx" }
    private var agedSortPath: String { base + "poisort.wrk" }

    func reportSupplierRecords() -> [Record] {
        store.all(suppliersPath).compactMap {
            guard $0.data.count == PurchaseRecords.purchLayout.size else { return nil }
            return Record(PurchaseRecords.purchLayout, bytes: $0.data)
        }
    }

    func sortReportSuppliers() throws -> [Record] {
        let sorted = reportSupplierRecords().sorted {
            let lhs = $0.raw("purch-name"), rhs = $1.raw("purch-name")
            return lhs == rhs ? $0.raw("purch-key").lexicographicallyPrecedes($1.raw("purch-key"))
                : lhs.lexicographicallyPrecedes(rhs)
        }
        try store.writeRaw(supplierSortPath, sorted.flatMap { $0.raw("purch-key") })
        return sorted
    }

    private func agedItems(_ settings: inout Record) throws -> [Record] {
        let sorted = openItemRecords().sorted {
            let lhs = $0.raw("oi-supplier"), rhs = $1.raw("oi-supplier")
            if lhs != rhs { return lhs.lexicographicallyPrecedes(rhs) }
            for field in ["oi-date", "oi-invoice", "oi-type"] where $0.int(field) != $1.int(field) {
                return $0.int(field) < $1.int(field)
            }
            return false
        }
        try store.writeRaw(agedSortPath, sorted.flatMap(\.bytes))
        settings["oi-5-flag"] = "N"
        return sorted
    }

    public func agedCreditorsReport(date: Date, supplier: String = "", minimum: Int64 = 0, alphabetical: Bool = false) throws -> Data {
        guard (0..<1_000_000_000).contains(minimum) else { throw PurchaseReportError.invalidMinimum }
        let entered = try legacyDate(date)
        let report: Data? = try store.withTransaction {
            let byName = try sortReportSuppliers()
            var settings = system
            guard settings.raw("file-statuses")[28] == 0x31 else { throw PurchaseReportError.missingOpenItems }
            let items = try agedItems(&settings)
            try systemFile.write(1, settings.bytes)
            guard settings.int("p-flag-p") != 1 else { return nil }
            let records = alphabetical ? byName : reportSupplierRecords()
            let matching = SupplierReportRange(supplier)
            let grouped = Dictionary(grouping: items) { $0.raw("oi-supplier") }
            let printer = PurchasePrinter(self)
            var page: Int64 = 0
            var line: Int64 = 0
            func headings(summary: Bool = false) {
                page += 1
                let title = Cobol.x("PL120 (3.01.08)", 56) + Cobol.x("Aged Creditors Report", 22)
                    + Cobol.x(alphabetical && !summary ? "(Sorted)" : "", 46) + "Page " + Pic.edit("zz9", value: page, scale: 0)
                if page == 1 { printer.writeBefore(title, before: 1) } else { printer.writePage(title); printer.write("", after: 1) }
                let period = settings.int("scycle")
                printer.write(Cobol.x(settings.str("usera"), 56) + "Current Period is "
                              + (period == 0 ? "  " : Pic.edit("z9", value: period, scale: 0))
                              + Cobol.x("", 46) + reportDate(entered), after: 1)
                printer.write(summary ? "" : "Supplier              Name                 Telephone     Folio      Date       Current         30         60    90 & over   Payments", after: 2)
                line = 4
            }
            headings()
            var balances = [Int64](repeating: 0, count: 4)
            var counts = [Int64](repeating: 0, count: 4)
            var ledgerBalance: Int64 = 0
            var live: Int64 = 0, active: Int64 = 0
            var unapplied: Int64 = 0, unappliedCount: Int64 = 0
            var credit: Int64 = 0, creditCount: Int64 = 0
            var lost: Int64 = 0, lostCount: Int64 = 0
            var payments: Int64 = 0, promptTaken: Int64 = 0
            var nextItem = 0
            var bufferedItem: Record?
            func itemsForStatement(_ key: [UInt8]) -> [Record] {
                var statement: [Record] = []
                func count(_ item: Record) {
                    if [5, 6].contains(item.int("oi-type")) {
                        payments += 1
                        promptTaken += item.int("oi-deduct-amt")
                    }
                }
                if let bufferedItem {
                    let previousKey = bufferedItem.raw("oi-supplier")
                    if key.lexicographicallyPrecedes(previousKey) { return [] }
                    if previousKey == key {
                        statement.append(bufferedItem)
                        count(bufferedItem)
                    }
                }
                bufferedItem = nil
                while nextItem < items.count {
                    let item = items[nextItem]
                    nextItem += 1
                    if key.lexicographicallyPrecedes(item.raw("oi-supplier")) {
                        bufferedItem = item
                        break
                    }
                    if item.raw("oi-supplier") == key { statement.append(item) }
                    count(item)
                }
                return statement
            }
            let blank = Cobol.x("", 54)
            func money(_ amount: Int64, _ picture: String = "zzzz,zz9.99cr") -> String {
                Pic.edit(picture, value: amount, scale: 2)
            }
            for record in records {
                let key = record.raw("purch-key")
                guard matching.contains(key) else { continue }
                let supplierItems = grouped[key] ?? []
                let current = record.int("purch-current")
                let cash = record.int("purch-unapplied")
                let balance = current - cash
                ledgerBalance += balance
                live += 1
                if current != 0 && cash != 0 { unapplied += cash; unappliedCount += 1 }
                if balance < 0 { credit += balance; creditCount += 1 }
                let invoiceDay = record.int("purch-last-inv"), paymentDay = record.int("purch-last-pay")
                let recent = max(invoiceDay, paymentDay) > settings.int("s-end-cycle-date")
                let sameDay = paymentDay != 0 && invoiceDay == paymentDay
                guard balance != 0 || (sameDay ? !supplierItems.isEmpty : recent),
                      minimum == 0 || balance >= minimum else { continue }
                let statement = itemsForStatement(key)
                active += 1
                var subtotals = [Int64](repeating: 0, count: 4)
                var paid = cash
                var heading = Cobol.x(record.str("purch-key"), 9) + Cobol.x(record.str("purch-name"), 32) + record.str("purch-phone")
                if cash != 0 {
                    printer.write(heading + Cobol.x("Unapplied Cash", 67) + money(cash, "zzzzzz9.99"), after: 2)
                    heading = blank
                    line += 2
                }
                for item in statement where item.int("oi-type") != 1 {
                    if line > settings.int("page-lines") - 5 { headings() }
                    let type = item.int("oi-type"), amountPaid = item.int("oi-paid")
                    let gross = itemGross(item)
                    let day = item.int("oi-date")
                    let elapsed = entered - day
                    let eligible = elapsed <= item.int("oi-deduct-days")
                    let discount = item.int("oi-deduct-amt")
                    var values = [Cobol.x("", 14), Cobol.x("", 11), Cobol.x("", 11), Cobol.x("", 10), Cobol.x("", 12)]
                    if type == 3 {
                        let amount = gross + amountPaid
                        values[0] = amount == 0 ? "<" + money(-amountPaid, "zzzzzz9.99cr") + ">"
                            : " " + money(amount, "zzzzzz9.99cr") + " "
                    } else if type == 5 || type == 6 {
                        paid += amountPaid
                        let applied = item.int("oi-approp")
                        values[4] = amountPaid == applied ? "<" + money(amountPaid, "zzzzzz9.99") + ">"
                            : " " + money(amountPaid - applied, "zzzzzz9.99") + " "
                    } else {
                        let amount = type == 2 ? gross - amountPaid : 0
                        if !eligible && discount > 0 { lost += discount; lostCount += 1 }
                        let bucket = amount < 0 ? 0 : Int(min(3, max(0, elapsed / 30)))
                        subtotals[bucket] += amount
                        balances[bucket] += amount
                        if amount != 0 { counts[bucket] += 1 }
                        values[bucket] = switch bucket {
                        case 0: (amount == 0 ? "<" : " ") + money(amount == 0 ? amountPaid : amount, "zzzzzz9.99cr") + (amount == 0 ? ">" : " ")
                        case 3: money(amount, "zzzzzz9.99")
                        default: money(amount, "zzzzzzz9.99")
                        }
                    }
                    let number = type == 5 || type == 6 ? 0 : item.int("oi-invoice")
                    let folio = number == 0 ? Cobol.x("", 8) : Pic.edit("z(7)9", value: number, scale: 0)
                    if heading != blank { printer.write("", after: 1); line += 1 }
                    printer.write(heading + folio + item.str("oi-hold-flag") + (eligible && discount != 0 && type == 2 ? "*" : " ")
                                  + reportDate(day) + values.joined(), after: 1)
                    heading = blank
                    line += 1
                }
                if heading != blank { printer.write(heading, after: 1) }
                let limit = record.int("purch-limit")
                let overdue = balance > limit * 100
                let over = overdue ? money(balance - limit * 100, "zzz,zz9.99bb") : Cobol.x("", 12)
                let terms = Pic.edit("z9bb", value: record.int("purch-credit"), scale: 0)
                printer.write(Cobol.x(overdue ? "Over:" : "", 5) + over + "Terms: " + terms
                              + "Credit Limit:" + Pic.edit("zzzz,zz9", value: limit, scale: 0) + Cobol.x("", 6)
                              + Cobol.x(balance < 0 ? "Cr Bal:" : "Balance:", 8) + money(balance, "zzzz,zz9.99")
                              + money(subtotals[0]) + subtotals.dropFirst().map { money($0, "zzzz,zz9.99") }.joined()
                              + money(paid, "zzzz,zz9.99"), after: 1)
                printer.write("", after: 1)
                line += 2
            }
            headings(summary: true)
            let sum = balances.reduce(0, +), count = counts.reduce(0, +)
            func summary(_ name: String, _ amounts: [Int64], after: Int = 1) {
                printer.write(Cobol.x(name, 25) + amounts.map { money($0) }.joined(), after: after)
            }
            func countLine(_ name: String, _ number: Int64, after: Int = 1) {
                printer.write(Cobol.x(name, 25) + Pic.edit("zzzz,zz9bbbbb", value: number, scale: 0), after: after)
            }
            printer.write(Cobol.x("", 29) + "Total       Current         30           60       90 & over", after: 1)
            printer.write("", after: 1)
            printer.write(Cobol.x("Number of Invoices", 25) + ([count] + counts).map {
                Pic.edit("zzzz,zz9bbbbb", value: $0, scale: 0)
            }.joined(), after: 1)
            summary("Amount", [sum] + balances)
            summary("% of O/S Invoices", [10_000] + balances.map {
                sum == 0 ? 0 : Int64((Double($0) * 10_000 / Double(sum)).rounded())
            })
            summary("Average O/S Amount", [count == 0 ? 0 : sum / count] + zip(balances, counts).map { $1 == 0 ? 0 : $0 / $1 })
            var bytes = systemFile.read(4) ?? SystemAuxRecords.initialRecord4()
            var totals = Record(PurchaseRecords.sys4Layout, bytes: bytes)
            for (title, number, amount) in [
                ("Unapplied Cash", unappliedCount, unapplied), ("Payments", payments, totals.int("pl-payments")),
                ("Credit Balances", creditCount, credit), ("Prompt Payment Disc. lost", lostCount, lost)
            ] {
                printer.write(Cobol.x(title, 25) + Pic.edit("zzzz,zz9bbbbb", value: number, scale: 0) + money(amount), after: 1)
            }
            countLine("Number of Live Accounts", live)
            countLine("Number of Active Accounts", active)
            summary("% Active", [live == 0 ? 0 : active * 10_000 / live])
            if matching.isEmpty {
                countLine("  Reconciliation Data:", 0, after: 3)
                let brought = totals.int("pl-os-bal-last-month")
                let invoices = totals.int("pl-invoices-this-month")
                let creditNotes = totals.int("pl-credit-notes-this-month")
                let posted = totals.int("pl-payments")
                summary("Balance Brought Forward", [brought])
                summary("Plus: Invoices Posted", [invoices])
                summary("Less: Credit Notes Posted", [creditNotes], after: 2)
                summary("      Payments Posted", [posted])
                summary("      Prompt pay taken", [promptTaken])
                let expected = brought + invoices - creditNotes - posted - promptTaken
                let variance = ledgerBalance - expected
                summary("Balance Carried Forward", [0, expected])
                if variance != 0 { summary(" Out of Balance", [variance], after: 2) }
                totals.setInt("pl-variance", Cobol.truncate(variance, digits: 10))
                totals.setInt("pl-os-bal-this-month", Cobol.truncate(ledgerBalance, digits: 10))
                bytes.replaceSubrange(0..<PurchaseRecords.sys4Layout.size, with: totals.bytes.prefix(PurchaseRecords.sys4Layout.size))
                try systemFile.write(4, bytes)
            }
            try printer.close()
            return Data(store.readRaw(Self.reportPath) ?? [])
        }
        guard let report else { throw PurchaseReportError.proofRequired }
        return report
    }
}

struct SupplierReportRange {
    let lower: [UInt8]
    let upper: [UInt8]
    var isEmpty: Bool { lower.allSatisfy { $0 == 0x20 } }

    init(_ code: String, upperSpace: UInt8 = 0x5a) {
        lower = SJIS.encode(code.uppercased(), size: 7)
        upper = lower.map { $0 == 0x20 ? upperSpace : $0 }
    }

    func contains(_ key: [UInt8]) -> Bool {
        isEmpty || (!key.lexicographicallyPrecedes(lower) && !upper.lexicographicallyPrecedes(key))
    }
}
