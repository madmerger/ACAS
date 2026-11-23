import Foundation

extension PurchaseLedger {
    public func registerScheduledPayments() throws {
        try store.withTransaction {
            let records = scheduleRecords()
            guard !records.isEmpty else { throw ScheduleError.noSchedule }
            try writeChequeRegister(records)
            var configuration = system
            let gl = configuration.int("level-1") == 1
            let irs = configuration.str("irs-instead") == "Y"
            let batchPath = base + "batch.dat"
            var nextBatch = configuration.int("bl-next-batch")
            var rrn = max(1, Int(configuration.int("postings")) + 1)
            var batch = Record(PurchaseRecords.batchLayout)
            func startBatch() {
                batch = Record(PurchaseRecords.batchLayout)
                batch.setInt("ledger", 2)
                batch.setInt("batch-nos", nextBatch)
                batch.setInt("bcycle", configuration.int("scycle"))
                batch.setInt("entered", configuration.int("run-date"))
                batch.setInt("batch-start", Int64(rrn))
                batch["description"] = "Purchase Ledger Payments"
                batch["convention"] = "DR"
                batch["batch-def-code"] = "PL"
                batch["batch-def-vat"] = "I"
                nextBatch += 1
            }
            func saveBatch() throws {
                try requirePostingWrite(store.write(batchPath, key: batch.raw("batch-key"), data: batch.bytes), path: batchPath)
            }
            if gl { startBatch() }
            nextBatch = max(1, nextBatch)

            var count: Int64 = 0
            var deductions: Int64 = 0
            var series: Int64 = 0
            var payment = Record(PurchaseRecords.oiLayout)
            for record in records {
                series += 1
                if series > 999 {
                    series = 1
                    nextBatch += 1
                }
                let supplier = record.str("supplier")
                let date = record.int("date")
                var applied: Int64 = 0
                var discount: Int64 = 0
                for i in 1...9 {
                    let value = record.int("value-\(i)")
                    guard value != 0 else { continue }
                    let key = openItemKey(supplier: supplier, number: record.int("folio-\(i)"))
                    guard let bytes = store.read(openItemsPath, key: key) else { continue }
                    var item = Record(PurchaseRecords.oiLayout, bytes: bytes)
                    guard item.int("oi-type") == 2, item.str("oi-supplier") == supplier else { continue }
                    let deduct = record.int("discount-\(i)")
                    item.setInt("oi-paid", Cobol.truncate(item.int("oi-paid") + value, digits: 9))
                    if item.int("oi-paid") == Cobol.truncate(itemGross(item) - deduct, digits: 8) {
                        item.setInt("oi-status", 1)
                        item.setInt("oi-net", Cobol.truncate(item.int("oi-net") - deduct, digits: 9))
                        item.setInt("oi-deduct-amt", 0)
                        item.setInt("oi-b-nos", nextBatch)
                        item.setInt("oi-b-item", series)
                        item.setInt("oi-date-cleared", date)
                        discount = Cobol.truncate(discount + deduct, digits: 9)
                    }
                    try requirePostingWrite(store.rewrite(openItemsPath, key: key, data: item.bytes), path: openItemsPath)
                    payment = item
                    applied = Cobol.truncate(applied + value, digits: 9)
                }
                let number = 1_000 * nextBatch + series
                payment["oi-supplier"] = supplier
                payment.setInt("oi-invoice", number)
                payment.setInt("oi-b-nos", nextBatch)
                payment.setInt("oi-b-item", series)
                payment.setInt("oi-date", date)
                payment.setInt("oi-date-cleared", date)
                payment.setInt("oi-type", 5)
                payment.setInt("oi-approp", applied)
                payment.setInt("oi-paid", record.int("gross"))
                payment.setInt("oi-deduct-amt", discount)
                payment["oi-ref"] = Cobol.z(record.int("cheque"), 10)
                for field in ["oi-carriage", "oi-c-vat", "oi-vat", "oi-discount", "oi-status", "oi-p-c",
                              "oi-extra", "oi-e-vat", "oi-cr", "oi-deduct-days", "oi-days", "oi-deduct-vat"] {
                    payment.setInt(field, 0)
                }
                for field in ["oi-order", "oi-hold-flag", "oi-applied"] { payment[field] = "" }
                let key = openItemKey(supplier: supplier, number: number)
                try requirePostingWrite(store.write(openItemsPath, key: key, data: payment.bytes), path: openItemsPath)
                if discount != 0 { count += 1 }
                deductions = Cobol.truncate(deductions + discount, digits: 9)

                if gl {
                    let amount = payment.int("oi-paid")
                    let itemNumber = batch.int("items") + 1
                    batch.setInt("items", itemNumber)
                    for field in ["input-gross", "actual-gross"] {
                        batch.setInt(field, Cobol.truncate(batch.int(field) + amount, digits: 11, signed: false))
                    }
                    var entry = Record(PurchaseRecords.postLayout)
                    entry.setInt("batch", batch.int("batch-nos"))
                    entry.setInt("post-number", itemNumber)
                    entry["post-code"] = "PL"
                    let ukDate = Maps04.toDate(Int(date))
                    entry["post-date"] = String(ukDate.prefix(6)) + String(ukDate.suffix(2))
                    entry.setInt("post-dr", configuration.int("p-creditors"))
                    entry.setInt("post-cr", configuration.int("bl-pay-ac"))
                    entry.setInt("post-amount", amount)
                    entry["post-legend"] = String(number) + " : " + (supplierRecord(supplier)?.str("purch-name") ?? "Record Missing")
                    entry["post-vat-side"] = "DR"
                    try writePaymentEntry(entry, rrn: rrn, irs: irs)
                    if !irs { rrn += 1 }
                    if itemNumber == 99 {
                        try saveBatch()
                        if !irs { rrn += 1 }
                        startBatch()
                    }
                }
            }
            if gl {
                try saveBatch()
                if !irs { configuration.setInt("postings", Int64(rrn)) }
            }
            configuration.setInt("bl-next-batch", nextBatch + 1)
            try recordPaymentDeductions(count: count, amount: deductions)
            try clearSchedule()
            try systemFile.write(1, configuration.bytes)
        }
    }

    private func writeChequeRegister(_ records: [Record]) throws {
        guard let first = records.first else { return }
        let printer = PurchasePrinter(self)
        let company = Cobol.x(system.str("usera"), 70) + reportDate(system.int("run-date"))
        let date = reportDate(first.int("date"))
        var total: Int64 = 0
        var page: Int64 = 0
        var lines = 0
        func headings() {
            page += 1
            let title = Cobol.x("PL950 (3.01.09)", 33) + Cobol.x("Cheque/Bacs Register", 39)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            if page == 1 {
                printer.writeBefore(title, before: 1)
                printer.writeBefore(company, before: 1)
            } else {
                printer.writePage(title)
                printer.write(company, after: 1)
                printer.write("", after: 1)
            }
            printer.write(Cobol.x("Cheques Date - ", 16) + date, after: 1)
            printer.write("Cheque Nos     <------------ Payee ------------->      <--Value-->", after: 2)
            printer.write(Cobol.x(" Sort  Account", 16) + "Account             Name", after: 1)
            printer.write("", after: 1)
            lines = 8
        }
        headings()
        for record in records {
            let number = record.int("cheque")
            let details = number != 0
                ? Pic.edit("z(9)9", value: number, scale: 0) + Cobol.x("", 6)
                : Cobol.z(record.int("sort-code"), 6) + " " + Cobol.z(record.int("account"), 8) + " "
            let supplier = record.str("supplier")
            let name = supplierRecord(supplier)?.str("purch-name") ?? "Record Missing"
            let amount = record.int("gross")
            printer.write(details + Cobol.x(supplier, 9) + Cobol.x(name, 30)
                          + Pic.edit("z(7)9.99", value: amount, scale: 2), after: 1)
            total = Cobol.truncate(total + amount, digits: 9, signed: false)
            lines += 1
            if lines > Int(system.int("page-lines")) { headings() }
        }
        let rule = Cobol.x("", 55) + "==========="
        printer.write(rule, after: 2)
        printer.write(Cobol.x("", 25) + Cobol.x("    total", 30) + Pic.edit("z(7)9.99", value: total, scale: 2), after: 1)
        printer.write(rule, after: 1)
        try printer.close()
    }
}
