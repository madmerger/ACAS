import Foundation

extension StockService {
    public enum Direction { case receipt, issue }

    private var movementReportPath: String { directory + "prt-1" }

    public func prepareMovementEntry() throws {
        try store.transaction {
            guard store.exists(path) else { return }
            let audit = directory + "staudit.dat"
            if let settingBytes = settings.read(1) {
                var system = Record(SystemLayout.layout, bytes: settingBytes)
                if system.int("stk-audit-used") == 1 {
                    if !store.exists(audit) { try store.writeRaw(audit, []) }
                    var statuses = system.raw("file-statuses")
                    if statuses[9] != 0x31 {
                        statuses[9] = 0x31
                        system.setRaw("file-statuses", statuses)
                        try settings.write(1, system.bytes)
                    }
                }
            }
            try store.writeRaw(movementReportPath, [])
        }
    }

    public func move(_ direction: Direction, code: String, quantity: Int64, price: Int64 = 0,
                     valueOverride: Int64? = nil, date: Date, codeOnly: Bool = false) throws -> Item {
        try store.transaction {
            try applyMovement(direction, code: code, quantity: quantity, price: price,
                              valueOverride: valueOverride, date: date, codeOnly: codeOnly)
        }
    }

    private func applyMovement(_ direction: Direction, code: String, quantity: Int64, price: Int64,
                               valueOverride: Int64?, date: Date, codeOnly: Bool) throws -> Item {
        guard quantity != 0, (-999_998...999_998).contains(quantity), (0...99_999_999).contains(price),
              valueOverride.map({ (0...9_999_999_999).contains($0) }) ?? true else { throw Failure.invalidInput }
        var system = settings.read(1).map { Record(SystemLayout.layout, bytes: $0) } ?? Record(SystemLayout.layout)
        let format = Int(system.int("date-form"))
        let processingDay = day(date)
        let processing = Maps04.format(Maps04.toDate(processingDay), dateForm: format)
        let month = Maps04.dateOfInteger(processingDay).month
        guard processingDay > 0, (1...12).contains(month) else {
            throw Failure.invalidInput
        }
        let receiving = direction == .receipt
        var row = try codeOnly ? record(code) : movementRecord(code)
        let held = row.int("stock-held")
        let work = row.int("stock-work-in-progress")
        let cost = row.int("stock-cost")
        let next = held + (receiving ? quantity : -quantity)
        guard row.str("stock-services-flag") != "Y", (-999_999...999_999).contains(next),
              receiving || next >= 0 else { throw Failure.invalidInput }
        let change = Cobol.truncate(receiving ? quantity * price : -quantity * cost / 100, digits: 10)
        var dates = ""
        if receiving {
            var value = change + Cobol.truncate((held + work) * cost / 100, digits: 10)
            if abs(value) >= 10_000_000_000 { value = 9_999_999_999 }
            if system.int("stk-averaging") != 1, let valueOverride, valueOverride != 0 { value = valueOverride }
            if next != 0 {
                let rounded = (abs(value) * 100 + abs(next) / 2) / abs(next)
                row.setInt("stock-cost", Cobol.truncate(rounded, digits: 10))
            }
            let balance = row.int("stock-on-order") - abs(quantity)
            let back = max(0, Cobol.truncate(row.int("stock-back-ordered") + balance, digits: 6))
            let ordered = Int(row.int("stock-order-date"))
            let due = Int(row.int("stock-order-due"))
            let late = due == 0 ? 0 : (day(today) - due) % 1000
            dates = Cobol.x(ordered == 0 ? "" : Maps04.format(Maps04.toDate(ordered), dateForm: format), 13)
                + Cobol.x(due == 0 ? "" : Maps04.format(Maps04.toDate(due), dateForm: format), 13)
                + (late == 0 ? "   " : Pic.edit("zz9", value: Int64(abs(late)), scale: 0))
                + Cobol.x(late > 0 ? "Days Late" : late < 0 ? "Early" : "", 10)
            if back == 0 {
                row.setInt("stock-order-date", 0)
                row.setInt("stock-order-due", 0)
            }
            row.setInt("stock-last-actual-cost", price)
            row.setInt("stock-value", abs(value))
            row.setInt("stock-on-order", 0)
            row.setInt("stock-back-ordered", back)
        } else {
            let value = abs((next + work) * cost / 100)
            row.setInt("stock-value", value >= 100_000_000_000 ? 9_999_999_999 : value)
        }
        let totals = receiving ? ["stock-adds", "stock-td-adds-\(month)"] : ["stock-deducts", "stock-td-deds-\(month)"]
        for total in totals {
            row.setInt(total, Cobol.truncate(row.int(total) + quantity, digits: 8, signed: false))
        }
        row.setInt("stock-held", next)
        if system.int("stk-audit-used") == 1 {
            let type = receiving ? "1" : "2"
            var bytes = Array((type + "0000000000000000").utf8)
            bytes += row.raw("stock-key") + row.raw("stock-desc") + Array(processing.utf8)
            bytes += [quantity < 0 ? 0x31 : 0x30]
            for (number, width) in [(quantity, 6), (receiving ? price * 100 : cost, 10), (change, 10)] {
                var field = Array(Cobol.z(abs(number) % Cobol.pow10(width), width).utf8)
                if number < 0 { field[width - 1] |= 0x40 }
                bytes += field
            }
            bytes += Array(Cobol.z(system.int("stk-audit-no"), 5).utf8)
            try store.appendRaw(directory + "staudit.dat", bytes)
            var statuses = system.raw("file-statuses")
            statuses[9] = 0x31
            system.setRaw("file-statuses", statuses)
            system.setInt("stk-activity-rep-run", 0)
            try settings.write(1, system.bytes)
        }
        guard store.rewrite(path, key: row.raw("stock-key"), data: row.bytes) else { throw Failure.missing }
        let current = context.calendar.dateComponents([.hour, .minute], from: today)
        let printed = Maps04.format(Maps04.toDate(day(today)), dateForm: format) + " "
            + Cobol.z(current.hour ?? 0, 2) + ":" + Cobol.z(current.minute ?? 0, 2)
        try store.writeRaw(movementReportPath, Self.movementReport(receiving: receiving, company: system.str("usera"),
            printed: printed, processing: processing, row: row, quantity: quantity, price: price, change: change,
            dates: dates))
        return Item(row)
    }

    private static func movementReport(receiving: Bool, company: String, printed: String, processing: String,
                                       row: Record, quantity: Int64, price: Int64, change: Int64,
                                       dates: String) -> [UInt8] {
        let title = receiving ? "Stock Addition Report" : "Stock Deduction Report"
        let first = Cobol.x("ST020 (3.01.29)", 55) + Cobol.x(title, 69) + "Page   1"
        let second = SJIS.encode(company, size: 116) + SJIS.encode(printed, size: 16)
        let headings = Cobol.x("Proc. Date", 11)
            + Cobol.x("Stock Number  Description                         Qty", 57)
            + Cobol.x(receiving ? "Price" : "", 5) + "    Stock Value    "
            + (receiving ? "Order Date    Date Due     Order Status" : "")
        let detail = SJIS.encode(processing, size: 11) + row.raw("stock-key") + [0x20] + row.raw("stock-desc")
        let values = Pic.edit("z(6)9-", value: quantity, scale: 0)
            + (receiving ? Pic.edit("z(6)9.99-", value: price, scale: 2) : Cobol.x("", 11))
            + Pic.edit("z(5),zz9.99-", value: change, scale: 2) + "   " + dates
        let lines = [
            SJIS.encode(first, size: 132), second, [], SJIS.encode(Cobol.x("", 78) + "Change in", size: 132),
            SJIS.encode(headings, size: 132), SJIS.encode("", size: 132),
            detail + SJIS.encode(values, size: 132 - detail.count),
        ]
        return lines.flatMap { $0 + [0x0a] }
    }
}
