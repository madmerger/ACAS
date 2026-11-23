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
            if drafts.contains(where: { !$0.useUnappliedBalance }) {
                system.setInt("s-flag-p", 1)
            }
            system.setInt("first-sl-batch", batch + 1)
            system["oi-3-flag"] = "Y"
            try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        }
        return batch
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
        let file = SalesOpenItems.file(context.store)
        guard file.start(notLessThan: SalesOpenItems.key(customer: customer, invoice: 0)) else { return [] }
        var result: [Record] = []
        while let record = file.readNext(), record.str("customer") == customer {
            if record.int("type") == 2, record.int("batch") == 0 { result.append(record) }
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
