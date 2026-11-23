import Foundation

extension PurchaseLedger {
    public enum PeriodCloseError: Swift.Error {
        case uninitialized, unpostedPayments, analysisRequired, unpostedInvoices, incorrectPassword
    }

    public struct PeriodCloseStatus {
        public let date: Date
        public let asksForQuarterEnd: Bool
        public let warnsAboutInvoices: Bool
        public let requiresPassword: Bool
        public let needsPurchaseAnalysis: Bool
        public let needsSalesAnalysis: Bool
    }

    public var periodCloseStatus: PeriodCloseStatus {
        let settings = system
        return PeriodCloseStatus(
            date: processingDate, asksForQuarterEnd: ![3, 13].contains(settings.int("period")),
            warnsAboutInvoices: hasInvoiceWarning(settings),
            requiresPassword: settings.str("pass-word") != "    ",
            needsPurchaseAnalysis: settings.int("p-flag-a") == 1,
            needsSalesAnalysis: settings.int("s-flag-a") == 1
        )
    }

    private func hasInvoiceWarning(_ settings: Record) -> Bool {
        settings.int("p-flag-i") == 1 || settings.int("s-flag-i") == 1
    }

    public func closePeriod(confirmUnpostedInvoices: Bool, password: String, endQuarter: Bool) throws {
        try store.withTransaction {
            var settings = system
            let files = settings.raw("file-statuses")
            guard files[14] == 0x31 else { throw PeriodCloseError.uninitialized }
            guard !hasInvoiceWarning(settings) || confirmUnpostedInvoices else { throw PeriodCloseError.unpostedInvoices }
            guard ![1, 2].contains(settings.int("p-flag-p")), ![1, 2].contains(settings.int("s-flag-p")) else {
                throw PeriodCloseError.unpostedPayments
            }
            guard settings.int("p-flag-a") != 1, settings.int("s-flag-a") != 1 else {
                throw PeriodCloseError.analysisRequired
            }
            guard settings.raw("pass-word") == encodeClosingPassword(password) else { throw PeriodCloseError.incorrectPassword }
            guard files[28] == 0x31 else { throw PeriodCloseError.uninitialized }

            var cycle = settings.int("scycle") + 1
            var quarter = settings.int("current-quarter")
            let newQuarter: Bool
            let newYear: Bool
            switch settings.int("period") {
            case 3:
                newYear = cycle == 13
                newQuarter = newYear || [4, 7, 10].contains(cycle)
            case 13:
                newYear = cycle == 53
                newQuarter = newYear || [14, 27, 40].contains(cycle)
            default:
                newQuarter = endQuarter
                newYear = newQuarter && quarter == 4
            }
            if newYear {
                cycle = 1
                quarter = 1
            } else if newQuarter {
                quarter += 1
            }

            try archiveClosingDayBook()
            try carrySupplierBalances(newQuarter: newQuarter ? quarter : nil, newYear: newYear)
            try carryOpenItems()
            try carryAnalysisValues(newYear: newYear)
            try compactPostedInvoices()
            try carryMonthlyTotals()
            settings.setInt("scycle", cycle)
            settings.setInt("current-quarter", quarter)
            settings.setInt("bl-end-cycle-date", try legacyDate(processingDate))
            settings["oi-5-flag"] = "Y"
            try systemFile.write(1, settings.bytes)
        }
    }

    private func encodeClosingPassword(_ password: String) -> [UInt8] {
        let upper = Array("CKQUAELSMWYIZJRPBXFVGNODTH".utf8)
        let lower = Array("ckquaelsmwyizjrpbxfvgnodth".utf8)
        var output = Array(repeating: UInt8(0x20), count: 4)
        for (index, byte) in SJIS.encode(password, size: 4).enumerated() {
            guard let matching = upper.firstIndex(of: byte) ?? lower.firstIndex(of: byte) else { continue }
            let position = index + 1
            let value = abs(matching + 1 + position * position + 3 - 26)
            if value != 0 { output[3 - index] = upper[value - 1] }
        }
        return output
    }

    private func carrySupplierBalances(newQuarter: Int64?, newYear: Bool) throws {
        for entry in store.all(suppliersPath) where entry.data.count == PurchaseRecords.purchLayout.size {
            var supplier = Record(PurchaseRecords.purchLayout, bytes: entry.data)
            let current = supplier.int("purch-current")
            let unapplied = supplier.int("purch-unapplied")
            if current == 0 && unapplied == 0 && supplier.int("purch-last") == 0 {
                supplier.setInt("purch-status", 0)
            }
            if current < 0 {
                supplier.setInt("purch-unapplied", Cobol.truncate(unapplied - current, digits: 10))
                supplier.setInt("purch-current", 0)
            }
            supplier.setInt("purch-last", max(0, current))
            if let newQuarter, (1...4).contains(newQuarter) { supplier.setInt("turnover-q\(newQuarter)", 0) }
            if newYear {
                supplier.setInt("purch-average", 0)
                supplier.setInt("purch-activety", 0)
            }
            try requirePostingWrite(store.rewrite(suppliersPath, key: entry.key, data: supplier.bytes), path: suppliersPath)
        }
    }

    private func carryOpenItems() throws {
        for entry in store.all(openItemsPath) where entry.data.count == PurchaseRecords.oiLayout.size {
            var item = Record(PurchaseRecords.oiLayout, bytes: entry.data)
            let type = item.int("oi-type")
            let closed = item.int("oi-status") == 1
            if closed || type == 1 {
                if closed && type == 2 {
                    let folio = item.int("oi-invoice")
                    if let header = header(folio) {
                        for line in 0...Int(max(0, header.int("ih-lines"))) { try deleteInvoiceRecord(folio, line: line) }
                    } else {
                        for line in 1...127 {
                            let key = invoiceKey(folio, line)
                            guard store.read(invoicePath, key: key) != nil else { break }
                            try requirePostingWrite(store.delete(invoicePath, key: key), path: invoicePath)
                        }
                    }
                }
                try requirePostingWrite(store.delete(openItemsPath, key: entry.key), path: openItemsPath)
                continue
            }
            if type == 5 || type == 6 { item.setInt("oi-deduct-amt", 0) }
            item["oi-applied"] = "z"
            item.setInt("oi-p-c", 0)
            try requirePostingWrite(store.rewrite(openItemsPath, key: entry.key, data: item.bytes), path: openItemsPath)
        }
    }

    private func deleteInvoiceRecord(_ folio: Int64, line: Int) throws {
        let key = invoiceKey(folio, line)
        if store.read(invoicePath, key: key) != nil {
            try requirePostingWrite(store.delete(invoicePath, key: key), path: invoicePath)
        }
    }

    private func carryAnalysisValues(newYear: Bool) throws {
        let path = base + "value.dat"
        if newYear && !store.exists(path) {
            store.createIndexed(path)
            try requirePostingWrite(store.kind(path) == "indexed", path: path)
        }
        for entry in store.all(path) {
            if newYear {
                try requirePostingWrite(store.delete(path, key: entry.key), path: path)
            } else if entry.data.first == 0x50, entry.data.count == PurchaseRecords.valueLayout.size {
                var value = Record(PurchaseRecords.valueLayout, bytes: entry.data)
                value.setRaw("last-count", value.raw("this-count"))
                value.setRaw("last-net", value.raw("this-net"))
                value.setInt("this-count", 0)
                value.setInt("this-net", 0)
                try requirePostingWrite(store.rewrite(path, key: entry.key, data: value.bytes), path: path)
            }
        }
    }

    private func compactPostedInvoices() throws {
        for var header in headers() where ["z", "Z"].contains(header.str("ih-status")) {
            let folio = header.int("ih-invoice")
            let type = header.int("ih-type")
            if [1, 2, 3].contains(type), header.int("ih-lines") > 0 {
                for line in 1...Int(header.int("ih-lines")) { try deleteInvoiceRecord(folio, line: line) }
            }
            if type == 1 || type == 3 {
                try deleteInvoiceRecord(folio, line: 0)
                continue
            }
            if type < 4 { header["ih-day-book-flag"] = "B" }
            if type == 2 { header.setInt("ih-lines", 0) }
            try requirePostingWrite(store.rewrite(invoicePath, key: invoiceKey(folio), data: header.bytes), path: invoicePath)
        }
    }

    private func carryMonthlyTotals() throws {
        var bytes = systemFile.read(4) ?? SystemAuxRecords.initialRecord4()
        var totals = Record(PurchaseRecords.sys4Layout, bytes: bytes)
        totals.setRaw("pl-os-bal-last-month", totals.raw("pl-os-bal-this-month"))
        for field in ["pl-os-bal-this-month", "pl-variance", "pl-invoices-this-month", "pl-payments",
                      "pl-credit-deductions", "pl-cn-unappl-this-month", "pl-credit-notes-this-month"] {
            totals.setInt(field, 0)
        }
        bytes.replaceSubrange(0..<PurchaseRecords.sys4Layout.size, with: totals.bytes.prefix(PurchaseRecords.sys4Layout.size))
        try systemFile.write(4, bytes)
    }
}
