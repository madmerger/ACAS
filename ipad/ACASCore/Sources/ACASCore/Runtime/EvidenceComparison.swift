import Foundation

public struct RecordChange: Codable, Equatable, Comparable {
    public let file: String
    public let key: String
    public let before: String?
    public let after: String?

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.file, lhs.key) < (rhs.file, rhs.key)
    }
}

public enum EvidenceComparison {
    public typealias Snapshot = [String: [String: String]]

    public static func snapshot(_ store: FileStore) -> Snapshot {
        var snapshot: Snapshot = [:]
        for file in store.fileNames() {
            if file.hasSuffix("/system.dat") {
                let relative = RelativeFile(store, path: file, recordSize: 1024)
                for index in 0..<relative.recordCount {
                    guard let bytes = relative.read(index + 1) else { continue }
                    snapshot[file, default: [:]][String(format: "%08d", index + 1)] = FileStore.hex(bytes)
                }
            } else if store.kind(file) == "indexed" {
                for (key, data) in store.all(file) {
                    snapshot[file, default: [:]][FileStore.hex(key)] = FileStore.hex(data)
                }
            }
        }
        return snapshot
    }

    public static func diff(before: Snapshot, after: Snapshot) -> [RecordChange] {
        Set(before.keys).union(after.keys).flatMap { file -> [RecordChange] in
            let old = before[file] ?? [:], new = after[file] ?? [:]
            return Set(old.keys).union(new.keys).compactMap { key in
                guard old[key] != new[key] else { return nil }
                return RecordChange(file: file, key: key, before: old[key], after: new[key])
            }
        }.sorted()
    }

    public static func reportsAgree(_ expected: [String: String], in store: FileStore) -> Bool {
        expected.allSatisfy { path, hex in
            store.readRaw(path).map(FileStore.hex) == hex
        }
    }
}
