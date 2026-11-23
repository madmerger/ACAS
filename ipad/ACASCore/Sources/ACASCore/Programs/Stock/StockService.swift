import Foundation

public struct StockService {
    public struct Item: Identifiable {
        public var code = ""
        public var abbreviation = ""
        public var name = ""
        public var held: Int64 = 0
        public var cost: Int64 = 0
        public var value: Int64 = 0
        public var reorderPoint: Int64 = 0
        public var ordered: Int64 = 0
        public var added: Int64 = 0
        public var deducted: Int64 = 0
        public var id: String { code }

        public init() {}

        init(_ row: Record) {
            code = Cobol.rtrim(row.str("stock-key"))
            abbreviation = Cobol.rtrim(row.str("stock-abrev-key"))
            name = Cobol.rtrim(row.str("stock-desc"))
            held = row.int("stock-held")
            cost = row.int("stock-cost")
            value = row.int("stock-value")
            reorderPoint = row.int("stock-reorder-pnt")
            ordered = row.int("stock-on-order")
            added = row.int("stock-adds")
            deducted = row.int("stock-deducts")
        }
    }

    public enum Failure: Error { case invalidInput, duplicate, missing, hasStockOrOrders, auditRequired, missingRecovery }

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
        if let row = try? record(normalized) { return row }
        if let abbreviation = try? key(normalized, 7),
           let row = records.first(where: { $0.raw("stock-abrev-key") == abbreviation }) {
            return row
        }
        throw Failure.missing
    }

    public func find(_ code: String) throws -> Item { Item(try record(code)) }

    public func save(_ item: Item, editing original: String? = nil) throws {
        let id = try key(item.code.uppercased(), 13)
        let abbreviation = try key(item.abbreviation.uppercased(), 7)
        _ = try key(item.name, 32)
        guard (-999_999...999_999).contains(item.held), (0...99_999_999_999).contains(item.cost),
              (-999_999...999_999).contains(item.reorderPoint),
              (0...99_999_999_999).contains(item.value) else { throw Failure.invalidInput }
        var row = try original.map(record) ?? Record(StockLayout.layout)
        let previous = original == nil ? nil : row.raw("stock-key")
        guard !records.contains(where: {
            $0.raw("stock-key") != previous &&
              ($0.raw("stock-key") == id || $0.raw("stock-abrev-key") == abbreviation)
        }) else { throw Failure.duplicate }
        if original == nil {
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
        row.setInt("stock-held", item.held)
        row.setInt("stock-cost", item.cost)
        row.setInt("stock-reorder-pnt", item.reorderPoint)
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
        var row = try movementRecord(code)
        row.setInt("stock-on-order", quantity)
        row.setInt("stock-back-ordered", backOrdered)
        row.setInt("stock-order-date", Int64(ordered.map(day) ?? 0))
        row.setInt("stock-order-due", Int64(due.map(day) ?? 0))
        store.rewrite(path, key: row.raw("stock-key"), data: row.bytes)
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
