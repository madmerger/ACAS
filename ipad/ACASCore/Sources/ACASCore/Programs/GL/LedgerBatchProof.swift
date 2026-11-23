public struct LedgerBatchProof {
    public enum Error: Swift.Error { case missingBatch, invalidPostings, storage }

    public struct Report: Identifiable {
        public let id: Int
        public let verified: Bool
        public let bytes: [UInt8]
    }

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generate(batch number: Int? = nil) throws -> [Report] {
        try context.store.transaction {
            let settings = CompanySetup(context).settings
            let batches = IndexedFile(context.store, path: LedgerBatches.batchPath,
                                      layout: LedgerBatches.batchLayout, keyLength: 6)
            let selected: [Record]
            if let number {
                guard (1...99998).contains(number), let batch = batches.read(key: "1" + Cobol.z(number, 5)) else {
                    throw Error.missingBatch
                }
                selected = [batch]
            } else {
                selected = batches.allRecords().filter {
                    $0.int("ledger") == 1 && $0.int("cycle") == settings.number("scycle") && $0.int("cleared") == 0
                }
            }
            guard !selected.isEmpty else { return [] }
            let postings = try readPostings()
            let chart = ChartOfAccounts(context)
            return try selected.map { original in
                var batch = original
                let id = batch.int("number")
                let lines = postings[id] ?? []
                let accounts = lines.map { line in
                    ["debit", "credit"].map { side in
                        chart.account(code: line.str(side), branch: line.str(side + "-branch")) != nil
                    }
                }
                let net = lines.reduce(Int64(0)) { $0 + $1.int("amount") }
                let tax = lines.reduce(Int64(0)) { $0 + $1.int("vat-amount") }
                let valid = !lines.isEmpty && accounts.allSatisfy { $0.allSatisfy { $0 } }
                let verified = valid && net + tax == batch.int("input-gross") && tax == batch.int("input-vat")
                batch.setInt("actual-gross", net + (valid ? tax : 0))
                batch.setInt("actual-vat", tax)
                batch.setInt("status", verified ? 1 : 0)
                if number != nil { batch.setInt("proofed", batch.int("entered")) }
                let bytes = render(batch, lines: lines, accounts: accounts, settings: settings,
                                   net: net, tax: tax, valid: valid, verified: verified)
                guard batches.rewrite(batch) == "00" else { throw Error.storage }
                try context.store.writeRaw(CompanySetup.reportPath, bytes)
                return Report(id: Int(id), verified: verified, bytes: bytes)
            }
        }
    }

    private func readPostings() throws -> [Int64: [Record]] {
        let layout = LedgerBatches.postingLayout
        let slot = layout.size + 8
        guard let bytes = context.store.readRaw(LedgerBatches.postingPath), bytes.count.isMultiple(of: slot) else {
            throw Error.invalidPostings
        }
        var records: [Int64: [Record]] = [:]
        for offset in stride(from: 0, to: bytes.count, by: slot) {
            let length = bytes[offset..<(offset + 8)].enumerated().reduce(UInt64(0)) {
                $0 | (UInt64($1.element) << (8 * $1.offset))
            }
            if length == 0 { continue }
            guard length == layout.size else { throw Error.invalidPostings }
            let line = Record(layout, bytes: Array(bytes[(offset + 8)..<(offset + slot)]))
            if line.int("batch") != 0 { records[line.int("batch"), default: []].append(line) }
        }
        return records
    }

    private func render(_ batch: Record, lines: [Record], accounts: [[Bool]], settings: CompanySettings,
                        net: Int64, tax: Int64, valid: Bool, verified: Bool) -> [UInt8] {
        var bytes: [UInt8] = []
        var page: Int64 = 0
        var count = 0
        let pageLines = settings.number("page-lines")
        func date(_ value: Int64) -> String {
            value == 0 ? "" : Maps04.format(Maps04.toDate(Int(value)), dateForm: Int(settings.number("date-form")))
        }
        func write(_ text: String, after: Int = 1) {
            bytes += [UInt8](repeating: 10, count: after) + SJIS.encode(text, size: 132)
        }
        func pic(_ form: String, _ value: Int64, scale: Int = 0) -> String {
            Pic.edit(form, value: value, scale: scale)
        }
        func headings() {
            page += 1
            write(Cobol.x("gl051 (3.00.04)", 14) + Cobol.x("", 41) + "Transaction Proof Report"
                  + Cobol.x("", 45) + "Page  " + pic("z9", page))
            bytes += [10] + SJIS.encode(settings.text("usera"), size: 32)
                + SJIS.encode(Cobol.x("", 90) + date(settings.number("run-date")), size: 100)
            bytes += [10, 10] + SJIS.encode("Batch - " + pic("z(4)9", batch.int("number")) + Cobol.x("", 8), size: 21)
                + batch.raw("description")
                + SJIS.encode(Cobol.x("    Date Entered - ", 20) + date(batch.int("entered")), size: 87)
            write(Cobol.x("Number  Code  ---Date--- --Debit--   --Credit-    Net Amount    VAT Amount  VAT Account  VAT Side   ----------", 110)
                  + "--Narative------------", after: 2)
            write("------  ----              A/C  P/C    A/C  P/C    ----------    ----------    A/C  P/C   --------")
            write("")
            count = 8
        }
        headings()
        for (line, present) in zip(lines, accounts) {
            let vatAccount = line.int("vat-account"), vatBranch = line.int("vat-branch")
            let leading = pic("z(4)9b(4)", line.int("sequence")) + Cobol.x(line.str("code"), 5)
                + Cobol.x(line.str("date"), 12)
                + pic("zzz9.99b", line.int("debit"), scale: 2) + pic("99bb", line.int("debit-branch"))
                + pic("zzz9.99b", line.int("credit"), scale: 2) + pic("99bb", line.int("credit-branch"))
            let amounts = pic("z(8)9.99bb", line.int("amount"), scale: 2)
                + pic("z(8)9.99bb", line.int("vat-amount"), scale: 2)
                + (vatAccount == 0 ? Cobol.x("", 7) : pic("zzz9.99", vatAccount, scale: 2))
                + (vatBranch == 0 ? Cobol.x("", 9) : pic("bz9bbbbbb", vatBranch))
                + Cobol.x(vatAccount == 0 ? "" : line.str("vat-side"), 8)
            let detail = SJIS.encode(leading + amounts, size: 102) + line.raw("memo")
            bytes += [10] + detail.prefix(132)
            count += 1
            if present.contains(false) {
                write(Cobol.x("", 24) + present.map { Cobol.x($0 ? "" : "^^^^^^^^^^", 12) }.joined())
                count += 1
            }
            if count > pageLines - 6 { headings() }
        }
        if valid {
            if count > pageLines - 12 { headings() }
            let padding = Cobol.x("", 20)
            write(padding + "Batch              ----Net----    ----VAT----", after: 3)
            for (label, amount, vat) in [("Header", batch.int("input-gross") - batch.int("input-vat"), batch.int("input-vat")),
                                         ("Actual", net, tax)] {
                write(padding + Cobol.x(label, 17) + pic("z(9)9.99bb", amount, scale: 2)
                      + pic("z(9)9.99bb", vat, scale: 2), after: 2)
            }
            write(padding + "*********************", after: 3)
            write(padding + (verified ? "* Batch Verified Ok *" : "*  Batch In ERROR   *"))
            write(padding + "*********************")
        }
        return bytes + [10]
    }
}
