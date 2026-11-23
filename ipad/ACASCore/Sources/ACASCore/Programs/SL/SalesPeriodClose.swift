public struct SalesPeriodClose {
    public enum Error: Swift.Error {
        case missingAnalysis, pendingPayments, analysisReportRequired, invalidPassword, missingOpenItems, pendingInvoices, writeFailed
    }

    public struct Options {
        public let warnedInvoices: Bool
        public let manualQuarter: Bool
    }

    private let context: BusinessContext
    private var store: FileStore { context.store }

    public init(_ context: BusinessContext) { self.context = context }

    public func options() throws -> Options {
        try options(SalesInvoices(context).settings())
    }

    public func close(password: String, acceptingPendingInvoices: Bool, endQuarter: Bool) throws {
        let files = SalesInvoices(context)
        try store.withTransaction {
            var system = try files.settings()
            let options = try options(system)
            guard !options.warnedInvoices || acceptingPendingInvoices else { throw Error.pendingInvoices }
            guard system.raw("pass-word") == encodedPassword(password) else { throw Error.invalidPassword }
            let day = system.int("run-date")
            var cycle = system.int("scycle") + 1
            var quarter = system.int("current-quarter")
            let period = system.int("period")
            let newYear: Bool
            let newQuarter: Bool
            switch period {
            case 3:
                newYear = cycle == 13
                newQuarter = newYear || [4, 7, 10].contains(cycle)
            case 13:
                newYear = cycle == 53
                newQuarter = newYear || [14, 27, 40].contains(cycle)
            default:
                newQuarter = endQuarter
                newYear = endQuarter && quarter == 4
            }
            if newYear {
                quarter = 1
                cycle = 1
            } else if newQuarter {
                quarter += 1
            }
            try closeCustomers(quarter: newQuarter ? quarter : nil, newYear: newYear)
            try closeOpenItems(invoices: files, ownNumbers: system.str("sl-own-nos") == "Y")
            try closeAnalysis(newYear: newYear)
            try compactInvoices(files, system: system)
            var monthly = Record(SalesPostingRecords.monthly, bytes: files.systemFile.read(4) ?? SystemAuxRecords.initialRecord4())
            monthly.setInt("old-balance", monthly.int("balance"))
            for field in ["balance", "invoices", "credit-notes", "variance", "credit-deductions", "unapplied-credits", "payments"] {
                monthly.setInt(field, 0)
            }
            system.setInt("scycle", cycle)
            system.setInt("current-quarter", quarter)
            system.setInt("s-end-cycle-date", day)
            system["oi-3-flag"] = "Y"
            try files.systemFile.write(4, monthly.bytes)
            try files.systemFile.write(1, system.bytes)
        }
    }

    private func options(_ system: Record) throws -> Options {
        let flags = system.raw("file-statuses")
        guard flags[14] == 0x31 else { throw Error.missingAnalysis }
        guard ![1, 2].contains(system.int("s-flag-p")), ![1, 2].contains(system.int("p-flag-p")) else { throw Error.pendingPayments }
        guard system.int("s-flag-a") != 1, system.int("p-flag-a") != 1 else { throw Error.analysisReportRequired }
        guard flags[18] == 0x31, store.exists(SalesOpenItems.path) else { throw Error.missingOpenItems }
        return Options(warnedInvoices: system.int("s-flag-i") == 1 || system.int("p-flag-i") == 1,
                       manualQuarter: ![3, 13].contains(system.int("period")))
    }

    private func closeCustomers(quarter: Int64?, newYear: Bool) throws {
        let file = SalesProofRecords.salesFile(store)
        for var row in file.allRecords() {
            let current = row.int("sales-current")
            let unapplied = row.int("sales-unapplied")
            if current == 0, row.int("sales-last") == 0, unapplied == 0 { row.setInt("sales-status", 0) }
            if current < 0 {
                row.setInt("sales-unapplied", unapplied - current)
                row.setInt("sales-current", 0)
            }
            row.setInt("sales-last", row.int("sales-current"))
            if let quarter, (1...4).contains(quarter) { row.setInt("turnover-q\(quarter)", 0) }
            if newYear {
                row.setInt("sales-average", 0)
                row.setInt("sales-activety", 0)
            }
            guard file.rewrite(row) == "00" else { throw Error.writeFailed }
        }
    }

    private func closeOpenItems(invoices: SalesInvoices, ownNumbers: Bool) throws {
        let file = SalesOpenItems.file(store)
        for var row in file.allRecords() {
            let type = row.int("type")
            if row.int("status") == 1 || type == 1 {
                if row.int("status") == 1, type == 2, !ownNumbers {
                    let number = SalesInvoices.Number(value: row.int("invoice"))
                    if let header = invoices.header(number) {
                        try remove(invoices, key: invoices.key(number))
                        for line in 0..<max(0, Int(header.int("ih-lines"))) {
                            let key = invoices.key(number, line: line + 1)
                            if store.read(invoices.file.path, key: key) != nil { try remove(invoices, key: key) }
                        }
                    } else {
                        for line in 1...255 {
                            let key = invoices.key(number, line: line)
                            guard store.read(invoices.file.path, key: key) != nil else { break }
                            try remove(invoices, key: key)
                        }
                    }
                }
                guard file.delete(key: file.key(of: row)) == "00" else { throw Error.writeFailed }
                continue
            }
            if type == 5 || type == 6 { row.setInt("deduction", 0) }
            row["applied"] = "z"
            row.setInt("paid-current", 0)
            guard file.rewrite(row) == "00" else { throw Error.writeFailed }
        }
    }

    private func closeAnalysis(newYear: Bool) throws {
        let path = SalesPosting.valuePath
        for row in store.all(path) {
            if newYear {
                guard store.delete(path, key: row.key) else { throw Error.writeFailed }
            } else if row.key.first == 0x53 {
                var value = Record(SalesPostingRecords.value, bytes: row.data)
                for field in ["count", "value"] {
                    value.setInt(field + "-last", value.int(field + "-this"))
                    value.setInt(field + "-this", 0)
                }
                guard store.rewrite(path, key: row.key, data: value.bytes) else { throw Error.writeFailed }
            }
        }
    }

    private func compactInvoices(_ invoices: SalesInvoices, system: Record) throws {
        let rows = store.all(invoices.file.path)
        let day = system.int("run-date")
        var skipCount = 0
        for row in rows {
            if skipCount > 0 {
                try remove(invoices, key: row.key)
                skipCount -= 1
                continue
            }
            let stored = Array(row.data.prefix(129))
            var bytes = stored + Array(repeating: UInt8(0x20), count: SalesInvoices.recordSize - stored.count)
            if row.key.last == 0 {
                var header = Record(SalesProofRecords.ihLayout, bytes: bytes)
                let type = header.int("ih-type")
                let applied = ["z", "Z"].contains(header.str("ih-status"))
                let lines = max(0, Int(header.int("ih-lines")))
                let expiredProForma = type == 4 && day - system.int("pf-retention") > header.int("ih-date")
                if expiredProForma || (applied && (type == 1 || type == 3)) {
                    try remove(invoices, key: row.key)
                    skipCount = lines
                    continue
                }
                if applied, type < 4 { header["ih-day-book-flag"] = "B" }
                if applied, type == 2, lines > 0 {
                    skipCount = lines
                    header.setInt("ih-lines", 0)
                } else if applied, type == 2, system.str("sl-own-nos") == "Y", day - 92 > header.int("ih-date") {
                    try remove(invoices, key: row.key)
                    continue
                }
                bytes = header.bytes
            }
            let result = Array(bytes.prefix(129)) + Array(repeating: UInt8(0x20), count: SalesInvoices.recordSize - 129)
            guard store.rewrite(invoices.file.path, key: row.key, data: result) else { throw Error.writeFailed }
        }
    }

    private func remove(_ invoices: SalesInvoices, key: [UInt8]) throws {
        guard store.delete(invoices.file.path, key: key) else { throw Error.writeFailed }
    }

    private func encodedPassword(_ input: String) -> [UInt8] {
        let alphabet = Array("CKQUAELSMWYIZJRPBXFVGNODTH".utf8)
        let lower = Array("ckquaelsmwyizjrpbxfvgnodth".utf8)
        var output = Array(repeating: UInt8(0x20), count: 4)
        for (index, char) in SJIS.encode(input, size: 4).enumerated() {
            guard let position = alphabet.firstIndex(of: char) ?? lower.firstIndex(of: char) else { continue }
            let y = index + 1
            let z = abs(position + 1 + y * y + 3 - 26)
            if (1...alphabet.count).contains(z) { output[3 - index] = alphabet[z - 1] }
        }
        return output
    }
}
