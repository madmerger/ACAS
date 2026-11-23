import Foundation

public struct StructuredTrialBalance {
    private struct Balance {
        var code: Int64 = 0
        var debit: Int64 = 0
        var credit: Int64 = 0
    }

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generateReport() throws {
        guard context.store.exists(ChartOfAccounts.path) else { throw DetailedTrialBalance.Error.missingLedger }
        let settings = CompanySetup(context).settings
        let date = Maps04.format(Maps04.toDate(Int(settings.number("run-date"))),
                                 dateForm: Int(settings.number("date-form")))
        var page = 0, count = 0
        var output: [UInt8] = []
        var balance = Array(repeating: Balance(), count: 6)
        var totals = Balance()
        let pattern = "zzzzzzz9.99b"

        func printLine(_ text: String, advance: [UInt8] = [10]) {
            output += advance + SJIS.encode(text, size: 132)
        }

        func headings() {
            page += 1
            printLine(Cobol.x("gl090a (3.00.04)", 50) + Cobol.x("Profit Centre Trial Balance", 27)
                      + Cobol.x("", 47) + "Page " + Pic.edit("zz9", value: Int64(page % 1000), scale: 0),
                      advance: page == 1 ? [] : [12])
            output += [10] + SJIS.encode(settings.text("usera"), size: 32)
                + SJIS.encode(Cobol.x("", 25) + "Condensed Report" + Cobol.x("", 49) + date, size: 100)
            if page != 1 { printLine("") }
            printLine("Account      <----Detail   Level----><-------Level  4-------><-------Level  3-------><-------Level  2-------><-------Level  1------>",
                      advance: page == 1 ? [10, 10] : [10])
            printLine("               Debit        Credit      Debit       CRedit      Debit       Credit      Debit       Credit      Debit       Credit")
            printLine("")
            count = 6
        }

        func sum(_ a: Int64, _ b: Int64) -> Int64 { (a + b) % 10_000_000_000 }

        func flush(_ level: Int) {
            let current = balance[level]
            let net = current.debit - current.credit
            if level == 5 || level == 1 || current.code != 0 {
                let amounts = level == 5 ? (current.debit, current.credit) : (max(0, net), max(0, -net))
                let index = (5 - level) * 2
                let columns = (0..<10).map { column in
                    let value = column == index ? amounts.0 : column == index + 1 ? amounts.1 : 0
                    return value == 0 ? Cobol.x("", 12) : Pic.edit(pattern, value: value, scale: 2)
                }.joined()
                let code = Cobol.x(Cobol.x("", level - 1)
                                   + Pic.edit("9999.99", value: current.code, scale: 2), 12)
                printLine(code + columns)
                count += 1
                if count > settings.number("page-lines") { headings() }
            }
            if level == 1 { printLine("") }
            if let parent = (1..<level).reversed().first(where: { balance[$0].code != 0 }) {
                balance[parent].debit = sum(balance[parent].debit, current.debit)
                balance[parent].credit = sum(balance[parent].credit, current.credit)
            } else {
                totals.debit = sum(totals.debit, max(0, net))
                totals.credit = sum(totals.credit, max(0, -net))
            }
            balance[level] = Balance(code: level == 5 ? current.code : 0)
        }

        headings()
        for account in ChartOfAccounts(context).accounts.prefix(while: { !$0.code.hasPrefix("9999") }) {
            let code = Int64(account.code) ?? 0
            let level = account.level
            if balance[5].code != 0 && balance[5].code != code {
                flush(5)
                if level == 0 { balance[5].code = code }
            }
            if (1...4).contains(where: { balance[$0].code == code }) { continue }
            if (1...4).contains(level) {
                if balance[level].code != 0 {
                    for group in (level...4).reversed() { flush(group) }
                }
                balance[level].code = code
                continue
            }
            balance[5].code = code
            balance[5].debit = sum(balance[5].debit, max(0, account.balance))
            balance[5].credit = sum(balance[5].credit, max(0, -account.balance))
        }
        for level in (1...5).reversed() { flush(level) }
        let rule = Cobol.x("", 108) + " ==========  =========="
        printLine(rule, advance: [10, 10, 10])
        printLine(Cobol.x("", 20) + Cobol.x("t o t a l", 88) + Pic.edit(pattern, value: totals.debit, scale: 2)
                  + Pic.edit("zzzzzzz9.99", value: totals.credit, scale: 2))
        printLine(rule)
        output.append(10)
        try context.store.writeRaw(CompanySetup.reportPath, output)
    }
}
