import Foundation

extension BookkeepingService {
    public enum Report { case accounts, defaults }

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
        }
        if !output.isEmpty { output.append(0x0a) }
        try store.writeRaw(directory + "prt-1", output)
        return Data(output)
    }
}
