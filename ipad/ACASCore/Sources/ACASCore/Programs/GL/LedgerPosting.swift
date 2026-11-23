import Foundation

public struct LedgerPosting {
    public enum Error: Swift.Error, Equatable {
        case openBatches, invalidPostings, missingAccount(String), storage
    }

    public struct Result: Equatable {
        public let batches: Int
        public let entries: Int
    }

    private struct Entry {
        let code: Int64
        let branch: Int64
        let sequence: Int64
        let date: String
        let amount: Int64
        let memo: String

        var key: String { Cobol.z(code, 6) + Cobol.z(branch, 2) }
    }

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func postCurrentCycle() throws -> Result {
        try context.store.transaction {
            let setup = CompanySetup(context).settings
            let batchFile = IndexedFile(context.store, path: LedgerBatches.batchPath,
                                        layout: LedgerBatches.batchLayout, keyLength: 6)
            let current = batchFile.allRecords().filter { $0.int("cycle") == setup.number("scycle") }
            guard !current.contains(where: { $0.int("ledger") != 9 && $0.int("status") == 0 }) else {
                throw Error.openBatches
            }
            let waiting = current.filter { $0.int("ledger") == 1 && $0.int("cleared") == 0 }
            guard !waiting.isEmpty else { return Result(batches: 0, entries: 0) }

            let selected = Set(waiting.map { $0.int("number") })
            let ledger = IndexedFile(context.store, path: ChartOfAccounts.path, layout: ChartOfAccounts.layout, keyLength: 8)
            let report = PostingReport(setup: setup)
            let entries = try readEntries(selected)
            var count = 0
            for var batch in waiting {
                guard let lines = entries[batch.int("number")], !lines.isEmpty else { throw Error.invalidPostings }
                report.begin(batch)
                var account: Record?
                var key = ""
                func closeAccount() throws {
                    guard let account else { return }
                    report.finishAccount(account)
                    guard ledger.rewrite(account) == "00" else { throw Error.storage }
                }

                for entry in lines.sorted(by: {
                    ($0.key, $0.sequence) < ($1.key, $1.sequence)
                }) {
                    if key != entry.key {
                        try closeAccount()
                        key = entry.key
                        account = ledger.read(key: key)
                        guard let account else { throw Error.missingAccount(key) }
                        report.startAccount(account)
                    }
                    guard var currentAccount = account else { throw Error.missingAccount(key) }
                    currentAccount.setInt("balance",
                        Cobol.truncate(currentAccount.int("balance") + entry.amount, digits: 10))
                    account = currentAccount
                    report.detail(entry)
                    if report.pageIsFull {
                        try closeAccount()
                        report.begin(batch)
                        report.startAccount(currentAccount, continued: true)
                    }
                    count += 1
                }
                try closeAccount()
                batch.setInt("cleared", 1)
                batch.setInt("posted", setup.number("run-date"))
                guard batchFile.rewrite(batch) == "00" else { throw Error.storage }
            }
            try context.store.writeRaw(CompanySetup.reportPath, report.output + [10])
            return Result(batches: waiting.count, entries: count)
        }
    }

    private func readEntries(_ selected: Set<Int64>) throws -> [Int64: [Entry]] {
        let layout = LedgerBatches.postingLayout
        let file = RelativeFile(context.store, path: LedgerBatches.postingPath, recordSize: layout.size)
        guard let data = context.store.readRaw(file.path), data.count.isMultiple(of: layout.size + 8) else {
            throw Error.invalidPostings
        }
        var entries: [Int64: [Entry]] = [:]
        for offset in stride(from: 0, to: data.count, by: layout.size + 8) {
            let length = data[offset..<(offset + 8)].enumerated().reduce(UInt64(0)) {
                $0 | (UInt64($1.element) << (8 * $1.offset))
            }
            if length == 0 { continue }
            guard length == layout.size else { throw Error.invalidPostings }
            let posting = Record(layout, bytes: Array(data[(offset + 8)..<(offset + 8 + layout.size)]))
            let batch = posting.int("batch")
            guard selected.contains(batch), posting.int("sequence") > 0 else { continue }
            let amount = posting.int("amount"), vat = posting.int("vat-amount"), side = posting.str("vat-side")
            let combined = Cobol.truncate(amount + vat, digits: 10)
            func add(_ code: String, _ branch: String, amount: Int64) {
                entries[batch, default: []].append(Entry(code: posting.int(code), branch: posting.int(branch),
                    sequence: posting.int("sequence"), date: posting.str("date"), amount: amount,
                    memo: Cobol.rtrim(posting.str("memo"))))
            }
            add("debit", "debit-branch", amount: side == "CR" ? combined : amount)
            add("credit", "credit-branch", amount: -(side == "DR" ? combined : amount))
            if posting.int("vat-account") != 0 && vat != 0 {
                add("vat-account", "vat-branch", amount: side == "CR" ? -vat : vat)
            }
        }
        return entries
    }

    private final class PostingReport {
        let setup: CompanySettings
        let rawDate: String
        let date: String
        var output: [UInt8] = []
        private var page = 0
        private var lines = 0
        private var debitTotal: Int64 = 0
        private var creditTotal: Int64 = 0
        private var code: Int64 = 0
        private var branch: Int64 = 0
        private let rule = Cobol.x("", 54) + "===========    ==========="

        init(setup: CompanySettings) {
            self.setup = setup
            rawDate = Maps04.toDate(Int(setup.number("run-date")))
            date = Maps04.format(rawDate, dateForm: Int(setup.number("date-form")))
        }

        var pageIsFull: Bool { lines > setup.number("page-lines") }

        func begin(_ batch: Record) {
            page += 1
            line(Cobol.x("gl072 (3.00.04)", 50) + Cobol.x("Transaction  Posting", 63) + "Page "
                + Pic.edit("z9", value: Int64(page % 100), scale: 0), advance: page == 1 ? [] : [12])
            let prefix = "Cycle - " + Pic.edit("z9", value: setup.number("scycle"), scale: 0) + "          Batch - "
                + Pic.edit("zzzz9", value: batch.int("number"), scale: 0) + Cobol.x("", 10) + Cobol.x("General", 12)
            output += [10] + SJIS.encode(prefix, size: 55) + SJIS.encode(Cobol.rtrim(batch.str("description")), size: 32)
                + SJIS.encode(Cobol.x("", 23) + date, size: 45)
            if page != 1 { line("") }
            line("Account   Br/P C    --Balance--   Trans  --Date--    ---Debit---    ---Credit--       -------------Legend------------",
                 advance: page == 1 ? [10, 10] : [10])
            line(Cobol.x("-------", 34) + "-----")
            lines = 5
        }

        func startAccount(_ account: Record, continued: Bool = false) {
            code = account.int("code")
            branch = account.int("branch")
            let balance = account.int("balance")
            let debit = continued ? 0 : max(0, balance)
            let credit = continued ? 0 : max(0, -balance)
            if !continued { debitTotal = debit; creditTotal = credit }
            row(balance: balance, date: date, debit: debit, credit: credit, memo: "brought forward", advance: [10, 10])
        }

        func detail(_ entry: Entry) {
            let debit = max(0, entry.amount), credit = max(0, -entry.amount)
            debitTotal = (debitTotal + debit) % 10_000_000_000
            creditTotal = (creditTotal + credit) % 10_000_000_000
            row(sequence: entry.sequence, date: entry.date, debit: debit, credit: credit, memo: entry.memo)
        }

        func finishAccount(_ account: Record) {
            line(rule)
            row(balance: account.int("balance"), date: rawDate, debit: debitTotal, credit: creditTotal,
                memo: Cobol.rtrim(account.str("name")))
            line(rule)
            line("")
        }

        private func line(_ text: String, advance: [UInt8] = [10]) {
            output += advance + SJIS.encode(text, size: 132)
            lines += advance.count
        }

        private func row(balance: Int64 = 0, sequence: Int64 = 0, date: String, debit: Int64, credit: Int64,
                         memo: String, advance: [UInt8] = [10]) {
            func picture(_ format: String, _ value: Int64, scale: Int = 2) -> String {
                value == 0 ? Cobol.x("", Pic.size(format)) : Pic.edit(format, value: value, scale: scale)
            }
            let fields = picture("9999.99", code) + Cobol.x("", 6) + picture("99", branch, scale: 0)
                + Cobol.x("", 5) + picture("zzzzzzz9.99cr", balance) + picture("bbbz9", sequence, scale: 0)
                + Cobol.x("", 4) + Cobol.x(date, 12) + picture("zzzzzzz9.99", debit) + Cobol.x("", 4)
                + picture("zzzzzzz9.99", credit) + Cobol.x("", 6)
            output += advance + SJIS.encode(fields, size: 86) + SJIS.encode(memo, size: 32) + SJIS.encode("", size: 14)
            lines += advance.count
        }
    }
}
