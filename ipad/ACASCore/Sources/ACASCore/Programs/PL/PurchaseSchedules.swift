import Foundation

extension PurchaseLedger {
    public enum ScheduleError: Swift.Error {
        case noSchedule, invalidSchedule, invalidAge, invalidChequeNumber
    }

    public struct ScheduledPayment: Identifiable {
        public struct Line: Identifiable {
            public let id: Int
            public let folio: Int64
            public let reference: String
            public let amount: Int64
            public let discount: Int64
        }

        public var id: String { supplier + "/" + String(sequence) }
        public let supplier: String
        public let sequence: Int64
        public let bankTransfer: Bool
        public let amount: Int64
        public let lines: [Line]
    }

    static let scheduleLayout: Layout = {
        let binary = FieldType.native(bytes: 4, signed: true)
        let byte = FieldType.native(bytes: 1, signed: true)
        let amount = FieldType.comp3(digits: 9, scale: 2, signed: true)
        var fields: [(String, FieldType)] = [
            ("supplier", .x(7)), ("sequence", byte), ("continuation", .x(1)), ("date", binary),
            ("cheque", binary), ("sort-code", binary), ("account", binary), ("gross", amount),
        ]
        for i in 1...9 {
            fields += [
                ("folio-\(i)", binary), ("period-\(i)", byte), ("value-\(i)", amount),
                ("discount-\(i)", .comp3(digits: 5, scale: 2, signed: true)), ("reference-\(i)", .x(10)),
            ]
        }
        return Layout("pay-record", fields)
    }()

    var schedulePath: String { base + "pay.dat" }
    public var scheduleAge: Int64 { system.int("age-to-pay") }

    func scheduleRecords() -> [Record] {
        store.all(schedulePath).compactMap {
            guard $0.data.count == Self.scheduleLayout.size else { return nil }
            return Record(Self.scheduleLayout, bytes: $0.data)
        }
    }

    public func paymentSchedule() -> [ScheduledPayment] {
        scheduleRecords().map { record in
            ScheduledPayment(supplier: Cobol.rtrim(record.str("supplier")), sequence: record.int("sequence"),
                             bankTransfer: record.int("sort-code") != 0, amount: record.int("gross"),
                             lines: (1...9).compactMap { i in
                let folio = record.int("folio-\(i)")
                guard folio != 0 else { return nil }
                return ScheduledPayment.Line(id: i, folio: folio, reference: Cobol.rtrim(record.str("reference-\(i)")),
                                             amount: record.int("value-\(i)"), discount: record.int("discount-\(i)"))
            })
        }
    }

    func clearSchedule() throws {
        for entry in store.all(schedulePath) {
            try requirePostingWrite(store.delete(schedulePath, key: entry.key), path: schedulePath)
        }
        store.createIndexed(schedulePath)
        try requirePostingWrite(store.kind(schedulePath) == "indexed", path: schedulePath)
    }

    public func generatePaymentSchedule(age: Int64) throws {
        guard (0...99).contains(age) else { throw ScheduleError.invalidAge }
        try store.withTransaction {
            var settings = system
            let runDate = settings.int("run-date")
            let cutoff = runDate - age
            let report = ScheduleReport(self, cutoff: cutoff)
            let invoices = Dictionary(grouping: openItemRecords().filter {
                $0.int("oi-status") != 1 && $0.str("oi-hold-flag") != "H" && $0.int("oi-b-nos") == 0
                    && $0.int("oi-type") == 2 && $0.int("oi-date") <= cutoff
            }) { $0.str("oi-supplier") }
            var lastDate = cutoff
            try clearSchedule()
            for entry in store.all(suppliersPath) where entry.data.count == PurchaseRecords.purchLayout.size {
                let supplier = Record(PurchaseRecords.purchLayout, bytes: entry.data)
                let code = supplier.str("purch-key")
                guard supplier.int("purch-current") > 0, let items = invoices[code] else { continue }
                var record = Record(Self.scheduleLayout)
                record["supplier"] = code
                record.setInt("sequence", 1)
                record.setInt("date", lastDate)
                record.setInt("sort-code", supplier.int("purch-sortcode"))
                if record.int("sort-code") != 0 { record.setInt("account", supplier.int("purch-accountno")) }
                var i = 1
                var total: Int64 = 0
                var gross: Int64 = 0
                var first = true
                for invoice in items {
                    lastDate = invoice.int("oi-date")
                    let days = runDate - lastDate
                    let remaining = itemGross(invoice) - invoice.int("oi-paid")
                    let discount = invoice.int("oi-deduct-days") >= days ? invoice.int("oi-deduct-amt") : 0
                    let value = remaining - discount
                    guard value != 0, remaining != 0, discount == 0 || value > 0 else { continue }
                    let period = min(90, max(0, days / 30 * 30))
                    record.setInt("folio-\(i)", invoice.int("oi-invoice"))
                    record.setInt("period-\(i)", period)
                    record.setInt("value-\(i)", value)
                    record.setInt("discount-\(i)", discount)
                    record["reference-\(i)"] = invoice.str("oi-ref")
                    total = Cobol.truncate(total + value, digits: 9, signed: false)
                    gross = Cobol.truncate(gross + value, digits: 9, signed: false)
                    record.setInt("gross", gross)
                    report.detail(supplier: first ? code : "", name: first ? supplier.str("purch-name") : "",
                                  record: record, line: i, date: lastDate, total: total)
                    first = false
                    if i == 9 {
                        record["continuation"] = "C"
                        try writeScheduleRecord(record)
                        let next = record.int("sequence") + 1
                        guard next <= 127 else { throw ScheduleError.invalidSchedule }
                        let blank = Record(Self.scheduleLayout)
                        for slot in 1...9 {
                            for field in ["folio", "period", "value", "discount", "reference"] {
                                let key = "\(field)-\(slot)"
                                record.setRaw(key, blank.raw(key))
                            }
                        }
                        record.setInt("sequence", next)
                        record.setInt("gross", 0)
                        gross = 0
                        i = 1
                    } else {
                        i += 1
                    }
                }
                if i != 1 { try writeScheduleRecord(record) }
            }
            try report.close()
            settings.setInt("age-to-pay", age)
            try systemFile.write(1, settings.bytes)
        }
    }

    private func writeScheduleRecord(_ record: Record) throws {
        try requirePostingWrite(store.write(schedulePath, key: Array(record.bytes.prefix(8)), data: record.bytes), path: schedulePath)
    }

    public func amendPaymentSchedule(supplier: String, sequence: Int64, line: Int, amount: Int64) throws {
        guard (1...9).contains(line), (1...127).contains(sequence), (0..<1_000_000_000).contains(amount) else {
            throw ScheduleError.invalidSchedule
        }
        try store.withTransaction {
            let key = SJIS.encode(supplier.uppercased(), size: 7) + [UInt8(sequence)]
            guard let bytes = store.read(schedulePath, key: key), bytes.count == Self.scheduleLayout.size else {
                throw ScheduleError.noSchedule
            }
            var record = Record(Self.scheduleLayout, bytes: bytes)
            let previous = record.int("value-\(line)")
            guard previous != 0 else { throw ScheduleError.invalidSchedule }
            record.setInt("value-\(line)", amount)
            record.setInt("gross", Cobol.truncate(record.int("gross") - previous + amount, digits: 9))
            try requirePostingWrite(store.rewrite(schedulePath, key: key, data: record.bytes), path: schedulePath)
        }
    }

    public func proofPaymentSchedule() throws {
        let report = ScheduleReport(self, cutoff: nil)
        var total: Int64 = 0
        var previousSupplier: String?
        var continued = false
        var supplierLabel = ""
        var name = ""
        for record in scheduleRecords() {
            let code = record.str("supplier")
            if !continued || previousSupplier != code {
                report.supplierBreak()
                let supplier = supplierRecord(code)
                supplierLabel = (supplier == nil ? "ZZZZZZZ" : code) + "/" + Cobol.z(record.int("sequence"), 2)
                name = supplier?.str("purch-name") ?? String(repeating: "Z", count: 30)
            }
            for i in 1...9 where record.int("value-\(i)") != 0 {
                total = Cobol.truncate(total + record.int("value-\(i)"), digits: 9, signed: false)
                report.detail(supplier: supplierLabel, name: name, record: record, line: i, date: record.int("date"), total: total)
                supplierLabel = ""
                name = ""
            }
            continued = record.str("continuation") == "C"
            previousSupplier = code
            if !continued { total = 0 }
        }
        try report.close()
    }
}

private final class ScheduleReport {
    let ledger: PurchaseLedger
    let printer: PurchasePrinter
    let cutoff: Int64?
    let pageLength: Int
    var page: Int64 = 0
    var lineCount = 0
    var totals = [Int64](repeating: 0, count: 4)

    init(_ ledger: PurchaseLedger, cutoff: Int64?) {
        self.ledger = ledger
        self.cutoff = cutoff
        printer = PurchasePrinter(ledger)
        pageLength = Int(ledger.system.int("page-lines"))
        headings()
    }

    private func headings() {
        page = (page + 1) % 100
        let title: String
        if let cutoff {
            title = Cobol.x("PL910 (3.01.07)", 56) + Cobol.x("Payments Due Report", 24)
                + Cobol.x("Prior To", 9) + ledger.reportDate(cutoff) + Cobol.x("", 25)
        } else {
            title = Cobol.x("PL930 (3.01.07)", 53) + Cobol.x("Payments Due Proof Report", 71)
        }
        let first = title + "Page " + Pic.edit("zz9", value: page, scale: 0)
        let date = Cobol.x(ledger.system.str("usera"), 122) + ledger.reportDate(ledger.system.int("run-date"))
        if page == 1 {
            printer.writeBefore(first, before: 1)
            printer.writeBefore(date, before: 1)
        } else {
            printer.writePage(first)
            printer.write(date, after: 1)
            printer.write("", after: 1)
        }
        printer.write(Cobol.x(cutoff == nil ? "" : " Number   Supplier", 38)
                      + "Folio M    Date     Invoice      Current       30 +        60 +        90 +       Total to Pay", after: 1)
        printer.write("", after: 1)
        lineCount = 5
    }

    func detail(supplier: String, name: String, record: Record, line: Int, date: Int64, total: Int64) {
        let index = Int(record.int("period-\(line)") / 30)
        let value = record.int("value-\(line)")
        var amounts = [Int64](repeating: 0, count: 4)
        if amounts.indices.contains(index) {
            amounts[index] = value
            totals[index] = Cobol.truncate(totals[index] + value, digits: 9, signed: false)
        }
        let key = Cobol.x(supplier, cutoff == nil ? 12 : 10)
        let folio = Pic.edit("z(7)9b", value: record.int("folio-\(line)"), scale: 0)
        let method = record.int("sort-code") == 0 ? "C " : "B "
        printer.write(key + Cobol.x(name, cutoff == nil ? 23 : 25) + folio + method + Cobol.x(ledger.reportDate(date), 12)
                      + Cobol.x(record.str("reference-\(line)"), 11) + figures(amounts, total: total), after: 1)
        lineCount += 1
        if lineCount > pageLength { headings() }
    }

    func supplierBreak() {
        if lineCount != 5 { printer.write("", after: 1) }
        lineCount += 1
    }

    private func figures(_ amounts: [Int64], total: Int64) -> String {
        amounts.map { $0 == 0 ? Cobol.x("", 12) : PurchaseRecords.cr("z(6)9.99cr", $0, int: 7) }.joined()
            + "    " + (total == 0 ? "" : Pic.edit("z(6)9.99", value: total, scale: 2))
    }

    func close() throws {
        printer.write(Cobol.x("", 69) + String(repeating: "  --------  ", count: 4) + "      ========", after: 1)
        printer.write(Cobol.x("    Total", 69) + figures(totals, total: Cobol.truncate(totals.reduce(0, +), digits: 9)), after: 1)
        try printer.close()
    }
}
