import Foundation

public struct FinancialStatements {
    public enum Error: Swift.Error { case missingLedger, storage }

    static let path = "ledgers/acas/final.dat"
    static let layout = Layout("final-record", [
        ("placement", .x(1)),
        ("code", .n9(digits: 6, scale: 0, signed: false)),
        ("branch", .n9(digits: 2, scale: 0, signed: false)),
        ("name", .x(24)),
        ("balance", .comp3(digits: 10, scale: 2, signed: true)),
        ("last", .comp3(digits: 10, scale: 2, signed: true)),
    ])

    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generateReport() throws -> [UInt8] {
        try context.store.transaction {
            guard context.store.exists(ChartOfAccounts.path) else { throw Error.missingLedger }
            let ledger = IndexedFile(context.store, path: ChartOfAccounts.path, layout: ChartOfAccounts.layout, keyLength: 8)
            let totals = IndexedFile(context.store, path: Self.path, layout: Self.layout, keyLength: 9)
            totals.openOutput()
            var debit = [Int64](repeating: 0, count: 6)
            var credit = debit
            var active = debit
            var heading: Record?
            func rollUp(_ level: Int) {
                if let parent = (1..<level).reversed().first(where: { active[$0] != 0 }) {
                    debit[parent] = (debit[parent] + debit[level]) % 10_000_000_000
                    credit[parent] = (credit[parent] + credit[level]) % 10_000_000_000
                }
                debit[level] = 0
                credit[level] = 0
                if level != 5 { active[level] = 0 }
            }
            func writeHeading() throws {
                var total = Record(Self.layout)
                if let heading {
                    total.setRaw("placement", heading.raw("placement"))
                    total.setRaw("name", heading.raw("name"))
                } else {
                    total.setRaw("placement", [0])
                    total.setRaw("name", [UInt8](repeating: 0, count: 24))
                }
                total.setInt("code", active[1])
                total.setInt("balance", debit[1] - credit[1])
                guard totals.write(total) == "00" else { throw Error.storage }
                active[1] = 0
                debit[1] = 0
                credit[1] = 0
            }
            for account in ledger.allRecords().prefix(while: { $0.int("code") / 100 != 9999 }) {
                let code = account.int("code")
                let level = Int(account.int("level"))
                if active[5] != 0 && code != active[5] {
                    rollUp(5)
                    if level == 0 { active[5] = code }
                }
                if active[1...4].contains(code) { continue }
                if (1...4).contains(level) {
                    if active[level] != 0 {
                        for lower in (max(level, 2)...4).reversed() { rollUp(lower) }
                        if level == 1 { try writeHeading() }
                    }
                    active[level] = code
                    if level == 1 { heading = account }
                } else {
                    let balance = account.int("balance")
                    if code != active[5] { debit[5] = 0; credit[5] = 0 }
                    if balance < 0 { credit[5] = (credit[5] - balance) % 10_000_000_000 }
                    else { debit[5] = (debit[5] + balance) % 10_000_000_000 }
                    active[5] = code
                }
            }
            for level in (2...5).reversed() { rollUp(level) }
            try writeHeading()
            let settings = CompanySetup(context).settings
            let date = Maps04.format(Maps04.toDate(Int(settings.number("run-date"))),
                                     dateForm: Int(settings.number("date-form")))
            let bytes = render(totals.allRecords(), company: settings.text("usera"), date: date)
            try context.store.writeRaw(CompanySetup.reportPath, bytes)
            return bytes
        }
    }

    private func render(_ records: [Record], company: String, date: String) -> [UInt8] {
        let groups = Array("11112222334444555666778888").compactMap(\.wholeNumberValue)
        let names = ["Sales Income", "Direct Costs", "Sundry Income", "Indirect Costs", "Fixed Assets",
                     "Current Assets", "Current Liabilities", "Shareholders Funds"]
        let rule = String(repeating: "=", count: 11)
        let headings = Cobol.x("", 50) + Cobol.x("<--------This  Year-------->", 40) + "<--------Last  Year-------->"
        let subtotalRule = Cobol.x("", 50) + rule + Cobol.x("", 29) + rule
        let totalRule = Cobol.x("", 66) + rule + Cobol.x("", 29) + rule
        var bytes: [UInt8] = []
        func line(_ text: String, after: Int = 1) {
            bytes += [UInt8](repeating: 10, count: after) + SJIS.encode(text, size: 132)
        }
        func amount(_ value: Int64) -> String { Pic.edit("z(7)9.99cr", value: value, scale: 2) }
        func sum(_ lhs: Int64, _ rhs: Int64) -> Int64 { (lhs + rhs) % 10_000_000_000 }

        line(company)
        line(Cobol.x("", 32) + Cobol.x("Profit & Loss Account    For the period to ", 43) + date, after: 2)
        line(Cobol.x("", 33) + String(repeating: "*", count: 52))
        line(headings, after: 3)
        var group = 0
        var subtotal: Int64 = 0
        var running: Int64 = 0
        var gross: Int64 = 0
        var net: Int64 = 0
        var totalLabel = ""
        for record in records {
            let placement = record.raw("placement")[0]
            let next = (65...90).contains(placement) ? groups[Int(placement) - 65] : (placement == 32 ? group : 3)
            if next != group {
                if group != 0 {
                    line(subtotalRule, after: 2)
                    line(Cobol.x("", 50) + amount(subtotal) + Cobol.x("", 3) + amount(subtotal))
                    line(subtotalRule)
                    running = sum(running, [1, 3, 5].contains(group) ? subtotal : -subtotal)
                    switch next {
                    case 3: totalLabel = "Gross Profit"; gross = running
                    case 5: totalLabel = "Net Profit"; net = sum(running, gross)
                    case 8: totalLabel = "Net Current Value"
                    default: break
                    }
                    if [3, 5, 8].contains(next) {
                        line(totalRule, after: 2)
                        line(Cobol.x(totalLabel, 66) + amount(next == 5 ? net : running))
                        if next == 5 {
                            line(totalRule)
                            line(company)
                            line(Cobol.x("", 42) + Cobol.x("Balance Sheet  as at  ", 22) + date, after: 2)
                            line(Cobol.x("", 44) + String(repeating: "*", count: 30))
                            line(headings, after: 3)
                        } else {
                            line("", after: 2)
                        }
                        running = 0
                    }
                }
                line(names[next - 1])
                group = next
                subtotal = 0
            }
            let value = record.int("balance") * ([1, 3, 5].contains(group) ? -1 : 1)
            subtotal = sum(subtotal, value)
            bytes += [10] + [UInt8](repeating: 32, count: 20) + record.raw("name")
                + SJIS.encode(Cobol.x("", 6) + amount(value), size: 88)
        }
        line(Cobol.x("", 20) + Cobol.x("Net Profit", 30) + amount(net))
        line(totalRule, after: 2)
        line(Cobol.x(totalLabel, 66) + amount(sum(running, net)))
        line(totalRule)
        return bytes + [10]
    }
}
