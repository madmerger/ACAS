public struct LedgerArchiveSort {
    public enum Error: Swift.Error { case missingArchive, invalidArchive }

    static let sortedPath = "archives/workarc.tmp"
    private let store: FileStore

    public init(_ context: BusinessContext) { store = context.store }

    public func prepare() throws {
        try store.transaction {
            guard let bytes = store.readRaw(LedgerCycleClose.archivePath) else { throw Error.missingArchive }
            let layout = LedgerCycleClose.archiveLayout
            let width = layout.size + 1
            guard bytes.count.isMultiple(of: width) else { throw Error.invalidArchive }
            let rows = try stride(from: 0, to: bytes.count, by: width).map { start in
                let end = start + layout.size
                guard bytes[end] == 10 else { throw Error.invalidArchive }
                let record = Record(layout, bytes: Array(bytes[start..<end]))
                return (offset: start, key: ["account", "branch", "batch", "sequence"].map { record.int($0) })
            }
            let sorted = rows.sorted { lhs, rhs in
                lhs.key == rhs.key ? lhs.offset < rhs.offset : lhs.key.lexicographicallyPrecedes(rhs.key)
            }.flatMap { bytes[$0.offset..<($0.offset + width)] }
            try store.writeRaw(Self.sortedPath, sorted)
        }
    }
}
