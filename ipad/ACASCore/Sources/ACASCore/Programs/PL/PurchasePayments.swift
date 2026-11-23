import Foundation

extension PurchaseLedger {
    public enum PaymentError: Swift.Error {
        case invalidAmount, paymentNotFound, notProofed, unavailableInvoice, alreadyAllocated, issuedSchedule
    }

    public struct Allocation: Identifiable {
        public let id: Int64
        public var amount: Int64
        public var discount: Int64
        public init(invoice: Int64, amount: Int64, discount: Int64 = 0) {
            id = invoice
            self.amount = amount
            self.discount = discount
        }
    }

    public struct Payment: Identifiable {
        public var id: String { supplier + "/" + String(number ?? 0) }
        public var number: Int64?
        public var supplier = ""
        public var date: Date
        public var amount: Int64 = 0
        public var credit = false
        public internal(set) var discount: Int64 = 0
        public var allocations: [Allocation] = []
        public var allocated: Int64 { allocations.reduce(0) { $0 + $1.amount } }

        public init(date: Date) { self.date = date }
    }

    var openItemsPath: String { base + "openitm5.dat" }

    func openItemKey(supplier: String, number: Int64) -> [UInt8] {
        var item = Record(PurchaseRecords.oiLayout)
        item["oi-supplier"] = supplier
        item.setInt("oi-invoice", number)
        return Array(item.bytes.prefix(11))
    }

    func openItemRecords() -> [Record] {
        store.all(openItemsPath).compactMap {
            guard $0.data.count == PurchaseRecords.oiLayout.size else { return nil }
            return Record(PurchaseRecords.oiLayout, bytes: $0.data)
        }
    }

    func itemGross(_ item: Record) -> Int64 {
        Cobol.truncate(["oi-net", "oi-vat", "oi-carriage", "oi-c-vat"].reduce(0) { $0 + item.int($1) }, digits: 9)
    }

    func dateFromLegacy(_ days: Int64) -> Date {
        let parts = Maps04.dateOfInteger(Int(days))
        return context.calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? processingDate
    }

    public func proposedAllocations(supplier: String, amount: Int64, date: Date) throws -> [Allocation] {
        let day = try legacyDate(date)
        var remaining = amount
        return openItemRecords().compactMap { item in
            guard remaining > 0, Cobol.rtrim(item.str("oi-supplier")) == supplier.uppercased(),
                  item.int("oi-type") == 2, item.int("oi-b-nos") == 0, item.int("oi-status") == 0 else { return nil }
            let due = itemGross(item) - item.int("oi-paid")
            let discount = day <= item.int("oi-date") + item.int("oi-deduct-days") ? item.int("oi-deduct-amt") : 0
            let selected = min(remaining, due - discount)
            guard selected > 0 else { return nil }
            remaining -= selected
            return Allocation(invoice: item.int("oi-invoice"), amount: selected, discount: selected + discount == due ? discount : 0)
        }
    }

    public func pendingPayments() -> [Payment] {
        let items = openItemRecords()
        return items.compactMap { item in
            let type = item.int("oi-type")
            guard (type == 5 || type == 6), item.int("oi-status") == 0, item.int("oi-b-nos") != 0 else { return nil }
            var payment = Payment(date: dateFromLegacy(item.int("oi-date")))
            payment.number = item.int("oi-invoice")
            payment.supplier = Cobol.rtrim(item.str("oi-supplier"))
            payment.amount = item.int("oi-paid")
            payment.credit = type == 6
            payment.discount = item.int("oi-deduct-amt")
            let invoices = linkedInvoices(item, in: items)
            payment.allocations = invoices.map {
                Allocation(invoice: $0.int("oi-invoice"), amount: $0.int("oi-cr") / 100)
            }
            return payment
        }
    }

    private func linkedInvoices(_ payment: Record, in items: [Record]) -> [Record] {
        items.filter {
            $0.int("oi-type") == 2 && $0.raw("oi-supplier") == payment.raw("oi-supplier")
                && $0.int("oi-b-nos") == payment.int("oi-b-nos") && $0.int("oi-b-item") == payment.int("oi-b-item")
        }
    }

    private func reversedInvoices(_ payment: Record, in items: [Record],
                                  restoringDiscounts: [Int64: Int64]) throws -> [Record] {
        let invoices = linkedInvoices(payment, in: items)
        let restorable = Set(invoices.filter { $0.int("oi-deduct-amt") == 0 }.map { $0.int("oi-invoice") })
        guard restoringDiscounts.allSatisfy({ restorable.contains($0.key) && (0..<100_000).contains($0.value) }),
              restoringDiscounts.values.reduce(0, +) == payment.int("oi-deduct-amt") else {
            throw PaymentError.invalidAmount
        }
        return invoices.map { invoice in
            var restored = invoice
            let amount = invoice.int("oi-cr") / 100
            let discount = restoringDiscounts[invoice.int("oi-invoice")] ?? 0
            restored.setInt("oi-paid", invoice.int("oi-paid") - amount)
            restored.setInt("oi-p-c", invoice.int("oi-p-c") - amount)
            if discount > 0 {
                restored.setInt("oi-net", invoice.int("oi-net") + discount)
                restored.setInt("oi-deduct-amt", discount)
            }
            for field in ["oi-b-nos", "oi-b-item", "oi-cr", "oi-status"] { restored.setInt(field, 0) }
            return restored
        }
    }

    private func pendingPayment(supplier: String, number: Int64) throws -> Record {
        let key = openItemKey(supplier: supplier, number: number)
        guard let bytes = store.read(openItemsPath, key: key), bytes.count == PurchaseRecords.oiLayout.size else {
            throw PaymentError.paymentNotFound
        }
        let item = Record(PurchaseRecords.oiLayout, bytes: bytes)
        guard [5, 6].contains(item.int("oi-type")), item.int("oi-status") == 0,
              item.int("oi-b-nos") != 0, item.int("oi-b-item") != 0 else {
            throw PaymentError.paymentNotFound
        }
        return item
    }

    public func cancelPayment(supplier code: String, number: Int64, restoringDiscounts: [Int64: Int64] = [:]) throws {
        try store.withTransaction {
            try cancelPendingPayment(supplier: code, number: number, restoringDiscounts: restoringDiscounts)
        }
    }

    private func cancelPendingPayment(supplier code: String, number: Int64, restoringDiscounts: [Int64: Int64]) throws {
        guard var supplier = supplierRecord(code) else { throw Error.supplierNotFound }
        let payment = try pendingPayment(supplier: supplier.str("purch-key"), number: number)
        let invoices = try reversedInvoices(payment, in: openItemRecords(), restoringDiscounts: restoringDiscounts)
        for invoice in invoices {
            try requirePostingWrite(store.rewrite(openItemsPath, key: Array(invoice.bytes.prefix(11)), data: invoice.bytes), path: openItemsPath)
        }
        try requirePostingWrite(store.delete(openItemsPath, key: Array(payment.bytes.prefix(11))), path: openItemsPath)
        if payment.int("oi-type") == 6 {
            supplier.setInt("purch-unapplied", supplier.int("purch-unapplied") + payment.int("oi-paid"))
            try requirePostingWrite(store.rewrite(suppliersPath, key: supplier.raw("purch-key"), data: supplier.bytes), path: suppliersPath)
        }
        var configuration = system
        configuration["oi-5-flag"] = "Y"
        if configuration.int("p-flag-p") == 2 { configuration.setInt("p-flag-p", 1) }
        try systemFile.write(1, configuration.bytes)
    }

    @discardableResult
    public func savePayment(_ value: Payment, restoringDiscounts: [Int64: Int64] = [:]) throws -> Int64 {
        try store.withTransaction { try savePendingPayment(value, restoringDiscounts: restoringDiscounts) }
    }

    private func savePendingPayment(_ value: Payment, restoringDiscounts: [Int64: Int64]) throws -> Int64 {
        let day = try legacyDate(value.date)
        guard (1..<1_000_000_000).contains(value.amount), value.allocations.count <= 999,
              Set(value.allocations.map(\.id)).count == value.allocations.count,
              value.allocations.allSatisfy({ (1...Int64(Int32.max) / 100).contains($0.amount) && (0..<100_000).contains($0.discount) }),
              value.allocations.reduce(0, { $0 + $1.discount }) < 100_000,
              value.allocated <= value.amount else { throw PaymentError.invalidAmount }
        guard var supplier = supplierRecord(value.supplier) else { throw Error.supplierNotFound }
        let supplierCode = supplier.str("purch-key")
        let items = openItemRecords()
        var configuration = system
        let currentBatch = max(1, configuration.int("bl-next-batch") % 100_000)
        var batch = currentBatch
        var index = Int64(1)
        var modified: [Int64: Record] = [:]
        if let number = value.number {
            let previous = try pendingPayment(supplier: supplierCode, number: number)
            batch = previous.int("oi-b-nos")
            index = previous.int("oi-b-item")
            if previous.int("oi-type") == 6 {
                supplier.setInt("purch-unapplied", supplier.int("purch-unapplied") + previous.int("oi-paid"))
            }
            for invoice in try reversedInvoices(previous, in: items, restoringDiscounts: restoringDiscounts) {
                modified[invoice.int("oi-invoice")] = invoice
            }
        } else {
            let usedNumbers = Set(items.filter { $0.str("oi-supplier") == supplierCode }.map { $0.int("oi-invoice") })
            let usedBatchItems = Set(items.filter { $0.int("oi-b-nos") != 0 }.map { $0.int("oi-b-nos") * 1000 + $0.int("oi-b-item") })
            while usedNumbers.contains(batch * 1000 + index) || usedBatchItems.contains(batch * 1000 + index) {
                index += 1
                if index > 999 { batch = batch == 99_999 ? 1 : batch + 1; index = 1 }
                guard batch != currentBatch || index != 1 else { throw Error.duplicateTransaction }
            }
        }
        let number = batch * 1000 + index
        let key = openItemKey(supplier: supplierCode, number: number)
        guard value.number != nil || store.read(openItemsPath, key: key) == nil else { throw Error.duplicateTransaction }
        if value.credit {
            let unapplied = supplier.int("purch-unapplied")
            guard unapplied >= value.amount else { throw PaymentError.invalidAmount }
            supplier.setInt("purch-unapplied", unapplied - value.amount)
        }
        for allocation in value.allocations {
            guard var invoice = modified[allocation.id] ?? items.first(where: {
                $0.str("oi-supplier") == supplierCode && $0.int("oi-invoice") == allocation.id && $0.int("oi-type") == 2
            }) else { throw PaymentError.unavailableInvoice }
            guard invoice.int("oi-b-nos") == 0, invoice.int("oi-status") == 0 else { throw PaymentError.alreadyAllocated }
            let balance = itemGross(invoice) - invoice.int("oi-paid")
            guard allocation.amount + allocation.discount <= balance,
                  allocation.discount == 0 || (allocation.discount == invoice.int("oi-deduct-amt")
                    && allocation.amount + allocation.discount == balance) else { throw PaymentError.invalidAmount }
            invoice.setInt("oi-paid", invoice.int("oi-paid") + allocation.amount)
            invoice.setInt("oi-p-c", invoice.int("oi-p-c") + allocation.amount)
            invoice.setInt("oi-b-nos", batch)
            invoice.setInt("oi-b-item", index)
            invoice.setInt("oi-cr", allocation.amount * 100)
            if allocation.amount + allocation.discount == balance {
                invoice.setInt("oi-status", 1)
                invoice.setInt("oi-date-cleared", day)
                if allocation.discount != 0 {
                    invoice.setInt("oi-net", invoice.int("oi-net") - allocation.discount)
                    invoice.setInt("oi-deduct-amt", 0)
                }
            }
            modified[allocation.id] = invoice
        }
        var payment = Record(PurchaseRecords.oiLayout)
        payment["oi-supplier"] = supplierCode
        payment.setInt("oi-invoice", number)
        payment.setInt("oi-date", day)
        payment.setInt("oi-type", value.credit ? 6 : 5)
        payment.setInt("oi-paid", value.amount)
        payment.setInt("oi-net", value.allocated)
        payment.setInt("oi-deduct-amt", value.allocations.reduce(0) { $0 + $1.discount })
        payment.setInt("oi-b-nos", batch)
        payment.setInt("oi-b-item", index)
        for invoice in modified.values {
            try requirePostingWrite(store.rewrite(openItemsPath, key: Array(invoice.bytes.prefix(11)), data: invoice.bytes), path: openItemsPath)
        }
        if value.number == nil {
            try requirePostingWrite(store.write(openItemsPath, key: key, data: payment.bytes), path: openItemsPath)
        } else {
            try requirePostingWrite(store.rewrite(openItemsPath, key: key, data: payment.bytes), path: openItemsPath)
        }
        try requirePostingWrite(store.rewrite(suppliersPath, key: supplier.raw("purch-key"), data: supplier.bytes), path: suppliersPath)
        if value.number == nil { configuration.setInt("bl-next-batch", (batch + 1) % 100_000) }
        if !value.credit || configuration.int("p-flag-p") == 2 { configuration.setInt("p-flag-p", 1) }
        configuration["oi-5-flag"] = "Y"
        try systemFile.write(1, configuration.bytes)
        return number
    }
}
