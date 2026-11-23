import Foundation

extension StockService {
    public func printMasterReport() throws {
        let system = Record(SystemLayout.layout, bytes: settings.read(1) ?? Record(SystemLayout.layout).bytes)
        let pageLimit = Int(system.int("page-lines"))
        let format = Int(system.int("date-form"))
        let date = today
        let time = context.calendar.dateComponents([.hour, .minute], from: date)
        let dateAndTime = Maps04.format(Maps04.toDate(day(date)), dateForm: format) + " "
            + Cobol.z(time.hour ?? 0, 2) + ":" + Cobol.z(time.minute ?? 0, 2)
        var output: [UInt8] = []
        var line = 99
        var page = 0

        func appendBytes(_ bytes: [UInt8], after: Int) {
            output += Array(repeating: 0x0a, count: after) + bytes.prefix(132)
                + Array(repeating: 0x20, count: max(0, 132 - bytes.count))
        }
        func append(_ text: String, after: Int) {
            appendBytes(SJIS.encode(text, size: 132), after: after)
        }

        func heading() {
            page += 1
            if page > 1 { output.append(0x0c) }
            append(Cobol.x("ST010 (3.01.37)", 57) + Cobol.x("Stock File Report", 67) + "Page "
                   + Pic.edit("zz9", value: Int64(page), scale: 0), after: 0)
            let company = system.raw("usera")
            appendBytes(company + Array(repeating: 0x20, count: 116 - company.count)
                        + Array(dateAndTime.utf8), after: 1)
            if page > 1 { append("", after: 1) }
            append("<------ Stock ------> Supplier  Location     Unit      Unit        Value    Number"
                   + " <- ReOrder -> <------- Date ------>  Quantity On", after: page == 1 ? 2 : 1)
            append("Abrev   Number         Number               Price      Cost        in Stk   in Stk"
                   + "  Point    Qty   Ordered     Due      Order  B/Ord", after: 1)
            line = 5
        }

        let rows = records
        for row in rows {
            if line > pageLimit { heading() }
            if line > 5 { append(String(repeating: "-", count: 132), after: 1) }
            appendBytes(masterReportDetail(row, dateForm: format), after: line > 5 ? 1 : 2)
            appendBytes(masterReportDescription(row), after: 1)
            line += 3

            if row.str("stock-services-flag") == "Y" {
                append("Services only Product", after: 1)
                line += 1
            } else {
                let bundle = row.int("stock-construct-bundle")
                let wip = row.int("stock-work-in-progress")
                let construction = row.int("stock-under-construction")
                let item = row.str("stock-construct-item")
                if bundle != 0 || wip != 0 || construction != 0 || !Cobol.rtrim(item).isEmpty {
                    append("Construction Bundle :" + Pic.edit("z(6)", value: bundle, scale: 0)
                           + "  WIP :" + Pic.edit("z(6)", value: wip, scale: 0)
                           + "  Under Construction :" + Pic.edit("z(6)", value: construction, scale: 0)
                           + " For Constructed Item : " + item, after: 1)
                    line += 1
                }
            }
        }
        if line > pageLimit - 3 { heading() }
        let count = Pic.edit("zzz,zzz,zz9", value: Int64(rows.count), scale: 0)
        append(" Total Stock Records " + count.trimmingCharacters(in: .whitespaces), after: 3)
        try store.writeRaw(directory + "prt-1", output + [0x0a])
    }

    func masterReportDetail(_ row: Record, dateForm: Int) -> [UInt8] {
        func number(_ picture: String, _ field: String, scale: Int = 0) -> String {
            Pic.edit(picture, value: row.int("stock-" + field), scale: scale)
        }
        func date(_ field: String, width: Int) -> String {
            let value = Int(row.int("stock-order-" + field))
            return Cobol.x(value == 0 ? "" : Maps04.format(Maps04.toDate(value), dateForm: dateForm), width)
        }
        var cost = number("z(6)9.9999", "cost", scale: 4)
        if cost.hasSuffix("00") { cost = String(cost.dropLast(2)) + "  " }
        let merchandise = row.str("stock-services-flag") != "Y"
        let value = merchandise ? number("zzzzz,zz9.99", "value", scale: 2) + number("z(6)9", "held")
            + number("z(6)9", "reorder-pnt") + number("z(6)9b", "std-reorder") : Cobol.x("", 34)
        let orders = merchandise ? number("z(6)9", "on-order") + number("z(6)9", "back-ordered") : Cobol.x("", 14)
        var detail: [UInt8] = []
        for field in ["abrev-key", "key", "supplier-p1", "location"] {
            detail += row.raw("stock-" + field) + [0x20]
        }
        let amounts = number("z(6)9.99", "retail", scale: 2) + cost + value
        return detail + Array((amounts + date("date", width: 11) + date("due", width: 10) + orders).utf8)
    }

    func masterReportDescription(_ row: Record) -> [UInt8] {
        var detail = Array("     Description: ".utf8) + row.raw("stock-desc") + Array("     ".utf8)
        let suppliers = ["stock-supplier-p2", "stock-supplier-p3"].map { row.raw($0) }
        if suppliers.contains(where: { $0.contains(where: { $0 != 0x20 }) }) {
            detail += Array("Secondary Suppliers".utf8)
            for (index, supplier) in suppliers.enumerated() where supplier.contains(where: { $0 != 0x20 }) {
                detail += Array(" \(index + 1): ".utf8) + supplier
            }
            detail += [0x20, 0x20]
        }
        let sales = row.raw("stock-sa-code")
        let purchases = row.raw("stock-pa-code")
        if sales.contains(where: { $0 != 0x20 }) { detail += Array("SA Code: ".utf8) + sales.dropFirst() + [0x20, 0x20] }
        if purchases.contains(where: { $0 != 0x20 }) { detail += Array("PA Code: ".utf8) + purchases.dropFirst() }
        if row.int("stock-pre-sales") != 0 {
            detail += Array(("  Pre Sales :" + Pic.edit("z(6)", value: row.int("stock-pre-sales"), scale: 0)).utf8)
        }
        return detail
    }
}
