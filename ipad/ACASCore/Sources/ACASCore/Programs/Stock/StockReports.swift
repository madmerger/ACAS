import Foundation

extension StockService {
    public enum Report: String, CaseIterable {
        case valuation, activity, reorder, history, listing

        fileprivate var legacyTitle: String {
            switch self {
            case .valuation: "Stock Valuation Report"
            case .activity: "Stock Activity Report"
            case .reorder: "Stock Re-Order Report"
            case .history: "Stock History Report"
            case .listing: "Stock Report"
            }
        }
    }

    public enum ReportSelection: String, CaseIterable {
        case all, current, toDate, understocked, outOfStock, onOrder

        public static func options(for report: Report) -> [Self] {
            switch report {
            case .activity: [.all, .current, .toDate]
            case .reorder: [.all, .understocked, .outOfStock, .onOrder]
            default: [.all]
            }
        }
    }

    public func printReport(_ report: Report, date: Date, selection: ReportSelection = .all,
                            byAbbreviation: Bool = false, from: String = "", through: String = "") throws {
        guard ReportSelection.options(for: report).contains(selection) else { throw Failure.invalidInput }
        let system = Record(SystemLayout.layout, bytes: settings.read(1) ?? Record(SystemLayout.layout).bytes)
        let format = Int(system.int("date-form"))
        let pageLimit = Int(system.int("page-lines"))
        let manufacture = system.int("stk-manu-used") == 1
        let averaging = system.int("stk-averaging") == 1
        let currentPeriod = system.str("stk-period-cur")
        let currentTitle = currentPeriod == "Q" ? "Quarter" : currentPeriod == "W" ? "Week" : "Month"
        let periodTitle = system.str("stk-period-dat") == "Q" ? "Quarter" : "Year"
        let width = byAbbreviation ? 7 : 13
        let lower = from.isEmpty ? nil : try key(from.uppercased(), width)
        let upper = through.isEmpty ? nil : try key(through.uppercased(), width)
        if let lower, let upper, upper.lexicographicallyPrecedes(lower) { throw Failure.invalidInput }
        let useAbbreviation = byAbbreviation || (lower == nil && upper == nil)
        let orderKey = useAbbreviation ? "stock-abrev-key" : "stock-key"
        let time = context.calendar.dateComponents([.hour, .minute], from: today)
        func dateLabel(_ value: Int) -> String {
            Maps04.format(Maps04.toDate(value), dateForm: format)
        }
        func yearTotal(_ row: Record, _ field: String) -> Int64 {
            (1...12).reduce(0) { $0 + row.int("stock-td-\(field)-\($1)") }
        }
        let rows = records.sorted { $0.raw(orderKey).lexicographicallyPrecedes($1.raw(orderKey)) }.filter { row in
            let key = row.raw(orderKey)
            if let lower, key.lexicographicallyPrecedes(lower) { return false }
            if let upper, upper.lexicographicallyPrecedes(key) { return false }
            switch selection {
            case .all: return true
            case .current: return ["adds", "deducts", "wip-adds", "wip-deds"].contains { row.int("stock-" + $0) != 0 }
            case .toDate: return ["adds", "deds", "wip-adds", "wip-deds"].contains { yearTotal(row, $0) != 0 }
            case .understocked: return row.str("stock-services-flag") != "Y" && row.int("stock-held") <= row.int("stock-reorder-pnt")
            case .outOfStock: return row.str("stock-services-flag") != "Y" && row.int("stock-held") == 0
            case .onOrder: return row.str("stock-services-flag") != "Y" &&
                ["on-order", "back-ordered", "order-date", "order-due"].contains { row.int("stock-" + $0) != 0 }
            }
        }
        var output: [UInt8] = []
        var page = 0
        var line = 99
        var total: Int64 = 0
        var anyWip = false
        func edit(_ picture: String, _ number: Int64, _ scale: Int = 0) -> String {
            Pic.edit(picture, value: number, scale: scale)
        }
        func bytes(_ fields: [(String, Int)], _ row: Record) -> [UInt8] {
            fields.flatMap { name, width in
                let data = row.raw("stock-" + name).prefix(width)
                return Array(data) + Array(repeating: 0x20, count: width - data.count)
            }
        }
        func appendBytes(_ value: [UInt8], after: Int = 1) {
            output += Array(repeating: 0x0a, count: after) + value.prefix(132)
                + Array(repeating: 0x20, count: max(0, 132 - value.count))
        }
        func append(_ value: String, after: Int = 1) {
            appendBytes(SJIS.encode(value, size: 132), after: after)
        }
        func activityTail(_ added: Int64, _ deducted: Int64, _ pastAdded: Int64, _ pastDeducted: Int64) -> String {
            edit("z(5)9", abs(added)) + edit("z(5)9", abs(deducted)) + edit("z(5)9-", added - deducted)
                + edit("z(5)9", abs(pastAdded)) + edit("z(5)9", abs(pastDeducted)) + edit("z(5)9-", pastAdded - pastDeducted)
        }
        func headings() {
            page += 1
            if page > 1 { output.append(0x0c) }
            let inset = report == .history ? 1 : report == .listing ? 5 : 0
            append(Cobol.x("ST030 (3.01.22)", 16) + Cobol.x("", 39) + Cobol.x(Cobol.x("", inset) + report.legacyTitle, 42)
                   + Cobol.x("", 27) + "Page " + edit("zz9", Int64(page)), after: 0)
            let qualifier: String
            switch selection {
            case .all: qualifier = "All"
            case .current: qualifier = "Active in Current " + currentTitle
            case .toDate: qualifier = "Active in " + periodTitle + " to Date"
            case .understocked: qualifier = "Understocked"
            case .outOfStock: qualifier = "Not in Stock"
            case .onOrder: qualifier = "On Order"
            }
            let scope = lower == nil && upper == nil
                ? qualifier + " Items"
                : qualifier + " Items from " + (from.isEmpty ? "Start" : from.uppercased())
                    + " through " + (through.isEmpty ? "End" : through.uppercased())
            let headingDate = dateLabel(day(date)) + " " + Cobol.z(time.hour ?? 0, 2) + ":" + Cobol.z(time.minute ?? 0, 2)
            let scopeInset = max(0, (132 - scope.utf8.count) / 2 - 40)
            appendBytes(system.raw("usera") + Array(repeating: 0x20, count: 40 - system.raw("usera").count)
                        + SJIS.encode(Cobol.x(Cobol.x("", scopeInset) + scope, 76) + headingDate, size: 92))
            let labels: [String]
            switch report {
            case .valuation:
                labels = [
                    "<------- Stock ------>                                      Average       Replace     Stock     \(manufacture ? "WIP" : "   ")     Value in    Retail",
                    "Abrev    Number         Description                           Cost          Cost        Qty     \(manufacture ? "Qty" : "   ")     Stockroom    Price",
                ]
            case .activity:
                let current = currentPeriod == "Q" ? "< Current Quarter >" : currentPeriod == "W" ? "<- Current Week -->" : "<- Current Month ->"
                let past = periodTitle == "Quarter" ? "< Quarter to Date >" : "<- Year to Date -->"
                labels = [
                    Cobol.x("<------ Stock ------>                                  Current  Retail", 72)
                        + Cobol.x(averaging ? " Average" : "   Unit", 13) + Cobol.x(averaging ? " Stock" : "", 9) + current + past,
                    Cobol.x("Abrev     Number      Description                       Stock   Price      Cost", 86)
                        + Cobol.x(averaging ? "Value" : "", 11) + "Add   Ded    Net   Add   Ded    Net",
                ]
            case .reorder:
                labels = [
                    "<------ Stock ------>                                     Supp    Stock < ReOrder >  Unit     On   <------- Date ------>    Bk   WIP",
                    "Abrev     Number     Flg Description                      Number   Qty    Pnt   Qty  Cost    Order  Ordered      Due       Ord   Qty",
                ]
            case .history:
                labels = [
                    "<------ Stock ------> Description          This <----------------------------- History for the Year ------------------------------->",
                    Cobol.x("Abrev   Number", 43) + currentTitle,
                ]
            case .listing:
                labels = [
                    "<------ Stock ------> Supplier  Location     Unit      Unit        Value    Number <- ReOrder -> <------- Date ------>  Quantity On",
                    "Abrev   Number         Number               Price      Cost        in Stk   in Stk  Point    Qty   Ordered     Due      Order  B/Ord",
                ]
            }
            append(labels[0], after: 2)
            append(labels[1])
            append("")
            line = 6
        }
        for row in rows {
            if line > pageLimit { headings() }
            func value(_ field: String) -> Int64 { row.int("stock-" + field) }
            let identity = [("abrev-key", 8), ("key", 14)]
            let fields = identity + [("desc", 33)]
            let after = 1
            switch report {
            case .valuation:
                var cost = edit("zzzzz,zz9.9999", value("cost"), 4)
                if cost.hasSuffix("00") { cost = String(cost.dropLast(2)) + "  " }
                let amounts = cost + edit("zzzzz,zz9.99", value("last-actual-cost"), 2)
                    + edit("z(7)9", abs(value("held")))
                    + (manufacture ? edit("z(7)9", abs(value("work-in-progress"))) : Cobol.x("", 8))
                    + edit("zzz,zzz,zz9.99", value("value"), 2) + edit("zzzzz,zz9.99", value("retail"), 2)
                appendBytes(bytes([("abrev-key", 9), ("key", 15), ("desc", 33)], row) + Array(amounts.utf8), after: after)
                total = Cobol.truncate(total + value("value"), digits: 11)
            case .activity:
                let cost = averaging ? edit("zzz,zz9.99", value("cost") / 100, 2) + edit("zzzzz,zz9.99", value("value"), 2)
                    : edit("zzz,zz9.99", value("last-actual-cost"), 2) + Cobol.x("", 12)
                let activity = activityTail(value("adds"), value("deducts"), yearTotal(row, "adds"), yearTotal(row, "deds"))
                let amounts = edit("zzz,zz9", abs(value("held"))) + edit("zzz,zz9.99", value("retail"), 2) + cost + activity
                appendBytes(bytes(fields, row) + Array(amounts.utf8), after: after)
                let wip = [value("work-in-progress"), value("wip-adds"), value("wip-deds"),
                           yearTotal(row, "wip-adds"), yearTotal(row, "wip-deds")]
                if manufacture && wip.contains(where: { $0 != 0 }) {
                    append(Cobol.x("", 50) + Cobol.x("WIP:", 5) + edit("zzz,zz9", abs(wip[0]))
                           + Cobol.x("", 15) + "Work in Progress:" + activityTail(wip[1], wip[2], wip[3], wip[4]))
                    line += 1
                }
            case .reorder:
                let flag = row.str("stock-services-flag") == "Y" ? " " : value("held") < value("reorder-pnt") ? "U" : value("held") == 0 ? "0" : " "
                let cost = averaging ? value("cost") / 100 : value("last-actual-cost")
                let quantities = ["held", "reorder-pnt", "std-reorder"].map { edit("z(5)9", abs(value($0))) }.joined()
                let dates = [("order-date", 11), ("order-due", 10)].map { field, width in
                    Cobol.x(value(field) == 0 ? "" : dateLabel(Int(value(field))), width)
                }.joined()
                let amounts = quantities + edit("z(5)9.99", cost, 2) + edit("z(5)9b", abs(value("on-order")))
                    + dates + edit("z(5)9", abs(value("back-ordered")))
                    + (manufacture ? edit("z(6)", abs(value("work-in-progress"))) : "")
                appendBytes(bytes(identity, row) + Array((flag + "  ").utf8)
                            + bytes([("desc", 33), ("supplier-p1", 7)], row) + Array(amounts.utf8), after: after)
            case .history:
                func months(_ prefix: String) -> String {
                    (1...12).map { edit("-(6)9", value("td-\(prefix)adds-\($0)") + value("td-\(prefix)deds-\($0)")) }.joined()
                }
                let history = " " + edit("-(6)9", value("adds") + value("deducts")) + months("")
                appendBytes(bytes(identity + [("desc", 18)], row) + Array(history.utf8), after: after)
                if manufacture && [value("wip-adds"), value("wip-deds"), yearTotal(row, "wip-adds"), yearTotal(row, "wip-deds")].contains(where: { $0 != 0 }) {
                    append(Cobol.x("", 36) + "WIP: " + edit("-(6)9", value("wip-adds") + value("wip-deds")) + months("wip-"))
                    anyWip = true
                    line += 1
                }
            case .listing:
                if line > 6 { append(String(repeating: "-", count: 132)) }
                appendBytes(masterReportDetail(row, dateForm: format), after: after)
                appendBytes(masterReportDescription(row))
                line += 1
                if row.str("stock-services-flag") == "Y" {
                    append("Services only Product")
                    line += 1
                } else if ["construct-bundle", "work-in-progress", "under-construction"].contains(where: { value($0) != 0 })
                    || !Cobol.rtrim(row.str("stock-construct-item")).isEmpty {
                    append("Construction Bundle :" + edit("z(6)", abs(value("construct-bundle")))
                           + "  WIP :" + edit("z(6)", abs(value("work-in-progress")))
                           + "  Under Construction :" + edit("z(6)", abs(value("under-construction")))
                           + " For Constructed Item : " + row.str("stock-construct-item"))
                    line += 1
                }
            }
            line += 1
        }
        if !rows.isEmpty {
            switch report {
            case .valuation:
                if line > pageLimit - 4 { headings() }
                append(Cobol.x("", 99) + String(repeating: "-", count: 14), after: 2)
                append(Cobol.x("", 86) + Cobol.x("Total Value:", 13) + edit("zzz,zzz,zz9.99", abs(total), 2))
                append(Cobol.x("", 99) + String(repeating: "=", count: 14))
            case .history, .listing:
                if line > pageLimit - (report == .history ? 5 : 3) { headings() }
                let count = edit("zzz,zzz,zz9", Int64(rows.count)).trimmingCharacters(in: .whitespaces)
                append(" Total stock records Printed " + count, after: 3)
                if report == .history && manufacture && !anyWip {
                    append("WIP records were present but none had data", after: 2)
                }
            case .activity, .reorder: break
            }
            output.append(0x0a)
        }
        try store.writeRaw(directory + "prt-1", output)
    }
}
