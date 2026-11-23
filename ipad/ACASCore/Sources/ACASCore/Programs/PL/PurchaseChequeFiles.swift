import Foundation

extension PurchaseLedger {
    private var chequePath: String { base + "cheque.dat" }

    @discardableResult
    public func generateChequeFile(firstNumber: Int64, date: Date) throws -> Data {
        guard (0...99_999_999).contains(firstNumber) else { throw ScheduleError.invalidChequeNumber }
        let day = try legacyDate(date)
        return try store.withTransaction {
            guard store.kind(schedulePath) == "indexed" else { throw ScheduleError.noSchedule }
            var number = firstNumber
            var bytes: [UInt8] = []
            let delimiter = Cobol.rtrim(system.str("pl-delim")).first ?? " "
            for var record in scheduleRecords() where record.int("gross") > 0 {
                let supplier = supplierRecord(record.str("supplier"))
                let address = supplier.map { $0.str("purch-addr1") + $0.str("purch-addr2") } ?? "Record Missing"
                var parts = address.split(separator: delimiter, maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
                parts += Array(repeating: "", count: max(0, 5 - parts.count))
                let gross = record.int("gross")
                let (upper, lower) = ChequeWords.format(gross)
                var line = record.raw("supplier") + [44] + SJIS.encode(supplier?.str("purch-name") ?? "Record Missing", size: 30) + [44]
                for part in parts.prefix(5) { line += SJIS.encode(part, size: 32) + [44] }
                line += SJIS.encode(upper, size: 64) + [44] + SJIS.encode(lower, size: 64) + [44]
                line += SJIS.encode(Pic.edit("z(6)9.99", value: gross, scale: 2), size: 10) + [44]
                if record.int("sort-code") == 0 {
                    line += SJIS.encode(Pic.edit("z(8)9", value: number, scale: 0), size: 9)
                    record.setInt("cheque", number)
                    number = (number + 1) % 100_000_000
                } else {
                    line += SJIS.encode("BACS", size: 9)
                    record.setInt("cheque", 0)
                }
                line += [44] + SJIS.encode(reportDate(day), size: 10) + [44]
                for i in 1...9 {
                    let folio = record.int("folio-\(i)")
                    let value = record.int("value-\(i)")
                    line += record.raw("reference-\(i)") + [44]
                    line += SJIS.encode(folio == 0 ? "" : Pic.edit("z(7)9", value: folio, scale: 0), size: 8) + [44]
                    line += SJIS.encode(value == 0 ? "" : Pic.edit("z(6)9.99", value: value, scale: 2), size: 10)
                    if i != 9 { line.append(44) }
                }
                while line.last == 32 { line.removeLast() }
                bytes += line + [10]
                record.setInt("date", day)
                try requirePostingWrite(store.rewrite(schedulePath, key: Array(record.bytes.prefix(8)), data: record.bytes), path: schedulePath)
            }
            try store.writeRaw(chequePath, bytes)
            return Data(bytes)
        }
    }

    public func remittanceAdvice() throws {
        guard let bytes = store.readRaw(chequePath) else { throw ScheduleError.noSchedule }
        let settings = system
        let printer = PurchasePrinter(self)
        for (index, line) in bytes.split(separator: 10).enumerated() {
            let row = Array(line.prefix(645)) + Array(repeating: UInt8(32), count: max(0, 645 - line.count))
            func field(_ offset: Int, _ width: Int) -> String { SJIS.decode(row[offset..<(offset + width)]) }
            let box = Cobol.x("", 29) + String(repeating: "*", count: 24)
            if index == 0 { printer.write("", after: 1) } else { printer.writePage("") }
            printer.write(box, after: 1)
            printer.write(Cobol.x("", 29) + "** Remittance  Advice **", after: 1)
            printer.write(box, after: 1)
            printer.write("To " + Cobol.x(field(8, 30), 32) + "      From   " + Cobol.x(settings.str("usera"), 32), after: 3)
            for i in 0..<5 {
                let from = i < 4 ? settings.str("address-\(i + 1)") : ""
                printer.write(Cobol.x("", 3) + field(39 + i * 33, 32) + Cobol.x("", 13) + Cobol.x(from, 32), after: 1)
            }
            printer.write("   A/C Number - " + Cobol.x(field(0, 7), 19) + "Date " + field(355, 10), after: 4)
            printer.write(Cobol.x("", 10) + "Invoice Nos       Folio" + Cobol.x("", 17) + "Amount", after: 3)
            printer.write("", after: 1)
            for i in 0..<9 {
                let offset = 366 + i * 31
                let amount = field(offset + 20, 10)
                if !Cobol.rtrim(amount).isEmpty {
                    printer.write(Cobol.x("", 11) + Cobol.x(field(offset, 10), 14)
                                  + Cobol.x(field(offset + 11, 8), 23) + Cobol.x(amount, 12), after: 1)
                }
            }
            let rule = Cobol.x("", 48) + "=========="
            printer.write(rule, after: 3)
            let cheque = field(345, 9)
            let method = Cobol.rtrim(cheque) == "BACS" ? "BACS   to your Bank" : "Cheque " + cheque
            printer.write(Cobol.x("", 11) + "Total Paid by " + Cobol.x(method, 23) + Cobol.x(field(334, 10), 12), after: 1)
            printer.write(rule, after: 1)
        }
        try printer.close()
    }
}

private enum ChequeWords {
    static let ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven",
                       "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
    static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

    static func word(_ value: Int) -> String {
        if value < 20 { return ones[value] }
        return tens[value / 10] + (value % 10 == 0 ? "" : "-" + ones[value % 10])
    }

    static func format(_ amount: Int64) -> (String, String) {
        let value = Int(amount)
        func part(_ divisor: Int, _ suffix: String) -> String {
            let number = value / divisor % 100
            return number == 0 ? "" : word(number) + suffix
        }
        let upper = part(100_000_000, " Million ") + part(10_000_000, " Hundred and ") + part(100_000, " Thousand ")
        let lower = part(10_000, " Hundred and ") + part(100, "")
        let pounds = upper.isEmpty && lower.isEmpty ? "" : " Pounds "
        let pence = value % 100 == 0 ? "ONLY" : part(1, " Pence ")
        return (upper + String(repeating: "*", count: max(0, 64 - upper.count)), lower + pounds + pence)
    }
}
