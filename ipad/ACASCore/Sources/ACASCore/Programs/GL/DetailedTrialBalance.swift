import Foundation

public struct DetailedTrialBalance {
    public enum Error: Swift.Error { case missingLedger }

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generateReport() throws {
        guard context.store.exists("ledgers/acas/ledger.dat") else { throw Error.missingLedger }
        let settings = CompanySetup(context).settings
        let date = Maps04.format(Maps04.toDate(Int(settings.number("run-date"))),
                                 dateForm: Int(settings.number("date-form")))
        let quarters: [(Int, Int)] = [(0, 0), (4, 3), (1, 4), (2, 1), (3, 2)]
        let currentQuarter = settings.number("current-quarter")
        let (first, second) = quarters[(1...4).contains(currentQuarter) ? Int(currentQuarter) : 0]
        let branch = settings.text("p-c")
        let branchHeading = branch == "P" ? "  P/C " : branch == "B" ? "Branch" : ""
        let rule = Cobol.x("", 50) + "=========== ===========    =========== ==========="
        var page = 0
        var count = 0
        var output: [UInt8] = []

        func line(_ text: String, advance: [UInt8] = [10]) {
            output += advance + SJIS.encode(text, size: 132)
        }

        func heading() {
            page += 1
            line(Cobol.x("gl090b (3.00.04)", 56) + "Detail Trial Balance" + Cobol.x("", 48)
                 + "Page " + Pic.edit("zz9", value: Int64(page % 1000), scale: 0),
                 advance: page == 1 ? [] : [12])
            output += [10] + SJIS.encode(settings.text("usera"), size: 32)
                + SJIS.encode(Cobol.x("", 90) + date, size: 100)
            if page != 1 { line("") }
            line(Cobol.x("Account", 10) + Cobol.x(branchHeading, 10)
                 + "<---------Name--------->      <---Current Balance--->    <--Last Year Balance->     <-Quarter \(first)->  <-Quarter \(second)->",
                 advance: page == 1 ? [10, 10] : [10])
            line(Cobol.x("", 53) + "Debit      Credit          Debit     Credit")
            line("")
            count = 6
        }

        func picture(_ pattern: String, _ value: Int64, scale: Int = 2) -> String {
            value == 0 ? Cobol.x("", Pic.size(pattern)) : Pic.edit(pattern, value: value, scale: scale)
        }

        func entry(code: Int64 = 0, branch: Int64 = 0, name: String, debit: Int64, credit: Int64,
                   lastDebit: Int64, lastCredit: Int64, q1: Int64 = 0, q2: Int64 = 0) {
            output += [10] + SJIS.encode(picture("9999.99", code) + Cobol.x("", 5)
                                       + picture("z9bbbbbb", branch, scale: 0), size: 20)
            output += SJIS.encode(name, size: 30)
            let amounts = picture("zzzzzzz9.99b", debit) + picture("zzzzzzz9.99", credit)
                + Cobol.x("", 4) + picture("zzzzzzz9.99b", lastDebit) + picture("zzzzzzz9.99", lastCredit)
                + Cobol.x("", 4) + picture("zzzzzzz9.99cr", q1) + Cobol.x("", 2) + picture("zzzzzzz9.99cr", q2)
            output += SJIS.encode(amounts, size: 82)
        }

        heading()
        var previousPrefix = 0
        var debit: Int64 = 0, credit: Int64 = 0, lastDebit: Int64 = 0, lastCredit: Int64 = 0
        for account in ChartOfAccounts(context).accounts.prefix(while: { !$0.code.hasPrefix("9999") }) {
            let code = Int64(account.code) ?? 0
            let prefix = Int(code / 100)
            if prefix != previousPrefix {
                line("")
                count += 1
                previousPrefix = prefix
            }
            let dr = max(0, account.balance), cr = max(0, -account.balance)
            let oldDr = max(0, account.previousBalance), oldCr = max(0, -account.previousBalance)
            debit = (debit + dr) % 10_000_000_000
            credit = (credit + cr) % 10_000_000_000
            lastDebit = (lastDebit + oldDr) % 10_000_000_000
            lastCredit = (lastCredit + oldCr) % 10_000_000_000
            entry(code: code, branch: Int64(account.branch) ?? 0, name: account.name,
                  debit: dr, credit: cr, lastDebit: oldDr, lastCredit: oldCr,
                  q1: first == 0 ? account.previousBalance : account.quarterBalances[first - 1],
                  q2: second == 0 ? account.previousBalance : account.quarterBalances[second - 1])
            count += 1
            if count > settings.number("page-lines") { heading() }
        }
        line(rule, advance: [10, 10, 10])
        entry(name: "T o t a l", debit: debit, credit: credit, lastDebit: lastDebit, lastCredit: lastCredit)
        line(rule)
        output.append(10)
        try context.store.writeRaw(CompanySetup.reportPath, output)
    }
}
