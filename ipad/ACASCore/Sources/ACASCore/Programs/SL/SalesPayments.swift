import Foundation

public struct SalesPayments {
    public enum Error: Swift.Error {
        case unavailable, invalidInput, invalidAllocation, writeFailed
    }

    public struct Allocation: Identifiable {
        public var id: Int64 { invoice }
        public let invoice: Int64
        public let outstanding: Int64
        public let earlyPaymentDeduction: Int64
    }

    public struct Draft {
        public var customer = ""
        public var amount: Int64 = 0
        public var useUnappliedBalance = false
        public var allocations: [Int64: Int64] = [:]
        public var acceptExpiredDeduction: Set<Int64> = []
        public let date: Date

        public init(date: Date) { self.date = date }
    }

    public struct Pending: Identifiable {
        public var id: String { "\(customer)/\(batch)/\(item)" }
        public let customer: String
        public let batch: Int64
        public let item: Int64
        public let amount: Int64
        public let journal: Bool
        public let deduction: Int64
    }

    private let context: BusinessContext
    public init(_ context: BusinessContext) { self.context = context }

    public func allocations(customer: String, date: Date) throws -> [Allocation] {
        let key = try customerKey(customer)
        let day = try dayNumber(date)
        return eligibleInvoices(key).compactMap { invoice in
            let net = SalesOpenItems.invoiceTotal(invoice)
            let deduction = invoice.int("deduction") + invoice.int("deduction-tax")
            guard net + deduction > invoice.int("paid") else { return nil }
            let isEarly = invoice.int("date") + 1 + invoice.int("deduction-days") > day
            return Allocation(invoice: invoice.int("invoice"),
                              outstanding: net + (isEarly ? 0 : deduction) - invoice.int("paid"),
                              earlyPaymentDeduction: isEarly ? deduction : 0)
        }
    }

    @discardableResult
    public func saveBatch(_ drafts: [Draft]) throws -> Int64 {
        guard !drafts.isEmpty, drafts.count <= 999 else { throw Error.invalidInput }
        let store = context.store
        var batch: Int64 = 0
        try store.withTransaction {
            var system = try SalesLedger(context).systemRecord()
            guard system.int("s-flag-i") != 1, system.raw("file-statuses")[18] == 0x31 else {
                throw Error.unavailable
            }
            batch = max(system.int("first-sl-batch"), 1)
            for (index, draft) in drafts.enumerated() {
                try write(draft, batch: batch, item: Int64(index + 1))
            }
            system.setInt("s-flag-p", 1)
            system.setInt("first-sl-batch", batch + 1)
            system["oi-3-flag"] = "Y"
            try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        }
        return batch
    }

    public func pending() throws -> [Pending] {
        guard try SalesLedger(context).systemRecord().int("s-flag-p") != 0 else { return [] }
        return SalesOpenItems.file(context.store).allRecords().compactMap { record in
            let type = record.int("type")
            guard type == 5 || type == 6, record.int("batch") != 0, record.int("item") != 0,
                  record.int("status") != 1 else { return nil }
            return Pending(customer: record.str("customer"), batch: record.int("batch"), item: record.int("item"),
                           amount: record.int("paid"), journal: type == 6, deduction: record.int("deduction"))
        }
    }

    public func restorableInvoices(_ payment: Pending) -> [Int64] {
        allocatedInvoices(payment).filter { $0.int("deduction") == 0 }.map { $0.int("invoice") }
    }

    public func cancel(_ payment: Pending, restoring deductions: [Int64: Int64] = [:]) throws {
        let store = context.store
        try store.withTransaction {
            guard try pending().contains(where: { $0.id == payment.id && $0.amount == payment.amount }) else {
                throw Error.invalidInput
            }
            let openItems = SalesOpenItems.file(store)
            let key = SalesOpenItems.key(customer: payment.customer, invoice: payment.batch * 1000 + payment.item)
            guard let stored = openItems.read(key: key) else { throw Error.invalidInput }
            var unappliedDeduction = stored.int("deduction")
            var appropriated = stored.int("net")
            var remaining = deductions.filter { $0.value != 0 }
            if appropriated != 0 {
                for var invoice in allocatedInvoices(payment) {
                    let value = invoice.int("credit") / 100
                    invoice.setInt("paid", invoice.int("paid") - value)
                    invoice.setInt("paid-current", invoice.int("paid-current") - value)
                    for field in ["batch", "item", "credit", "status"] { invoice.setInt(field, 0) }
                    appropriated -= value
                    if let deduction = remaining.removeValue(forKey: invoice.int("invoice")) {
                        guard invoice.int("deduction") == 0, deduction >= 0, deduction <= unappliedDeduction else {
                            throw Error.invalidAllocation
                        }
                        unappliedDeduction -= deduction
                        invoice.setInt("deduction", deduction)
                    }
                    guard openItems.rewrite(invoice) == "00" else { throw Error.writeFailed }
                    if appropriated == 0, unappliedDeduction == 0 { break }
                }
            }
            guard remaining.isEmpty, appropriated == 0, unappliedDeduction == 0 else { throw Error.invalidAllocation }
            if stored.int("type") == 6 {
                let customers = SalesProofRecords.salesFile(store)
                guard var row = customers.read(key: payment.customer) else { throw Error.invalidInput }
                row.setInt("sales-unapplied", row.int("sales-unapplied") + stored.int("paid"))
                guard customers.rewrite(row) == "00" else { throw Error.writeFailed }
            }
            guard openItems.delete(key: key) == "00" else { throw Error.writeFailed }
            var system = try SalesLedger(context).systemRecord()
            system["oi-3-flag"] = "Y"
            try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        }
    }

    private func allocatedInvoices(_ payment: Pending) -> [Record] {
        customerInvoices(payment.customer).filter { $0.int("batch") == payment.batch && $0.int("item") == payment.item }
    }

    private func write(_ draft: Draft, batch: Int64, item: Int64) throws {
        guard (1...999_999_999).contains(draft.amount) else { throw Error.invalidInput }
        let customer = try customerKey(draft.customer)
        let date = try dayNumber(draft.date)
        let customerFile = SalesProofRecords.salesFile(context.store)
        let openItems = SalesOpenItems.file(context.store)
        if draft.useUnappliedBalance {
            guard var row = customerFile.read(key: customer), row.int("sales-unapplied") >= draft.amount else {
                throw Error.invalidInput
            }
            row.setInt("sales-unapplied", row.int("sales-unapplied") - draft.amount)
            guard customerFile.rewrite(row) == "00" else { throw Error.writeFailed }
        }
        var remaining = draft.allocations.filter { $0.value != 0 }
        var applied: Int64 = 0
        var deducted: Int64 = 0
        var lastClearedDate: Int64 = 0
        for var invoice in eligibleInvoices(customer) {
            lastClearedDate = invoice.int("date-cleared")
            let net = SalesOpenItems.invoiceTotal(invoice)
            let deduction = invoice.int("deduction") + invoice.int("deduction-tax")
            let paid = invoice.int("paid")
            let fullAmount = net + deduction - paid
            if fullAmount == 0, invoice.int("status") == 0 {
                invoice.setInt("status", 1)
                invoice.setInt("date-cleared", date)
                lastClearedDate = date
                guard openItems.rewrite(invoice) == "00" else { throw Error.writeFailed }
                continue
            }
            guard fullAmount > 0, let value = remaining.removeValue(forKey: invoice.int("invoice")) else { continue }
            guard value > 0, value <= fullAmount, value <= draft.amount - applied else { throw Error.invalidAllocation }
            let early = invoice.int("date") + 1 + invoice.int("deduction-days") > date
            let deduct = value == net - paid && (early || draft.acceptExpiredDeduction.contains(invoice.int("invoice")))
            if deduct {
                invoice.setInt("deduction", 0)
                invoice.setInt("deduction-tax", 0)
                deducted += deduction
            }
            if deduct || value == fullAmount {
                invoice.setInt("status", 1)
                invoice.setInt("date-cleared", date)
                lastClearedDate = date
            }
            invoice.setInt("batch", batch)
            invoice.setInt("item", item)
            invoice.setInt("paid", paid + value)
            invoice.setInt("paid-current", invoice.int("paid-current") + value)
            invoice.setInt("credit", value * 100)
            guard openItems.rewrite(invoice) == "00" else { throw Error.writeFailed }
            applied += value
            if applied == draft.amount { break }
        }
        guard remaining.isEmpty else { throw Error.invalidAllocation }
        var payment = Record(SalesOpenItems.layout)
        payment["customer"] = customer
        for (field, value) in [
            ("invoice", batch * 1000 + item), ("batch", batch), ("item", item), ("date", date),
            ("type", draft.useUnappliedBalance ? 6 : 5), ("paid", draft.amount),
            ("net", applied), ("deduction", deducted), ("date-cleared", lastClearedDate),
        ] {
            payment.setInt(field, value)
        }
        guard openItems.write(payment) == "00" else { throw Error.writeFailed }
    }

    private func eligibleInvoices(_ customer: String) -> [Record] {
        customerInvoices(customer).filter { $0.int("batch") == 0 }
    }

    private func customerInvoices(_ customer: String) -> [Record] {
        let file = SalesOpenItems.file(context.store)
        guard file.start(notLessThan: SalesOpenItems.key(customer: customer, invoice: 0)) else { return [] }
        var result: [Record] = []
        while let record = file.readNext(), record.str("customer") == customer {
            if record.int("type") == 2 { result.append(record) }
        }
        return result
    }

    private func customerKey(_ code: String) throws -> String {
        try SalesLedger(context).customer(code: code).code
    }

    private func dayNumber(_ date: Date) throws -> Int64 {
        let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              Maps04.validYMD(year, month, day) else { throw Error.invalidInput }
        return Int64(Maps04.integerOfDate(year: year, month: month, day: day))
    }
}
