import Foundation

extension PurchaseLedger {
    @discardableResult
    public func proofPayments() throws -> [Payment] {
        try generatePaymentProof().payments
    }

    public func generatePaymentProof() throws -> (payments: [Payment], report: Data?) {
        try store.withTransaction { try writePaymentProof() }
    }

    private func writePaymentProof() throws -> (payments: [Payment], report: Data?) {
        let payments = pendingPayments()
        var settings = system
        guard settings.int("p-flag-p") != 0 else { return (payments, nil) }
        let sortPath = base + "oisort.wrk"
        let fields = ["oi-b-nos", "oi-b-item", "oi-type", "oi-date", "oi-invoice"]
        let sorted = openItemRecords().filter {
            [2, 5, 6].contains($0.int("oi-type")) && ($0.int("oi-b-nos") != 0 || $0.int("oi-b-item") != 0)
        }.sorted { first, second in
            for key in fields where first.int(key) != second.int(key) {
                return key == "oi-type" ? first.int(key) > second.int(key) : first.int(key) < second.int(key)
            }
            return false
        }
        try store.writeRaw(sortPath, sorted.flatMap { $0.bytes.prefix(105) + Array(repeating: UInt8(0x20), count: 4) })
        try writePaymentReport("PL095 (3.01.04)", title: "Cash Proof Report", payments: payments, items: sorted)
        settings["oi-5-flag"] = "Y"
        settings.setInt("p-flag-p", 2)
        try systemFile.write(1, settings.bytes)
        return (payments, store.readRaw(Self.reportPath).map { Data($0) })
    }

    @discardableResult
    public func postPayments() throws -> [Payment] {
        try postPaymentsWithReport().payments
    }

    public func postPaymentsWithReport() throws -> (payments: [Payment], report: Data?) {
        try store.withTransaction {
            let payments = try postPendingPayments()
            return (payments, payments.isEmpty ? nil : store.readRaw(Self.reportPath).map { Data($0) })
        }
    }

    private func postPendingPayments() throws -> [Payment] {
        let payments = pendingPayments()
        guard !payments.isEmpty else { return [] }
        var settings = system
        guard settings.int("p-flag-p") == 2 else { throw PaymentError.notProofed }
        let gl = settings.int("level-1") == 1
        let irs = settings.str("irs-instead") == "Y"
        let batchPath = base + "batch.dat"
        var nextBatch = max(1, settings.int("bl-next-batch"))
        var batchNumbers: [Int64] = []
        if gl {
            for _ in 0...((payments.count - 1) / 99) {
                while nextBatch <= Int64(Int16.max),
                      store.read(batchPath, key: Array(("2" + Cobol.z(nextBatch, 5)).utf8)) != nil {
                    nextBatch += 1
                }
                guard nextBatch < Int64(Int16.max) else { throw Error.duplicateTransaction }
                batchNumbers.append(nextBatch)
                nextBatch += 1
            }
        }
        let items = openItemRecords()
        for var invoice in items where invoice.int("oi-type") == 2 && invoice.int("oi-b-nos") != 0 && invoice.int("oi-b-item") != 0 {
            for field in ["oi-b-nos", "oi-b-item", "oi-cr"] { invoice.setInt(field, 0) }
            try requirePostingWrite(store.rewrite(openItemsPath, key: Array(invoice.bytes.prefix(11)), data: invoice.bytes), path: openItemsPath)
        }
        var totalsBytes = systemFile.read(4) ?? SystemAuxRecords.initialRecord4()
        var totals = Record(PurchaseRecords.sys4Layout, bytes: totalsBytes)
        let printer = PurchasePrinter(self)
        let heading = " Number   ---Date--- <-----------Supplier------------>  --Type-- "
            + " Old Balance    New Balance    Payment   Deduction   Apportioned"
        reportHeading(printer, id: "PL100 (3.01.14)", title: "Cash Posting Report", columns: heading)
        var summary = [[Int64]](repeating: [0, 0, 0], count: 2)
        var deductionCount: Int64 = 0
        var rrn = max(1, Int(settings.int("postings") + 1))
        var batch = Record(PurchaseRecords.batchLayout)
        for (offset, payment) in payments.enumerated() {
            let name = supplierRecord(payment.supplier)?.str("purch-name") ?? "Supplier Unknown"
            let id = payment.number ?? 0
            let key = openItemKey(supplier: payment.supplier, number: id)
            guard let bytes = store.read(openItemsPath, key: key) else { continue }
            var item = Record(PurchaseRecords.oiLayout, bytes: bytes)
            let amount = item.int("oi-paid")
            let applied = item.int("oi-net")
            let deduction = item.int("oi-deduct-amt")
            if deduction != 0 { deductionCount += 1 }
            var old: Int64 = 0
            var new: Int64 = 0
            if var supplier = supplierRecord(payment.supplier) {
                old = supplier.int("purch-current") - supplier.int("purch-unapplied")
                let current = Cobol.truncate(supplier.int("purch-current") - applied - deduction, digits: 10)
                let unapplied = Cobol.truncate(supplier.int("purch-unapplied") + amount - applied - min(0, current), digits: 10)
                supplier.setInt("purch-current", max(0, current))
                supplier.setInt("purch-unapplied", unapplied)
                supplier.setInt("purch-last-pay", item.int("oi-date"))
                try requirePostingWrite(store.rewrite(suppliersPath, key: supplier.raw("purch-key"), data: supplier.bytes), path: suppliersPath)
                new = max(0, current) - unapplied
            }
            item.setInt("oi-paid", applied)
            item.setInt("oi-status", 1)
            try requirePostingWrite(store.rewrite(openItemsPath, key: key, data: item.bytes), path: openItemsPath)
            if !payment.credit {
                totals.setInt("pl-payments", Cobol.truncate(totals.int("pl-payments") + amount, digits: 10))
            }
            let group = payment.credit ? 1 : 0
            summary[group][0] += amount; summary[group][1] += deduction; summary[group][2] += applied
            let date = Maps04.toDate(Int(item.int("oi-date")))
            let ref = Pic.edit("z9(4)", value: item.int("oi-b-nos"), scale: 0) + "/" + Cobol.z(item.int("oi-b-item"), 3) + " "
            let detail = ref + Cobol.x(date, 11) + Cobol.x(payment.supplier, 8) + Cobol.x(name, 25)
                + "    " + Cobol.x(payment.credit ? "Cr Journal" : "Payment", 10)
                + PurchaseRecords.cr("z(6)9.99cr", old, int: 7) + "  "
                + PurchaseRecords.cr("z(6)9.99cr", new, int: 7)
                + " " + paymentFigures([amount, deduction, applied])
            printer.write(detail, after: 1)
            if gl {
                if offset % 99 == 0 {
                    batch = Record(PurchaseRecords.batchLayout)
                    batch.setInt("batch-nos", batchNumbers[offset / 99])
                    batch.setInt("ledger", 2)
                    batch.setInt("entered", settings.int("run-date"))
                    batch.setInt("bcycle", settings.int("scycle"))
                    batch.setInt("batch-start", Int64(rrn))
                    batch["description"] = "Purchase Ledger Payments"
                    batch["convention"] = "DR"; batch["batch-def-code"] = "PL"; batch["batch-def-vat"] = "I"
                }
                let index = Int64(offset % 99 + 1)
                batch.setInt("items", index)
                for name in ["input-gross", "actual-gross"] {
                    batch.setInt(name, Cobol.truncate(batch.int(name) + applied, digits: 11, signed: false))
                }
                var entry = Record(PurchaseRecords.postLayout)
                entry.setInt("batch", batch.int("batch-nos"))
                entry.setInt("post-number", index)
                entry["post-code"] = "PL"
                entry["post-date"] = String(date.prefix(6)) + String(date.suffix(2))
                entry.setInt("post-dr", Cobol.truncate(settings.int("p-creditors"), digits: 6, signed: false))
                entry.setInt("post-cr", Cobol.truncate(settings.int("bl-pay-ac"), digits: 6, signed: false))
                entry.setInt("post-amount", applied)
                entry["post-legend"] = String(id) + " : " + name
                entry["post-vat-side"] = "DR"
                try writePaymentEntry(entry, rrn: rrn, irs: irs)
                if !irs { rrn += 1 }
                if index == 99 || offset == payments.count - 1 {
                    try requirePostingWrite(store.write(batchPath, key: Array(batch.bytes.prefix(6)), data: batch.bytes), path: batchPath)
                }
            }
        }
        printer.write(Cobol.x("", 29) + Cobol.x("Payment Totals", 25) + Cobol.x("", 41) + paymentFigures(summary[0]), after: 3)
        printer.write(Cobol.x("", 29) + Cobol.x("Journal Totals", 25) + Cobol.x("", 41) + paymentFigures(summary[1]), after: 2)
        try printer.close()
        try recordPaymentDeductions(count: deductionCount, amount: summary[0][1] + summary[1][1])
        if gl && !irs { settings.setInt("postings", Int64(rrn)) }
        if gl { settings.setInt("bl-next-batch", nextBatch) }
        settings["oi-5-flag"] = "Y"
        settings.setInt("p-flag-p", 0)
        try systemFile.write(1, settings.bytes)
        totalsBytes.replaceSubrange(0..<totals.bytes.count, with: totals.bytes)
        try systemFile.write(4, totalsBytes)
        return payments
    }

    func recordPaymentDeductions(count: Int64, amount: Int64) throws {
        guard amount != 0 else { return }
        let path = base + "value.dat"
        for code in ["Pzb", "Pz "] {
            let key = Array(code.utf8)
            guard let bytes = store.read(path, key: key), bytes.count == PurchaseRecords.valueLayout.size else { return }
            var record = Record(PurchaseRecords.valueLayout, bytes: bytes)
            for period in ["this", "year"] {
                let countField = period + "-count"
                let netField = period + "-net"
                record.setInt(countField, Cobol.truncate(record.int(countField) - count, digits: 5, signed: false))
                record.setInt(netField, Cobol.truncate(record.int(netField) - amount, digits: 10))
            }
            try requirePostingWrite(store.rewrite(path, key: key, data: record.bytes), path: path)
        }
    }

    func writePaymentEntry(_ entry: Record, rrn: Int, irs: Bool) throws {
        if irs {
            var row = Array(entry.bytes.prefix(20))
            row += Array(Cobol.z(entry.int("post-dr") % 100_000, 5).utf8) + Array(Cobol.z(entry.int("post-cr") % 100_000, 5).utf8)
            row += PurchaseRecords.signLeading(entry.int("post-amount"), digits: 9) + entry.raw("post-legend")
            row += Array("31DR".utf8) + PurchaseRecords.signLeading(0, digits: 9)
            try store.appendRaw(base + "postings2irs.dat", row)
        } else {
            try RelativeFile(store, path: base + "posting.dat", recordSize: PurchaseRecords.postLayout.size).write(rrn, entry.bytes)
        }
    }

    func reportHeading(_ printer: PurchasePrinter, id: String, title: String, columns: String) {
        printer.writeBefore(Cobol.x(id, 56) + Cobol.x(title, 68) + "Page   1", before: 1)
        printer.writeBefore(Cobol.x(system.str("usera"), 56) + Cobol.x("", 66) + reportDate(system.int("run-date")), before: 1)
        printer.write(columns, after: 1)
        printer.write("", after: 1)
    }

    private func paymentFigures(_ values: [Int64]) -> String {
        zip(values, [" ", "   ", ""]).map { Pic.edit("z(6)9.99b", value: $0, scale: 2) + $1 }.joined()
    }

    private func writePaymentReport(_ id: String, title: String, payments: [Payment], items: [Record]) throws {
        let printer = PurchasePrinter(self)
        reportHeading(printer, id: id, title: title, columns: " Number   ---Date--- Supplier                         Payment      Deduction   Apportioned")
        printer.write(Cobol.x("", 90) + "Folio     Date      Approp.     Balance", after: 1)
        let invoicesByPayment = Dictionary(grouping: items.filter { $0.int("oi-type") == 2 && $0.int("oi-paid") != 0 }) {
            $0.int("oi-b-nos") * 1000 + $0.int("oi-b-item")
        }
        for payment in payments {
            let name = supplierRecord(payment.supplier)?.str("purch-name") ?? "Supplier Unknown"
            guard let number = payment.number,
                  let bytes = store.read(openItemsPath, key: openItemKey(supplier: payment.supplier, number: number)) else { continue }
            let allocated = Record(PurchaseRecords.oiLayout, bytes: bytes).int("oi-approp")
            let values = [payment.amount, payment.discount, allocated]
            printer.write(Cobol.z(number, 8) + " " + Maps04.toDate(Int((try? legacyDate(payment.date)) ?? 0))
                          + " " + Cobol.x(payment.supplier, 9) + Cobol.x(name, 25) + paymentFigures(values), after: 1)
            for item in invoicesByPayment[number] ?? []
                where Cobol.rtrim(item.str("oi-supplier")) == payment.supplier {
                let reference = Pic.edit("z(7)9", value: item.int("oi-invoice"), scale: 0) + "  "
                let date = reportDate(item.int("oi-date"))
                let appropriation = min(item.int("oi-paid"), allocated)
                let amount = appropriation == 0 ? Cobol.x("", 9) : Pic.edit("z(5)9.99", value: appropriation, scale: 2)
                let balance = PurchaseRecords.cr("z(7)9.99cr", itemGross(item) - item.int("oi-paid"), int: 8)
                printer.write(Cobol.x("", 90) + reference + date + amount + balance, after: 1)
            }
        }
        try printer.close()
    }
}
