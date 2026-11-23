import Foundation

extension BookkeepingService {
    public enum Report: Equatable { case accounts, defaults, trialBalance(summary: Bool, zeroBalances: Bool) }

    public struct TrialBalanceRow: Identifiable {
        public let account: Account
        public let debit: Int64
        public let credit: Int64
        public var id: String { account.id }
    }

    public struct TrialBalance {
        public let rows: [TrialBalanceRow]
        public let debit: Int64
        public let credit: Int64
        fileprivate let orphanCount: Int64
    }

    public func trialBalance(summary: Bool, zeroBalances: Bool) -> TrialBalance {
        let balanceLimit: Int64 = 1_000_000_000
        var main: Account?
        var debit: Int64 = 0
        var credit: Int64 = 0
        var orphanCount: Int64 = 0
        var rows: [TrialBalanceRow] = []
        func append(_ account: Account, debit: Int64, credit: Int64) {
            if debit == credit, !zeroBalances { return }
            rows.append(TrialBalanceRow(account: account, debit: max(0, (debit - credit) % balanceLimit),
                                        credit: max(0, (credit - debit) % balanceLimit)))
        }
        for account in accounts {
            if !summary {
                append(account, debit: account.debit, credit: account.credit)
            } else if account.child == 0 {
                if let main { append(main, debit: debit, credit: credit) }
                main = account
                debit = account.debit % balanceLimit
                credit = account.credit % balanceLimit
            } else {
                if main?.code != account.code { orphanCount = (orphanCount + 1) % 10_000 }
                debit = (debit + account.debit) % balanceLimit
                credit = (credit + account.credit) % balanceLimit
            }
        }
        if summary, let main { append(main, debit: debit, credit: credit) }
        return TrialBalance(rows: rows, debit: rows.reduce(0) { ($0 + $1.debit) % balanceLimit },
                            credit: rows.reduce(0) { ($0 + $1.credit) % balanceLimit }, orphanCount: orphanCount)
    }

    @discardableResult
    public func printReport(_ report: Report) throws -> Data {
        let settings = system
        var output: [UInt8] = []
        func field(_ text: String, _ width: Int) -> [UInt8] { SJIS.encode(text, size: width) }
        func spaces(_ width: Int) -> [UInt8] { field("", width) }
        func number(_ value: Int64, _ width: Int) -> [UInt8] {
            let digits = Array(String(value).utf8.suffix(width))
            return value == 0 ? spaces(width) : spaces(width - digits.count) + digits
        }
        func line(_ bytes: [UInt8], after: Int = 1) {
            output += Array(repeating: 0x0a, count: after)
            output += bytes.prefix(80).reversed().drop(while: { $0 == 0x20 }).reversed()
        }
        let date = Array(dateString(today).utf8)
        switch report {
        case .accounts:
            let records = store.all(accountsPath).map {
                Record(BookkeepingRecords.nlLayout, bytes: $0.data)
            }.filter { $0.str("type") != "S" }
            for (index, row) in records.enumerated() {
                if index % 75 == 0 {
                    if index > 0 { output.append(0x0c) }
                    line(settings.raw("suser") + spaces(4) + field("Incomplete Records System", 26) + spaces(18) + date,
                         after: index == 0 ? 1 : 0)
                    line(settings.raw("client") + spaces(7) + field("Accounts Directory", 18) + spaces(22)
                         + field("Page -", 6) + number(Int64(index / 75 + 1), 3), after: 2)
                    line(spaces(11) + field("  Main A/C       Sub-Account     ------Description------", 56)
                         + field("    A/C Type", 12), after: 2)
                    line([])
                }
                let child = row.int("sub-nominal")
                line(spaces(14) + number(child == 0 ? row.int("owning") : 0, 5) + spaces(12)
                     + number(child, 5) + spaces(8) + row.raw("name") + spaces(7) + row.raw("ac"))
            }
        case .defaults:
            line(settings.raw("suser") + spaces(5) + field("Incomplete Records System", 25) + spaces(17) + date)
            line(settings.raw("client") + spaces(9) + field("Posting Defaults", 16), after: 2)
            line(field("             A/C Nos     ------Description------    Code VAT", 64), after: 2)
            line([], after: 2)
            let bytes = defaultBytes
            for row in defaults {
                let index = row.id - 1
                var data = spaces(10) + number(Int64(row.id), 2) + spaces(2)
                if row.account != 0 {
                    let account = try postingAccount(row.account)
                    data += number(Int64(row.account), 5) + spaces(6) + account.raw("name") + spaces(4)
                    data += bytes[(160 + 2 * index)..<(162 + 2 * index)]
                    data += spaces(5) + [bytes[224 + index]]
                }
                line(data)
            }
        case let .trialBalance(summary, zeroBalances):
            let balance = trialBalance(summary: summary, zeroBalances: !summary || zeroBalances)
            func money(_ cents: Int64, showZero: Bool = false) -> [UInt8] {
                if cents == 0, !showZero { return spaces(12) }
                let digits = Array((String(cents / 100) + "." + Cobol.z(cents % 100, 2)).utf8)
                return spaces(12 - digits.count) + digits
            }
            func heading(_ page: Int) {
                if page > 1 { output.append(0x0c) }
                line(settings.raw("suser") + spaces(5) + field(summary ? "Summary" : "Detail", 8)
                     + field("Trial Balance", 13) + spaces(6) + date
                     + spaces(7) + field("Page ", 5) + number(Int64(page), 3), after: page == 1 ? 1 : 0)
                line(settings.raw("client") + field("    Start Date - ", 17) + settings.raw("start-date")
                     + field("           End Date - ", 22) + settings.raw("end-date"), after: 2)
                line(field(" Account     ----------Name----------", 37) + field("   Type", 19)
                     + field("   --Debit--   --Credit-", 24), after: 2)
                line([])
            }
            heading(1)
            for (index, row) in balance.rows.enumerated() {
                let account = row.account
                let child = account.child != 0
                let name = try accountRecord(account.code, account.child).raw("name")
                line(number(Int64(child ? account.child : account.code), 6) + spaces(6)
                     + name + spaces(4) + field(child ? "Sub" : "Main", 16)
                     + money(row.debit) + money(row.credit))
                if (index + 1) % 70 == 0 { heading((index + 1) / 70 + 1) }
            }
            let rule = spaces(57) + field("=========== ===========", 23)
            line(rule, after: 3)
            line(number(balance.orphanCount, 4) + spaces(37) + field("T o t a l", 15)
                 + money(balance.debit, showZero: true) + money(balance.credit, showZero: true))
            line(rule)
        }
        if !output.isEmpty { output.append(0x0a) }
        try store.writeRaw(directory + "prt-1", output)
        return Data(output)
    }
}
