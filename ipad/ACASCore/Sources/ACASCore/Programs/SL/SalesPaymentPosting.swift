public struct SalesPaymentPosting {
    public struct Entry: Identifiable {
        public var id: String { "\(customer)/\(batch)/\(item)" }
        public let customer: String
        public let batch: Int64
        public let item: Int64
        public let amount: Int64
        public let balance: Int64
        public let journal: Bool
    }

    public static let exportPath = SalesProofReport.exportPath
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func post() throws -> [Entry] {
        let store = context.store
        let settings = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var result: [Entry] = []
        try store.withTransaction {
            var system = try SalesLedger(context).systemRecord()
            guard system.int("s-flag-p") == 2 else { throw SalesPayments.Error.unavailable }
            var monthly = Record(SalesPostingRecords.monthly, bytes: settings.read(4) ?? SystemAuxRecords.initialRecord4())
            let openItems = SalesOpenItems.file(store)
            let customers = SalesProofRecords.salesFile(store)
            let ledger = system.int("level-1") == 1 ? Ledger(store: store, system: &system) : nil
            let report = Report(store, system: system)
            var current = Record(SalesProofRecords.salesLayout)
            for var record in openItems.allRecords() {
                let type = record.int("type")
                let batch = record.int("batch")
                let item = record.int("item")
                if type == 2, batch != 0, item != 0 {
                    updateStatistics(&current, with: record)
                    for field in ["batch", "item", "credit"] { record.setInt(field, 0) }
                    guard openItems.rewrite(record) == "00" else { throw SalesPayments.Error.writeFailed }
                    continue
                }
                guard type == 5 || type == 6, record.int("status") != 1, batch != 0 || item != 0 else { continue }
                let key = record.raw("customer")
                let found = customers.read(key: key)
                if let found { current = found } else { current.setRaw("sales-key", key) }
                let paid = record.int("paid")
                let applied = record.int("net")
                let deduction = record.int("deduction")
                let oldBalance = current.int("sales-current") - current.int("sales-unapplied")
                let outstanding = current.int("sales-current") - applied - deduction
                let unapplied = current.int("sales-unapplied") + paid - applied + max(0, -outstanding)
                current.setInt("sales-current", max(0, outstanding))
                current.setInt("sales-unapplied", unapplied)
                current.setInt("sales-last-pay", record.int("date"))
                let newBalance = current.int("sales-current") - current.int("sales-unapplied")
                if found != nil, customers.rewrite(current) != "00" { throw SalesPayments.Error.writeFailed }
                if type == 5 { monthly.setInt("payments", monthly.int("payments") + paid) }
                record.setInt("paid", applied)
                try ledger?.write(record, customer: current, system: &system)
                record.setInt("status", 1)
                guard openItems.rewrite(record) == "00" else { throw SalesPayments.Error.writeFailed }
                report.add(record, name: found?.str("sales-name") ?? "!! Customer Unknown", amount: paid,
                           oldBalance: oldBalance, newBalance: newBalance)
                result.append(Entry(customer: record.str("customer"), batch: batch, item: item,
                                    amount: paid, balance: newBalance, journal: type == 6))
            }
            try report.close()
            try updateDeductionAnalysis(store, count: report.deductionCount, amount: report.deductionTotal)
            try ledger?.close(system: &system)
            system["oi-3-flag"] = "Y"
            system.setInt("s-flag-p", 0)
            try settings.write(1, system.bytes)
            try settings.write(4, monthly.bytes)
        }
        return result
    }

    private func updateStatistics(_ current: inout Record, with invoice: Record) {
        let cleared = invoice.int("date-cleared")
        guard cleared != 0 else { return }
        let days = cleared - invoice.int("date")
        let count = current.int("sales-pay-activety")
        current.setInt("sales-pay-activety", count + 1)
        if count + 1 != 0 {
            current.setInt("sales-pay-average", (count * current.int("sales-pay-average") + days) / (count + 1))
        }
        if days > current.int("sales-pay-worst") { current.setInt("sales-pay-worst", days) }
    }

    private func updateDeductionAnalysis(_ store: FileStore, count: Int64, amount: Int64) throws {
        guard amount != 0 else { return }
        let file = IndexedFile(store, path: "ledgers/acas/value.dat", layout: SalesPostingRecords.value, keyLength: 3)
        for code in ["Szd", "Sz "] {
            guard var record = file.read(key: code) else { break }
            for field in ["count-this", "count-year"] { record.setInt(field, record.int(field) - count) }
            for field in ["value-this", "value-year"] { record.setInt(field, record.int(field) - amount) }
            guard file.rewrite(record) == "00" else { throw SalesPayments.Error.writeFailed }
        }
    }

    private final class Report {
        private struct Totals {
            var paid: Int64 = 0
            var deducted: Int64 = 0
            var applied: Int64 = 0

            mutating func add(paid: Int64, deducted: Int64, applied: Int64) {
                self.paid = Cobol.truncate(self.paid + paid, digits: 9)
                self.deducted = Cobol.truncate(self.deducted + deducted, digits: 9)
                self.applied = Cobol.truncate(self.applied + applied, digits: 9)
            }
        }

        private let printer: SalesProofRecords.Printer
        private let system: Record
        private var lines = 0
        private var page: Int64 = 0
        private var cash = Totals()
        private var journal = Totals()
        private(set) var deductionCount: Int64 = 0
        var deductionTotal: Int64 { Cobol.truncate(cash.deducted + journal.deducted, digits: 9) }

        init(_ store: FileStore, system: Record) {
            printer = SalesProofRecords.Printer(store)
            self.system = system
            printer.open()
            headings()
        }

        func add(_ entry: Record, name: String, amount: Int64, oldBalance: Int64, newBalance: Int64) {
            let deducted = entry.int("deduction")
            let applied = entry.int("net")
            let isJournal = entry.int("type") == 6
            if isJournal { journal.add(paid: amount, deducted: deducted, applied: applied) }
            else { cash.add(paid: amount, deducted: deducted, applied: applied) }
            if deducted != 0 { deductionCount += 1 }
            let date = Maps04.toDate(Int(entry.int("date")))
            let batch = Pic.edit("z(4)9", value: entry.int("batch"), scale: 0) + "/" + Cobol.z(entry.int("item"), 3)
            let prefix = batch + " " + Cobol.x(date, 11) + Cobol.x(entry.str("customer"), 8)
                + Cobol.x(name, 25) + "    " + Cobol.x(isJournal ? "Cr Journal" : "Payment", 11)
            let oldText = Pic.edit("z(5)9.99cr", value: oldBalance, scale: 2)
            let newText = Pic.edit("z(5)9.99cr", value: newBalance, scale: 2)
            printer.after(1, prefix + oldText + "   " + newText + "  " + totalsColumns(amount, deducted, applied))
            lines += 1
            if lines > Int(system.int("page-lines")) { headings() }
        }

        func close() throws {
            let space = SalesProofRecords.spaces
            for (spacing, label, totals) in [(3, "Payment Totals", cash), (2, "Journal Totals", journal)] {
                printer.after(spacing, space(29) + Cobol.x(label, 25) + space(42)
                    + totalsColumns(totals.paid, totals.deducted, totals.applied))
            }
            try printer.close()
        }

        private func headings() {
            page = (page + 1) % 100
            let head = Cobol.x("SL100 (3.01.12)", 56) + Cobol.x("Cash Posting Report", 68) + "Page "
                + Pic.edit("zz9", value: page, scale: 0)
            let date = Maps04.format(Maps04.toDate(Int(system.int("run-date"))), dateForm: Int(system.int("date-form")))
            let subtitle = Cobol.x(system.str("usera"), 56) + SalesProofRecords.spaces(66) + date
            if page == 1 {
                printer.before(1, head)
                printer.before(1, subtitle)
            } else {
                printer.afterPage(head)
                printer.after(1, subtitle)
                printer.after(1, "")
            }
            let labels = " Number   ---Date--  <------------Customer------------>  --Type-- "
            printer.after(1, Cobol.x(labels, 67) + " Old Balance    New Balance    Payment   Deduction   Apportioned")
            printer.after(1, "")
            lines = 5
        }

        private func totalsColumns(_ paid: Int64, _ deducted: Int64, _ applied: Int64) -> String {
            func formatted(_ value: Int64) -> String { Pic.edit("z(5)9.99", value: abs(value), scale: 2) }
            return formatted(paid) + "   " + formatted(deducted) + "     " + formatted(applied) + "  "
        }
    }

    private final class Ledger {
        private let store: FileStore
        private let irs: Bool
        private let batches: IndexedFile
        private let postingPath = "ledgers/acas/posting.dat"
        private let irsPath = "ledgers/irs/postings2irs.dat"
        private var batch = Record(SalesPostingRecords.batch)
        private var rrn = 0

        init(store: FileStore, system: inout Record) {
            self.store = store
            irs = system.str("irs-instead") == "Y"
            batches = IndexedFile(store, path: "ledgers/acas/batch.dat", layout: SalesPostingRecords.batch, keyLength: 6)
            open(system: &system)
        }

        private func open(system: inout Record) {
            var row = Record(SalesPostingRecords.batch)
            row.setInt("ledger", 3)
            row.setInt("number", system.int("next-batch"))
            row.setInt("cycle", system.int("scycle"))
            row.setInt("entered", system.int("run-date"))
            row.setInt("start", system.int("postings") + 1)
            row["description"] = "Sales-Ledger Payments"
            row["convention"] = "CR"
            row["code"] = "SL"
            row["tax-code"] = "O"
            batch = row
            rrn = Int(row.int("start"))
            system.setInt("next-batch", system.int("next-batch") + 1)
        }

        func write(_ record: Record, customer: Record, system: inout Record) throws {
            let count = batch.int("items") + 1
            let number = batch.int("number")
            let value = record.int("paid")
            let date = Maps04.toDate(Int(record.int("date")))
            let shortDate = String(date.prefix(6)) + String(date.suffix(2))
            let legend = Cobol.z(record.int("batch"), 5) + "/" + Cobol.z(record.int("item"), 3)
                + "  :  " + customer.str("sales-name")
            batch.setInt("items", count)
            for field in ["input-gross", "actual-gross"] { batch.setInt(field, batch.int(field) + value) }
            let debit = system.int("sl-pay-ac")
            let credit = system.int("s-debtors")
            if irs {
                let head = Cobol.z(number, 5) + Cobol.z(count, 5) + "SL" + shortDate + Cobol.z(debit, 5) + Cobol.z(credit, 5)
                let bytes = Array(head.utf8) + SalesPostingRecords.irsMoney(value) + SJIS.encode(legend, size: 32)
                    + Array("32CR".utf8) + SalesPostingRecords.irsMoney(0)
                try store.appendRaw(irsPath, bytes)
            } else {
                guard rrn > 0 else { throw SalesPayments.Error.writeFailed }
                var posting = Record(SalesPostingRecords.posting)
                for (field, amount) in [("batch", number), ("number", count), ("amount", value),
                                        ("debit", debit), ("credit", credit)] { posting.setInt(field, amount) }
                posting["date"] = shortDate
                posting["code"] = "SL"
                posting["legend"] = legend
                posting["tax-side"] = "CR"
                try RelativeFile(store, path: postingPath, recordSize: posting.layout.size).write(rrn, posting.bytes)
                rrn += 1
            }
            if count == 99 {
                try close(system: &system)
                open(system: &system)
            }
        }

        func close(system: inout Record) throws {
            let path = irs ? irsPath : postingPath
            if !store.exists(path) { try store.writeRaw(path, []) }
            guard batches.write(batch) == "00" else { throw SalesPayments.Error.writeFailed }
            if !irs { system.setInt("postings", Int64(rrn)) }
        }
    }
}
