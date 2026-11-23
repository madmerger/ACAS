import Foundation

extension BookkeepingService {
    public enum Side { case debit, credit }

    public var postings: [Posting] {
        store.all(postPath).map {
            let row = Record(BookkeepingRecords.postLayout, bytes: $0.data)
            return Posting(id: Int(row.int("key")), debit: Int(row.int("dr")), credit: Int(row.int("cr")),
                           amount: BookkeepingRecords.getSigned(row, "amount"),
                           description: Cobol.rtrim(row.str("legend")))
        }
    }

    public func post(defaultSlot: Int, side: Side, account: Int, date: Date, amount: Int64, description: String) throws {
        guard (1...32).contains(defaultSlot), amount != 0, (-999_999_999...999_999_999).contains(amount),
              Cobol.rtrim(SJIS.decode(SJIS.encode(description, size: 32)[...])) == Cobol.rtrim(description)
        else { throw Failure.invalidInput }
        let selected = defaults[defaultSlot - 1]
        guard selected.account != 0 else { throw Failure.missingDefault }
        guard !selected.usesTax else { throw Failure.invalidInput }
        let targetRecord = try postingAccount(account)
        let defaultRecord = try postingAccount(selected.account)
        let receiving = (side == .debit) == (amount > 0)
        let debit = receiving ? selected.account : account
        let credit = receiving ? account : selected.account

        var system = system
        var sequence = Int(system.int("next-post"))
        var post = Record(BookkeepingRecords.postLayout)
        post["code"] = selected.label
        post["date"] = dateString(date)
        post["legend"] = description
        post["vat-side"] = receiving ? "CR" : "DR"
        post.setInt("dr", Int64(debit))
        post.setInt("cr", Int64(credit))
        BookkeepingRecords.setSigned(&post, "amount", abs(amount))
        BookkeepingRecords.setSigned(&post, "vat-amount", 0)
        var key = [UInt8]()
        for _ in 0..<100_000 {
            sequence = (sequence + 1) % 100_000
            key = Array(Cobol.z(sequence, 5).utf8)
            if store.read(postPath, key: key) == nil { break }
        }
        post.setRaw("key", key)
        guard store.write(postPath, key: key, data: post.bytes) else { throw Failure.invalidInput }

        var target = targetRecord
        let field = receiving ? "cr" : "dr"
        target.setInt(field, (target.int(field) + abs(amount)) % 10_000_000_000)
        store.rewrite(accountsPath, key: target.raw("key"), data: target.bytes)

        var balance = defaultRecord
        let opening = balance.int("dr") - balance.int("cr")
        let adjustment = selected.account == account ? 0 : (receiving ? abs(amount) : -abs(amount))
        let closing = opening + adjustment
        balance.setInt("dr", max(0, closing) % 10_000_000_000)
        balance.setInt("cr", max(0, -closing) % 10_000_000_000)
        store.rewrite(accountsPath, key: balance.raw("key"), data: balance.bytes)
        system.setInt("next-post", Int64(sequence))
        system.setInt("save-sequ", 0)
        try writeLine(systemPath, system.bytes)
    }

    public func recalculate() throws {
        let journal = postings
        guard store.exists(postPath) else { throw Failure.missingPosting }
        var debits: [[UInt8]: Int64] = [:]
        var credits: [[UInt8]: Int64] = [:]
        for entry in journal {
            debits[try postingAccount(entry.debit).raw("key"), default: 0] += entry.amount
            credits[try postingAccount(entry.credit).raw("key"), default: 0] += entry.amount
        }
        for entry in accounts {
            var record = try accountRecord(entry.code, entry.child)
            let key = record.raw("key")
            record.setInt("dr", debits[key, default: 0] % 10_000_000_000)
            record.setInt("cr", credits[key, default: 0] % 10_000_000_000)
            store.rewrite(accountsPath, key: key, data: record.bytes)
        }
    }
}
