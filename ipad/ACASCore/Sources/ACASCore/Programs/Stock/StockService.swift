import Foundation

public struct StockService {
    public struct Item: Identifiable {
        public var code = ""
        public var abbreviation = ""
        public var name = ""
        public var location = ""
        public var held: Int64 = 0
        public var cost: Int64 = 0
        public var retail: Int64 = 0
        public var value: Int64 = 0
        public var reorderPoint: Int64 = 0
        public var reorderQuantity: Int64 = 0
        public var ordered: Int64 = 0
        public var added: Int64 = 0
        public var deducted: Int64 = 0
        public var id: String { code }

        public init() {}

        init(_ row: Record) {
            code = Cobol.rtrim(row.str("stock-key"))
            abbreviation = Cobol.rtrim(row.str("stock-abrev-key"))
            name = Cobol.rtrim(row.str("stock-desc"))
            location = Cobol.rtrim(row.str("stock-location"))
            held = row.int("stock-held")
            cost = row.int("stock-cost")
            retail = row.int("stock-retail")
            value = row.int("stock-value")
            reorderPoint = row.int("stock-reorder-pnt")
            reorderQuantity = row.int("stock-std-reorder")
            ordered = row.int("stock-on-order")
            added = row.int("stock-adds")
            deducted = row.int("stock-deducts")
        }
    }

    public enum Failure: Error {
        case invalidInput, duplicate, missing, hasStockOrOrders, auditRequired, missingRecovery, invalidAnalysisRecordLength
    }

    let context: BusinessContext
    let directory = "ledgers/acas/"
    var path: String { directory + "stockctl.dat" }
    var store: FileStore { context.store }
    var settings: RelativeFile { RelativeFile(store, path: directory + "system.dat", recordSize: 1024) }
    var records: [Record] { store.all(path).map { Record(StockLayout.layout, bytes: $0.data) } }

    public init(_ context: BusinessContext) { self.context = context }
    public var today: Date { context.now() }
    public var items: [Item] { records.map(Item.init) }

    func key(_ text: String, _ width: Int) throws -> [UInt8] {
        let encoded = SJIS.encode(text, size: width)
        guard !text.isEmpty, Cobol.rtrim(SJIS.decode(encoded[...])) == text else { throw Failure.invalidInput }
        return encoded
    }

    func record(_ code: String) throws -> Record {
        guard let data = store.read(path, key: try key(code.uppercased(), 13)) else { throw Failure.missing }
        return Record(StockLayout.layout, bytes: data)
    }

    func movementRecord(_ code: String) throws -> Record {
        let normalized = code.uppercased()
        if let abbreviation = try? key(normalized, 7),
           let row = records.first(where: { $0.raw("stock-abrev-key") == abbreviation }) {
            return row
        }
        return try record(normalized)
    }

    public func find(_ code: String) throws -> Item { Item(try record(code)) }

    public func validateItemEdit() throws {
        let analysis = directory + "analysis.dat"
        guard let kind = store.kind(analysis) else { return }
        let recordSize = 36
        guard kind == "indexed", store.all(analysis).allSatisfy({ $0.data.count == recordSize })
        else { throw Failure.invalidAnalysisRecordLength }
    }

    public func save(_ item: Item, editing original: String? = nil) throws {
        if original != nil { try validateItemEdit() }
        let id = try key(item.code.uppercased(), 13)
        let abbreviation = try key(item.abbreviation.uppercased(), 7)
        _ = try key(item.name, 32)
        if !item.location.isEmpty { _ = try key(item.location, 10) }
        guard (-999_999...999_999).contains(item.held), (0...99_999_999_999).contains(item.cost),
              (-999_999...999_999).contains(item.reorderPoint),
              (-999_999...999_999).contains(item.reorderQuantity), (0...999_999_999).contains(item.retail),
              (0...99_999_999_999).contains(item.value) else { throw Failure.invalidInput }
        var row = try original.map(record) ?? Record(StockLayout.layout)
        let previous = original == nil ? nil : row.raw("stock-key")
        guard !records.contains(where: {
            $0.raw("stock-key") != previous &&
              ($0.raw("stock-key") == id || $0.raw("stock-abrev-key") == abbreviation)
        }) else { throw Failure.duplicate }
        if original == nil {
            row["stock-services-flag"] = "N"
            row.setRaw("filler-1", [UInt8](repeating: 0, count: 8))
            row.setRaw("filler-2", [UInt8](repeating: 0, count: 15))
        }
        var value = item.value
        if value == 0, item.held != 0, item.cost != 0, let raw = settings.read(1) {
            let system = Record(SystemLayout.layout, bytes: raw)
            if system.int("stk-averaging") == 1 {
                let work = system.int("stk-manu-used") == 1 ? row.int("stock-work-in-progress") : 0
                let opening = Cobol.truncate(item.held * item.cost / 100, digits: 11, signed: false)
                value = Cobol.truncate((opening * 100 + work * item.cost) / 100, digits: 11, signed: false)
            }
        }
        row.setInt("stock-value", value)
        row.setRaw("stock-key", id)
        row.setRaw("stock-abrev-key", abbreviation)
        row["stock-desc"] = item.name
        row["stock-location"] = item.location
        row.setInt("stock-held", item.held)
        row.setInt("stock-cost", item.cost)
        row.setInt("stock-retail", item.retail)
        row.setInt("stock-reorder-pnt", item.reorderPoint)
        row.setInt("stock-std-reorder", item.reorderQuantity)
        if id == previous {
            guard store.rewrite(path, key: id, data: row.bytes) else { throw Failure.missing }
        } else {
            guard store.write(path, key: id, data: row.bytes) else { throw Failure.duplicate }
            if let previous { store.delete(path, key: previous) }
        }
    }

    public func remove(_ code: String) throws {
        let row = try record(code)
        guard ["stock-held", "stock-on-order", "stock-back-ordered"].allSatisfy({ row.int($0) == 0 })
        else { throw Failure.hasStockOrOrders }
        guard store.delete(path, key: row.raw("stock-key")) else { throw Failure.missing }
    }

    public func renumber(_ code: String, to replacement: String) throws {
        var row = try record(code)
        let old = row.raw("stock-key")
        let new = try key(replacement.uppercased(), 13)
        guard new != old else { return }
        row.setRaw("stock-key", new)
        guard store.write(path, key: new, data: row.bytes) else { throw Failure.duplicate }
        store.delete(path, key: old)
    }

    func day(_ date: Date) -> Int {
        let parts = context.calendar.dateComponents([.year, .month, .day], from: date)
        return Maps04.integerOfDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public func order(_ code: String, quantity: Int64, backOrdered: Int64, ordered: Date?, due: Date?) throws {
        guard (0...999_998).contains(quantity), (0...999_998).contains(backOrdered)
        else { throw Failure.invalidInput }
        var row = try code.count <= 7 ? movementRecord(code) : record(code)
        guard row.str("stock-services-flag") != "Y" else { throw Failure.invalidInput }
        row.setInt("stock-on-order", quantity)
        row.setInt("stock-back-ordered", backOrdered)
        row.setInt("stock-order-date", Int64(ordered.map(day) ?? 0))
        row.setInt("stock-order-due", Int64(due.map(day) ?? 0))
        guard store.rewrite(path, key: row.raw("stock-key"), data: row.bytes) else { throw Failure.missing }
    }

    public func confirmOrder(_ code: String, quantity: Int64, backOrdered: Int64,
                             ordered: Date?, due: Date?, date: Date) throws {
        try store.transaction {
            guard let bytes = settings.read(1) else { throw Failure.invalidInput }
            var system = Record(SystemLayout.layout, bytes: bytes)
            if system.int("stk-audit-used") == 1 {
                let audit = directory + "staudit.dat"
                var statuses = system.raw("file-statuses")
                if statuses[9] != 0x31 {
                    if !store.exists(audit) { try store.writeRaw(audit, []) }
                    statuses[9] = 0x31
                    system.setRaw("file-statuses", statuses)
                    try settings.write(1, system.bytes)
                }
            }
            try order(code, quantity: quantity, backOrdered: backOrdered, ordered: ordered, due: due)
            let row = try movementRecord(code)
            let form = Int(system.int("date-form"))
            func displayDate(_ value: Date?) -> String {
                Cobol.x(value.map { Maps04.format(Maps04.toDate(day($0)), dateForm: form) } ?? "", 13)
            }
            let time = context.calendar.dateComponents([.hour, .minute], from: context.now())
            let header = Cobol.x("ST020 (3.01.29)", 55) + Cobol.x("Stock Orders Update", 69) + "Page   1"
            let company = system.raw("usera")
            let dateTime = String(displayDate(date).prefix(10)) + " " + Cobol.z(time.hour ?? 0, 2) + ":" + Cobol.z(time.minute ?? 0, 2)
            let detail = Array(repeating: UInt8(0x20), count: 11) + row.raw("stock-key") + [0x20]
                + row.raw("stock-desc")
                + SJIS.encode(Pic.edit("z(6)9-", value: quantity, scale: 0)
                    + Cobol.x("", 2) + Pic.edit("z(5)9", value: backOrdered, scale: 0) + Cobol.x("", 19)
                    + displayDate(ordered) + displayDate(due), size: 75)
            let report = SJIS.encode(header, size: 132) + [10] + company
                + Array(repeating: 0x20, count: 116 - company.count) + Array(dateTime.utf8) + [10, 10]
                + SJIS.encode(Cobol.x("", 78) + "Change in", size: 132) + [10]
                + SJIS.encode("           Stock Number  Description                         Qty    B'Qty                   Order Date    Date Due", size: 132) + [10]
                + SJIS.encode("", size: 132) + [10] + detail + [10]
            try store.writeRaw(directory + "prt-1", report)
        }
    }

    public func closePeriod(current: Bool, yearly: Bool) throws {
        guard current || yearly else { return }
        guard let raw = settings.read(1), Record(SystemLayout.layout, bytes: raw).int("stk-activity-rep-run") == 1
        else { throw Failure.auditRequired }
        for var row in records {
            if current {
                for total in ["stock-adds", "stock-deducts", "stock-wip-adds", "stock-wip-deds"] {
                    row.setInt(total, 0)
                }
            }
            if yearly {
                for month in 1...12 {
                    for type in ["adds", "deds", "wip-adds", "wip-deds"] {
                        row.setInt("stock-td-\(type)-\(month)", 0)
                    }
                }
            }
            store.rewrite(path, key: row.raw("stock-key"), data: row.bytes)
        }
    }

    public func rebuild(recovery: Bool) throws {
        let temp = directory + "tmp-stock.dat"
        let source: [[UInt8]]
        if recovery {
            guard let data = store.readRaw(temp), data.count.isMultiple(of: StockLayout.layout.size)
            else { throw Failure.missingRecovery }
            source = stride(from: 0, to: data.count, by: StockLayout.layout.size)
                .map { Array(data[$0..<$0 + StockLayout.layout.size]) }
        } else {
            guard store.exists(path) else { throw Failure.missing }
            source = records.map {
                var row = $0
                row.setInt("stock-value", Cobol.truncate(row.int("stock-held") * row.int("stock-cost") / 100,
                                                          digits: 11, signed: false))
                return row.bytes
            }
            try store.writeRaw(temp, source.flatMap { $0 })
        }
        let keys = source.map { Array($0.prefix(13)) }
        guard Set(keys).count == keys.count else { throw Failure.duplicate }
        store.deleteFile(path)
        store.createIndexed(path)
        for (id, bytes) in zip(keys, source) { store.write(path, key: id, data: bytes) }
    }
}
