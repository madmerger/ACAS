import Foundation

extension BookkeepingService {
    public struct AnnualStatement {
        public let data: Data
        public let interrupted: Bool
    }

    private enum StatementStop: Error { case ledgerOrder }

    public func printAnnualStatement(title: String) throws -> AnnualStatement {
        let layout = BookkeepingRecords.nlLayout
        guard let work = store.readRaw(directory + "worksort.tmp"), !work.isEmpty, work.count % layout.size == 0,
              !title.contains(where: \.isNewline) else { throw Failure.invalidInput }
        let records = stride(from: 0, to: work.count, by: layout.size).map {
            Record(layout, bytes: Array(work[$0..<($0 + layout.size)]))
        }
        guard records.allSatisfy({ $0.raw("ac").first.map { (65...90).contains($0) } == true }),
              let finalCategory = records.last?.str("ac") else { throw Failure.invalidInput }
        let buckets = Dictionary(grouping: records) { $0.str("ac") }
        let end = system.raw("end-date")
        let year = Array(end.suffix(2))
        guard year.allSatisfy({ (48...57).contains($0) }) else { throw Failure.invalidInput }

        var output: [UInt8] = []
        func spaces(_ count: Int) -> [UInt8] { Array(repeating: 0x20, count: count) }
        func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }
        func centered(_ bytes: [UInt8], in width: Int) -> [UInt8] {
            let text = bytes.drop(while: { $0 == 0x20 }).reversed().drop(while: { $0 == 0x20 }).reversed()
            return spaces((width - text.count) / 2) + text
        }
        func write(_ bytes: [UInt8] = [], after: Int = 1) {
            output += Array(repeating: 0x0a, count: after)
            output += bytes.reversed().drop(while: { $0 == 0x20 }).reversed()
        }
        func heading(_ title: [UInt8], page: Bool) {
            if page { output.append(0x0c) }
            write(spaces(28) + centered(system.raw("client"), in: 24), after: page ? 0 : 1)
            write(spaces(20) + centered(title, in: 40), after: 2)
            write(spaces(25) + ascii("For the Year Ended ") + end, after: 2)
            write(spaces(34) + ascii("--------20") + year + ascii("--------"), after: 2)
        }
        func balance(_ row: Record) -> Int64 {
            let debit = row.int("dr") - row.int("cr")
            let category = row.str("ac")
            return category < "E" || category == "I" || category == "J" || category >= "U" ? -debit : debit
        }
        func amount(_ cents: Int64) -> [UInt8] {
            let whole = (abs(cents) + 50) / 100 % 10_000_000
            let digits = whole == 0 ? [] : ascii(String(whole))
            return ascii(cents < 0 ? "(" : " ") + spaces(7 - digits.count) + digits + ascii(cents < 0 ? ")" : " ")
        }
        func detail(_ categories: String) throws -> Int64 {
            var total: Int64 = 0
            for letter in categories {
                let category = String(letter)
                // After EOF irs060 still compares the last record's category on the next pass.
                guard category <= finalCategory else { throw StatementStop.ledgerOrder }
                var owner: Record?
                var cents: Int64 = 0
                for row in buckets[category, default: []] {
                    if row.int("sub-nominal") == 0 {
                        if let owner, cents != 0 { write(owner.raw("name") + spaces(10) + amount(cents)) }
                        owner = row
                        cents = 0
                    }
                    cents += balance(row)
                    total += balance(row)
                }
                if let owner, cents != 0 { write(owner.raw("name") + spaces(10) + amount(cents)) }
            }
            return total
        }
        func total(_ name: String, _ cents: Int64, subtotal: Bool = false) {
            write(spaces(subtotal ? 45 : 34) + ascii("---------"))
            let label = spaces(2) + ascii(name)
            write(label + spaces(45 - label.count) + amount(cents))
        }

        let defaultTitle = "Profit and Loss Report"
        let reportTitle = SJIS.encode(title.isEmpty ? defaultTitle : title, size: 40)
        heading(reportTitle, page: false)
        write()
        var interrupted = false
        do {
            let income = try detail("ABCD")
            total("Total Income", income)
            write(); write()
            let costs = try detail("EFGH")
            total("Less Total Direct Costs", costs)
            let gross = income - costs
            total("Gross Profit", gross, subtotal: true)
            write()
            let sundry = try detail("IJ")
            total("Plus Sundry Income", sundry)
            write(); write()
            let indirect = try detail("KLMN")
            total("Less Total Indirect Costs", indirect)
            let net = gross + sundry - indirect
            total("Net Profit", net, subtotal: true)
            write(spaces(45) + ascii("========="))

            heading(ascii("Balance Sheet"), page: true)
            let fixed = try detail("OPQ")
            total("Fixed Asset Total", fixed)
            write()
            let current = try detail("RST")
            total("Plus Total Current Assets", current)
            let assets = fixed + current
            total("Total Assets", assets, subtotal: true)
            write()
            let liabilities = try detail("UV")
            total("Less Current Liabilities", liabilities)
            total("Net Current Assets", assets - liabilities, subtotal: true)
            write(spaces(45) + ascii("========="))
            write(after: 2)
            let capital = try detail("WXYZ")
            total("Capital Account Total", capital)
            write(); write()
            total("Net Profits", net)
            total("Net Current Assets", capital + net, subtotal: true)
            write(spaces(45) + ascii("========="))

            output.append(0x0c)
            write(spaces(28) + centered(system.raw("client"), in: 24), after: 0)
            write(spaces(20) + centered(ascii("Balance Sheet"), in: 40), after: 2)
            write(system.raw("client") + spaces(10) + ascii("Sales Ratios") + spaces(18)
                  + ascii("Period To - ") + end, after: 2)
            write()
            for (label, profit) in [("Gross Profit % to Sales", gross), ("Net Profit % to Sales", gross - indirect)] {
                let ratio = income == 0 ? 0 : abs(Double(profit) / Double(income) * 100)
                let digits = ascii(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), ratio))
                write(SJIS.encode(label, size: 24) + spaces(max(0, 7 - digits.count)) + digits.suffix(7), after: 2)
            }
        } catch StatementStop.ledgerOrder {
            interrupted = true
        }
        output.append(0x0a)
        try store.writeRaw(directory + "prt-1", output)
        return AnnualStatement(data: Data(output), interrupted: interrupted)
    }
}
