import Foundation

extension StockService {
    public struct AuditReport {
        public let additions: Int
        public let deductions: Int
    }

    public func generateAuditReport(date: Date) throws -> AuditReport {
        try store.transaction {
            guard let bytes = settings.read(1) else { throw Failure.auditRequired }
            var system = Record(SystemLayout.layout, bytes: bytes)
            guard system.int("stk-audit-used") == 1 else { throw Failure.auditRequired }
            let data = store.readRaw(directory + "staudit.dat") ?? []
            let size = 104
            guard data.count.isMultiple(of: size) else { throw Failure.invalidInput }
            let rows = stride(from: 0, to: data.count, by: size).map { Array(data[$0..<$0 + size]) }
            let additions = rows.filter { [0x31, 0x34].contains($0[0]) }
            let deductions = rows.filter { [0x32, 0x33, 0x35].contains($0[0]) }
            let totals = [additions, deductions].map { group in group.reduce(Int64(0)) { $0 + Self.auditNumber($1[89..<99]) } }
            let clock = context.calendar.dateComponents([.hour, .minute], from: date)
            let printed = Maps04.format(Maps04.toDate(day(date)), dateForm: Int(system.int("date-form"))) + " "
                + Cobol.z(clock.hour ?? 0, 2) + ":" + Cobol.z(clock.minute ?? 0, 2)
            let batch = "Batch " + Pic.edit("zz9", value: system.int("stk-audit-no"), scale: 0)
            let heading = SJIS.encode(system.str("usera"), size: 61)
                + SJIS.encode(batch, size: 55) + SJIS.encode(printed, size: 16)
            let pageLines = max(13, Int(system.int("page-lines")))
            let first = Self.auditBytes(additions, receiving: true, heading: heading, totals: totals, pageLines: pageLines)
            let second = Self.auditBytes(deductions, receiving: false, heading: heading, totals: totals, pageLines: pageLines)
            try store.writeRaw(directory + "audit-additions.prt", first)
            try store.writeRaw(directory + "audit-deductions.prt", second)
            try store.writeRaw(directory + "prt-1", second)
            system.setInt("stk-activity-rep-run", 1)
            try settings.write(1, system.bytes)
            return AuditReport(additions: additions.count, deductions: deductions.count)
        }
    }

    private static func auditNumber(_ field: ArraySlice<UInt8>) -> Int64 {
        let value = field.reduce(Int64(0)) { $0 * 10 + Int64($1 & 0x0f) }
        return (field.last ?? 0) & 0x40 != 0 ? -value : value
    }

    private static func auditBytes(_ rows: [[UInt8]], receiving: Bool, heading: [UInt8],
                                   totals: [Int64], pageLines: Int) -> [UInt8] {
        let title = receiving ? "Additions Stock Audit Report" : "Deductions Stock Audit Report"
        let headings = "Proc. Date Stock Number  Description                         Qty    Price    Stock Value    "
            + (receiving ? "Source/PO.no." : "Source/Inv.no.")
        var data: [UInt8] = []
        var line = 99
        var page = 0
        func append(_ bytes: [UInt8], separator: UInt8 = 0x0a) {
            data += bytes + [separator]
        }
        func headers() {
            page += 1
            if page > 1 { data.append(0x0c) }
            append(SJIS.encode(Cobol.x("ST020 (3.01.29)", 55) + Cobol.x(title, 69)
                + "Page " + Pic.edit("zz9", value: Int64(page), scale: 0), size: 132))
            append(heading)
            append([])
            append(SJIS.encode(headings, size: 132))
            append(SJIS.encode("", size: 132))
            line = 5
        }
        for row in rows {
            if page == 0 || line > pageLines { headers() }
            let quantity = Pic.edit("z(6)9-", value: auditNumber(row[73..<79]), scale: 0)
            let cost = receiving ? Pic.edit("z(6)9.99-", value: auditNumber(row[79..<89]), scale: 4) : Cobol.x("", 11)
            let change = Pic.edit("z(5),zz9.99-", value: auditNumber(row[89..<99]), scale: 2)
            let number = String(decoding: row[1..<9], as: UTF8.self)
            let source: String
            switch row[0] {
            case 0x33: source = "Invoicing/" + number
            case 0x34: source = "Purchasing/" + number
            case 0x35: source = "Credit note/" + number + " for " + String(decoding: row[9..<17], as: UTF8.self)
            default: source = ""
            }
            let detail = Array(row[62..<72]) + [0x20] + Array(row[17..<30]) + [0x20] + Array(row[30..<62])
            append(detail + SJIS.encode(quantity + cost + change + "   " + source, size: 132 - detail.count))
            line += 1
        }
        if page == 0 { headers() }
        append([])
        append([])
        let amounts = [(0, " Total Additions   ", totals[0]), (0, " Total Deductions  ", totals[1]),
                       (19, "-------------- ", 0), (0, " Total Changes     ", totals[0] + totals[1]),
                       (19, "============== ", 0)]
        for (indent, label, amount) in amounts {
            let value = indent == 0 ? Pic.edit("zzz,zzz,zz9.99", value: amount, scale: 2) : ""
            append(SJIS.encode(Cobol.x("", 55 + indent) + label + value, size: 132))
        }
        return data
    }
}
