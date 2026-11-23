import Foundation

public struct PeriodClosing {
    public enum Ledger: Hashable { case sales, purchases }
    public enum Failure: Error { case unconfigured, unfinishedUpdates, missingLedger, wrongPassword, invalidDate }

    public struct Warning {
        public let hasUnpostedInvoices: Bool
        public let requiresQuarterChoice: Bool
    }

    private let context: BusinessContext
    private let directory = "ledgers/acas/"
    private var store: FileStore { context.store }
    private var file: RelativeFile { RelativeFile(store, path: directory + "system.dat", recordSize: 1024) }
    private let temporaryRecordSize = 129

    public init(_ context: BusinessContext) { self.context = context }

    private func settings() throws -> Record {
        guard let bytes = file.read(1) else { throw Failure.unconfigured }
        return Record(SystemLayout.layout, bytes: bytes)
    }

    public func warning() throws -> Warning {
        let system = try settings()
        try validateStatus(system)
        return Warning(hasUnpostedInvoices: system.int("s-flag-i") == 1 || system.int("p-flag-i") == 1,
                       requiresQuarterChoice: ![3, 13].contains(system.int("period")))
    }

    private func validateStatus(_ system: Record) throws {
        guard system.raw("file-statuses")[14] == 0x31 else { throw Failure.unconfigured }
        guard ![system.int("s-flag-p"), system.int("p-flag-p")].contains(where: { $0 == 1 || $0 == 2 }),
              system.int("s-flag-a") != 1, system.int("p-flag-a") != 1
        else { throw Failure.unfinishedUpdates }
    }

    public func close(_ ledgers: Set<Ledger>, date: Date, password: String, proceedWithUnposted: Bool,
                      endOfQuarter: Bool) throws {
        var system = try settings()
        try validateStatus(system)
        let statuses = system.raw("file-statuses")
        guard !ledgers.isEmpty,
              !ledgers.contains(.sales) || (statuses[18] == 0x31 && system.int("level-3") == 1),
              !ledgers.contains(.purchases) || (statuses[28] == 0x31 && system.int("level-2") == 1)
        else { throw Failure.missingLedger }
        guard proceedWithUnposted || (system.int("s-flag-i") != 1 && system.int("p-flag-i") != 1)
        else { throw Failure.unfinishedUpdates }
        guard system.str("pass-word") == Self.legacyPassword(password) else { throw Failure.wrongPassword }
        let components = context.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day,
              Maps04.validYMD(year, month, day) else { throw Failure.invalidDate }
        let closed = Maps04.integerOfDate(year: year, month: month, day: day)

        var cycle = system.int("scycle") + 1
        var quarter = system.int("current-quarter")
        let period = system.int("period")
        let yearEnd = period == 3 ? cycle == 13 : period == 13 ? cycle == 53 : endOfQuarter && quarter == 4
        let quarterEnd = yearEnd || (period == 3 ? [4, 7, 10].contains(cycle) :
                           period == 13 ? [14, 27, 40].contains(cycle) : endOfQuarter)
        if yearEnd { cycle = 1; quarter = 1 }
        else if quarterEnd { quarter = (quarter + 1) % 10 }
        system.setInt("scycle", cycle)
        system.setInt("current-quarter", quarter)
        var balances = file.read(4) ?? SystemAuxRecords.initialRecord4()
        for ledger in [Ledger.sales, .purchases] where ledgers.contains(ledger) {
            let sales = ledger == .sales
            rollLedger(sales: sales, quarter: quarterEnd ? quarter : 0, yearEnd: yearEnd)
            try rollOpenItems(sales: sales, ownNumbers: system.str("sl-own-nos") == "Y")
            rollValues(sales: sales, yearEnd: yearEnd)
            try rollInvoices(sales: sales, closed: closed, retention: Int(system.int("pf-retention")),
                         ownNumbers: system.str("sl-own-nos") == "Y")
            let offset = sales ? 0 : 60
            balances.replaceSubrange(offset..<(offset + 6), with: Array(balances[(offset + 6)..<(offset + 12)]))
            for field in 1...7 {
                let start = offset + field * 6
                balances.replaceSubrange(start..<(start + 6), with: [0, 0, 0, 0, 0, 0x0c])
            }
            system[sales ? "oi-3-flag" : "oi-5-flag"] = "Y"
            system.setInt(sales ? "s-end-cycle-date" : "bl-end-cycle-date", Int64(closed))
        }
        try file.write(1, system.bytes)
        try file.write(4, balances)
    }

    private static func legacyPassword(_ password: String) -> String {
        let alphabet = Array("CKQUAELSMWYIZJRPBXFVGNODTH")
        var encoded = Array(repeating: Character(" "), count: 4)
        for (index, letter) in password.uppercased().prefix(4).enumerated() {
            guard let original = alphabet.firstIndex(of: letter) else { continue }
            let position = index + 1
            let value = abs(original + 1 + position * position + 3 - 26)
            if value > 0 { encoded[3 - index] = alphabet[value - 1] }
        }
        return String(encoded)
    }

    private func rollLedger(sales: Bool, quarter: Int64, yearEnd: Bool) {
        let name = directory + (sales ? "salesled.dat" : "purchled.dat")
        let layout = sales ? SalesProofRecords.salesLayout : PeriodRecords.purchLayout
        func field(_ name: String) -> String { sales ? "sales-" + name : name }
        for (key, bytes) in store.all(name) {
            var row = Record(layout, bytes: bytes)
            let current = row.int(field("current"))
            if current == 0, row.int(field("last")) == 0, row.int(field("unapplied")) == 0 {
                row.setInt(field("status"), 0)
            }
            if current < 0 {
                row.setInt(field("unapplied"), Cobol.truncate(row.int(field("unapplied")) - current, digits: 10))
                row.setInt(field("current"), 0)
            }
            row.setInt(field("last"), max(0, current))
            if (1...4).contains(quarter) { row.setInt("turnover-q\(quarter)", 0) }
            if yearEnd {
                row.setInt(field("average"), 0)
                row.setInt(field("activety"), 0)
            }
            store.rewrite(name, key: key, data: row.bytes)
        }
    }

    private func rollOpenItems(sales: Bool, ownNumbers: Bool) throws {
        let name = directory + (sales ? "openitm3.dat" : "openitm5.dat")
        let invoices = directory + (sales ? "invoice.dat" : "pinvoice.dat")
        let layout = sales ? PeriodRecords.soiLayout : PeriodRecords.poiLayout
        for (key, data) in store.all(name) {
            var row = Record(layout, bytes: data)
            if row.int("status") == 1 {
                if row.int("type") == 2 && (!sales || !ownNumbers) {
                    removeInvoice(invoices, sales: sales, invoice: row.int("invoice"))
                }
                store.delete(name, key: key)
            } else if row.int("type") == 1 {
                store.delete(name, key: key)
            } else {
                if [5, 6].contains(row.int("type")) { row.setInt("deduct-amt", 0) }
                row["applied"] = "z"
                row.setInt("p-c", 0)
                store.rewrite(name, key: key, data: row.bytes)
            }
        }
        try store.writeRaw(directory + "oisort.wrk", [])
    }

    private func rollValues(sales: Bool, yearEnd: Bool) {
        let path = directory + "value.dat"
        if yearEnd {
            store.deleteFile(path)
            store.createIndexed(path)
        } else {
            for (key, bytes) in store.all(path) {
                var row = Record(PeriodRecords.valueLayout, bytes: bytes)
                guard row.str("system") == (sales ? "S" : "P") else { continue }
                row.setInt("t-last", row.int("t-this"))
                row.setInt("t-this", 0)
                row.setInt("v-last", row.int("v-this"))
                row.setInt("v-this", 0)
                store.rewrite(path, key: key, data: row.bytes)
            }
        }
    }

    private func removeInvoice(_ path: String, sales: Bool, invoice: Int64) {
        let prefix = Array(Cobol.z(invoice, 8).utf8) + (sales ? [0x20] : [])
        let header = prefix + [0]
        if let bytes = store.read(path, key: header) {
            let row = Record(sales ? SalesProofRecords.ihLayout : PeriodRecords.pihLayout, bytes: bytes)
            let lineCount = Int(row.int(sales ? "ih-lines" : "lines"))
            for index in 0...max(0, lineCount) {
                store.delete(path, key: prefix + [UInt8(truncatingIfNeeded: index)])
            }
        } else {
            for index in 1...255 {
                guard store.delete(path, key: prefix + [UInt8(index)]) else { break }
            }
        }
    }

    private func rollInvoices(sales: Bool, closed: Int, retention: Int, ownNumbers: Bool) throws {
        let path = directory + (sales ? "invoice.dat" : "pinvoice.dat")
        let source = store.all(path)
        let targetSize = source.first?.data.count ?? (sales ? 134 : 129)
        let layout = sales ? SalesProofRecords.ihLayout : PeriodRecords.pihLayout
        func name(_ field: String) -> String { sales ? "ih-" + field : field }
        var index = source.startIndex
        while index < source.endIndex {
            let (key, bytes) = source[index]
            index += 1
            var row = Record(layout, bytes: bytes)
            let test = row.int(name("test"))
            let type = row.int(name("type"))
            let status = row.str(name("status"))
            let count = max(0, Int(row.int(name("lines"))))
            let date = sales ? Int(row.int("ih-date")) : 0
            let isSettled = status == "z" || status == "Z"
            let expired = sales && type == 4 && closed - retention > date
            if test == 0 && (expired || (isSettled && ([1, 3].contains(type) || type == 2))) {
                for _ in 0..<min(count, source.endIndex - index) {
                    store.delete(path, key: source[index].key)
                    index += 1
                }
                if expired || type != 2 || (sales && ownNumbers && count == 0 && abs(closed - 92) % 100_000 > date) {
                    store.delete(path, key: key)
                    continue
                }
                row.setInt(name("lines"), 0)
            }
            if test == 0 && isSettled && type < 4 { row[name("day-book-flag")] = "B" }
            var projected = bytes
            let updated = min(projected.count, row.bytes.count)
            projected.replaceSubrange(0..<updated, with: row.bytes.prefix(updated))
            let copied = Array(projected.prefix(min(targetSize, temporaryRecordSize)))
            let output = copied + [UInt8](repeating: 0x20, count: targetSize - copied.count)
            store.rewrite(path, key: key, data: output)
        }
        try store.writeRaw(directory + "work.tmp", [])
    }
}
