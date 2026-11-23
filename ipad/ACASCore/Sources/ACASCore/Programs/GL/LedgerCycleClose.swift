public struct LedgerCycleClose {
    public enum Error: Swift.Error, Equatable {
        case missingCompany, unfinishedBatches, invalidCycle, invalidPostings, storage
    }

    private static let systemPath = "ledgers/acas/system.dat"
    static let archivePath = "archives/archive.dat"
    static let archiveLayout = Layout("archive-transaction", [
        ("batch", .n9(digits: 5, scale: 0, signed: false)),
        ("sequence", .n9(digits: 5, scale: 0, signed: false)),
        ("code", .x(2)), ("date", .x(8)),
        ("account", .n9(digits: 6, scale: 0, signed: false)),
        ("branch", .n9(digits: 2, scale: 0, signed: false)),
        ("amount", .n9(digits: 10, scale: 2, signed: true)),
        ("memo", .x(32)),
        ("counter-account", .n9(digits: 6, scale: 0, signed: false)),
        ("counter-branch", .n9(digits: 2, scale: 0, signed: false)),
    ])

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func close() throws {
        try context.store.transaction {
            let system = RelativeFile(context.store, path: Self.systemPath, recordSize: SystemLayout.layout.size)
            guard let bytes = system.read(1) else { throw Error.missingCompany }
            var settings = Record(SystemLayout.layout, bytes: bytes)
            let cycle = settings.int("scycle"), period = settings.int("period")
            guard cycle > 0, period > 0 else { throw Error.invalidCycle }

            let batches = IndexedFile(context.store, path: LedgerBatches.batchPath,
                                      layout: LedgerBatches.batchLayout, keyLength: 6)
            let current = batches.allRecords().filter { $0.int("cycle") == cycle && $0.int("ledger") != 9 }
            guard !current.contains(where: { $0.int("status") != 1 && $0.int("cleared") != 1 }) else {
                throw Error.unfinishedBatches
            }
            try closePostings(batches: Set(current.map { $0.int("number") }), archive: settings.str("arch") == "Y")
            for var batch in current {
                batch.setInt("cleared", 2)
                batch.setInt("stored", settings.int("run-date"))
                batch.setInt("start", 0)
                guard batches.rewrite(batch) == "00" else { throw Error.storage }
            }
            if cycle.isMultiple(of: period) {
                let index = cycle / period
                guard (1...4).contains(index) else { throw Error.invalidCycle }
                let quarter = settings.int("current-quarter")
                let ledger = IndexedFile(context.store, path: ChartOfAccounts.path,
                                         layout: ChartOfAccounts.layout, keyLength: 8)
                for var record in ledger.allRecords() {
                    record.setRaw("q\(index)", record.raw("balance"))
                    if quarter == 4 { record.setRaw("last", record.raw("balance")) }
                    guard ledger.rewrite(record) == "00" else { throw Error.storage }
                }
                let next = cycle + 1
                settings.setInt("scycle", (period == 3 && next > 12 || period == 13 && next > 52) ? 1 : next)
                settings.setInt("current-quarter", quarter == 4 ? 1 : quarter + 1)
                try system.write(1, settings.bytes)
            }
        }
    }

    private func closePostings(batches: Set<Int64>, archive: Bool) throws {
        guard let data = context.store.readRaw(LedgerBatches.postingPath) else {
            if !batches.isEmpty { throw Error.invalidPostings }
            return
        }
        let layout = LedgerBatches.postingLayout
        let slot = layout.size + 8
        guard data.count.isMultiple(of: slot) else { throw Error.invalidPostings }
        var compacted: [UInt8] = []
        var archived: [UInt8] = []
        for offset in stride(from: 0, to: data.count, by: slot) {
            let payload = offset + 8
            let length = data[offset..<payload].enumerated().reduce(UInt64(0)) {
                $0 | (UInt64($1.element) << (8 * $1.offset))
            }
            if length == 0 { continue }
            guard length == layout.size else { throw Error.invalidPostings }
            let posting = Record(layout, bytes: Array(data[payload..<(offset + slot)]))
            if posting.int("batch") != 0 && batches.contains(posting.int("batch")) {
                if archive { archived += archiveRows(posting) }
            } else {
                compacted += data[offset..<(offset + slot)]
            }
        }
        if archive { try context.store.appendRaw(Self.archivePath, archived) }
        try context.store.writeRaw(LedgerBatches.postingPath, compacted)
    }

    private func archiveRows(_ posting: Record) -> [UInt8] {
        var row = Record(Self.archiveLayout)
        for field in ["batch", "sequence", "code", "date", "memo"] {
            row.setRaw(field, posting.raw(field))
        }
        let amount = posting.int("amount"), vat = posting.int("vat-amount"), side = posting.str("vat-side")
        func line(_ account: String, branch: String, amount: Int64) -> [UInt8] {
            row.setRaw("account", posting.raw(account))
            row.setRaw("branch", posting.raw(branch))
            row.setInt("amount", Cobol.truncate(amount, digits: 10))
            return row.bytes + [10]
        }
        row.setRaw("counter-account", posting.raw("credit"))
        row.setRaw("counter-branch", posting.raw("credit-branch"))
        var output = line("debit", branch: "debit-branch", amount: side == "CR" ? amount + vat : amount)
        row.setRaw("counter-account", posting.raw("debit"))
        row.setRaw("counter-branch", posting.raw("debit-branch"))
        output += line("credit", branch: "credit-branch", amount: -(side == "DR" ? amount + vat : amount))
        if posting.int("vat-account") != 0 && vat != 0 {
            output += line("vat-account", branch: "vat-branch", amount: side == "CR" ? -vat : vat)
        }
        return output
    }
}
