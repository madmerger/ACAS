import Foundation
import SQLite3

/// 端末内 DB (SQLite)。レガシーの索引編成/相対編成/順編成ファイルを、同じファイル名・同じレコードバイト列で保持する。
public final class FileStore: @unchecked Sendable {
    public struct DatabaseError: Swift.Error {
        public let code: Int32
        public let message: String
    }

    public enum SeedError: Swift.Error, Equatable {
        case indexedFileNotInserted(String)
        case indexedRecordNotInserted(file: String, key: String)
    }

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String = ":memory:") throws {
        do {
            let result = sqlite3_open(path, &db)
            guard result == SQLITE_OK else { throw databaseError(result) }
            try exec("PRAGMA journal_mode=WAL")
            try exec("CREATE TABLE IF NOT EXISTS files(name TEXT PRIMARY KEY, kind TEXT NOT NULL, data BLOB)")
            try exec("CREATE TABLE IF NOT EXISTS records(file TEXT NOT NULL, key BLOB NOT NULL, data BLOB NOT NULL, PRIMARY KEY(file, key)) WITHOUT ROWID")
        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    func transaction<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try operation()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw databaseError(result) }
    }

    private func run<T>(_ sql: String, _ binds: [Any?], _ body: (OpaquePointer) -> T) -> T {
        do { return try withStatement(sql, binds, body) }
        catch { fatalError("SQLite: \(error) [\(sql)]") }
    }

    private func databaseError(_ code: Int32) -> DatabaseError {
        let message = db.flatMap { sqlite3_errmsg($0) } ?? sqlite3_errstr(code)
        return DatabaseError(code: code, message: message.map { String(cString: $0) } ?? "")
    }

    private func withStatement<T>(_ sql: String, _ binds: [Any?], _ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &st, nil)
        guard prepared == SQLITE_OK, let stmt = st else { throw databaseError(prepared) }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            let n = Int32(i + 1)
            let result: Int32
            switch b {
            case let s as String: result = sqlite3_bind_text(stmt, n, s, -1, Self.transient)
            case let d as [UInt8]:
                if d.isEmpty { result = sqlite3_bind_zeroblob(stmt, n, 0) }
                else { result = d.withUnsafeBytes { sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(d.count), Self.transient) } }
            default: result = sqlite3_bind_null(stmt, n)
            }
            guard result == SQLITE_OK else { throw databaseError(result) }
        }
        return try body(stmt)
    }

    private func blob(_ stmt: OpaquePointer, _ col: Int32) -> [UInt8] {
        let n = Int(sqlite3_column_bytes(stmt, col))
        guard n > 0, let p = sqlite3_column_blob(stmt, col) else { return [] }
        return [UInt8](UnsafeRawBufferPointer(start: p, count: n))
    }

    // MARK: ファイル

    public func exists(_ file: String) -> Bool {
        run("SELECT 1 FROM files WHERE name=?", [file]) { sqlite3_step($0) == SQLITE_ROW }
    }

    public func kind(_ file: String) -> String? {
        run("SELECT kind FROM files WHERE name=?", [file]) {
            sqlite3_step($0) == SQLITE_ROW ? String(cString: sqlite3_column_text($0, 0)) : nil
        }
    }

    /// 索引ファイルを (無ければ) 作成
    public func createIndexed(_ file: String) {
        _ = try? insertIndexedFile(file)
    }

    private func insertIndexedFile(_ file: String) throws -> Bool {
        try insertRow("INSERT OR IGNORE INTO files(name, kind, data) VALUES(?, 'indexed', NULL)", [file])
    }

    private func insertRow(_ sql: String, _ binds: [Any?]) throws -> Bool {
        try withStatement(sql, binds) {
            let result = sqlite3_step($0)
            guard result == SQLITE_DONE else { throw databaseError(result) }
            return sqlite3_changes(db) == 1
        }
    }

    public func deleteFile(_ file: String) {
        _ = run("DELETE FROM files WHERE name=?", [file]) { sqlite3_step($0) }
        _ = run("DELETE FROM records WHERE file=?", [file]) { sqlite3_step($0) }
    }

    public func fileNames() -> [String] {
        run("SELECT name FROM files ORDER BY name", []) { st in
            var out: [String] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(String(cString: sqlite3_column_text(st, 0))) }
            return out
        }
    }

    // MARK: 順編成・相対編成・帳票 (バイト列)

    public func readRaw(_ file: String) -> [UInt8]? {
        run("SELECT data FROM files WHERE name=? AND kind='raw'", [file]) {
            sqlite3_step($0) == SQLITE_ROW ? self.blob($0, 0) : nil
        }
    }

    public func writeRaw(_ file: String, _ data: [UInt8]) throws {
        try withStatement("INSERT INTO files(name, kind, data) VALUES(?, 'raw', ?) ON CONFLICT(name) DO UPDATE SET kind='raw', data=excluded.data", [file, data]) {
            let result = sqlite3_step($0)
            guard result == SQLITE_DONE else { throw databaseError(result) }
        }
    }

    public func appendRaw(_ file: String, _ data: [UInt8]) throws {
        try writeRaw(file, (readRaw(file) ?? []) + data)
    }

    // MARK: 索引編成

    public func read(_ file: String, key: [UInt8]) -> [UInt8]? {
        run("SELECT data FROM records WHERE file=? AND key=?", [file, key]) {
            sqlite3_step($0) == SQLITE_ROW ? self.blob($0, 0) : nil
        }
    }

    /// 追加。重複キーなら false (FILE STATUS 22)
    @discardableResult
    public func write(_ file: String, key: [UInt8], data: [UInt8]) -> Bool {
        do {
            _ = try insertIndexedFile(file)
            return try insertIndexedRecord(file, key: key, data: data)
        } catch {
            return false
        }
    }

    private func insertIndexedRecord(_ file: String, key: [UInt8], data: [UInt8]) throws -> Bool {
        try insertRow("INSERT OR IGNORE INTO records(file, key, data) VALUES(?,?,?)", [file, key, data])
    }

    /// 更新。無ければ false (FILE STATUS 23)
    @discardableResult
    public func rewrite(_ file: String, key: [UInt8], data: [UInt8]) -> Bool {
        run("UPDATE records SET data=? WHERE file=? AND key=?", [data, file, key]) {
            sqlite3_step($0) == SQLITE_DONE && sqlite3_changes(self.db) == 1
        }
    }

    @discardableResult
    public func delete(_ file: String, key: [UInt8]) -> Bool {
        run("DELETE FROM records WHERE file=? AND key=?", [file, key]) {
            sqlite3_step($0) == SQLITE_DONE && sqlite3_changes(self.db) == 1
        }
    }

    /// キー昇順の全レコード
    public func all(_ file: String) -> [(key: [UInt8], data: [UInt8])] {
        run("SELECT key, data FROM records WHERE file=? ORDER BY key", [file]) { st in
            var out: [(key: [UInt8], data: [UInt8])] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append((self.blob(st, 0), self.blob(st, 1))) }
            return out
        }
    }

    /// `key` 以上 (inclusive) / より大きい最初のレコード
    public func seek(_ file: String, key: [UInt8], inclusive: Bool) -> (key: [UInt8], data: [UInt8])? {
        let op = inclusive ? ">=" : ">"
        return run("SELECT key, data FROM records WHERE file=? AND key \(op) ? ORDER BY key LIMIT 1", [file, key]) {
            sqlite3_step($0) == SQLITE_ROW ? (self.blob($0, 0), self.blob($0, 1)) : nil
        }
    }

    public func count(_ file: String) -> Int {
        run("SELECT COUNT(*) FROM records WHERE file=?", [file]) {
            sqlite3_step($0) == SQLITE_ROW ? Int(sqlite3_column_int64($0, 0)) : 0
        }
    }

    // MARK: ベースライン

    public func clearAll() throws {
        try exec("DELETE FROM files"); try exec("DELETE FROM records")
    }

    /// シード JSON (ベースライン) を読み込み、DB を置き換える
    public func load(seed: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: seed) as? [String: Any],
              let files = root["files"] as? [String: [String: Any]] else {
            throw NSError(domain: "ACAS", code: 1, userInfo: [NSLocalizedDescriptionKey: "seed"])
        }
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN")
        do {
            try clearAll()
            for (name, f) in files {
                if f["type"] as? String == "indexed" {
                    // GnuCOBOL の副キー索引 (.1 .2) は主ファイルから導出するため保持しない
                    if name.hasSuffix(".1") || name.hasSuffix(".2") { continue }
                    guard try insertIndexedFile(name) else { throw SeedError.indexedFileNotInserted(name) }
                    for pair in (f["records"] as? [[String]] ?? []) where pair.count == 2 {
                        guard try insertIndexedRecord(name, key: Self.bytes(hex: pair[0]), data: Self.bytes(hex: pair[1])) else {
                            throw SeedError.indexedRecordNotInserted(file: name, key: pair[0])
                        }
                    }
                } else {
                    try writeRaw(name, Self.bytes(hex: f["hex"] as? String ?? ""))
                }
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public static func bytes(hex: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(hex.count / 2)
        var hi: UInt8?
        for c in hex.utf8 {
            let v: UInt8
            switch c {
            case 48...57: v = c - 48
            case 97...102: v = c - 87
            case 65...70: v = c - 55
            default: continue
            }
            if let h = hi { out.append(h << 4 | v); hi = nil } else { hi = v }
        }
        return out
    }

    public static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    /// 論理スナップショット: ファイル名 → (キー HEX → データ HEX)。同一性テストのレコード差分比較に使う。
    public func snapshot() -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for name in fileNames() {
            if kind(name) == "indexed" {
                var m: [String: String] = [:]
                for r in all(name) { m[Self.hex(r.key)] = Self.hex(r.data) }
                out[name] = m
            } else {
                out[name] = ["": Self.hex(readRaw(name) ?? [])]
            }
        }
        return out
    }
}

/// COBOL の索引編成ファイル操作 (FILE STATUS 付き) を FileStore 上で再現する。
public final class IndexedFile {
    public let store: FileStore
    public let path: String
    public let layout: Layout
    public let keyOffset: Int
    public let keyLength: Int
    public var status = "00"
    private var cursor: [UInt8]?
    private var cursorInclusive = true
    public private(set) var isOpen = false

    public init(_ store: FileStore, path: String, layout: Layout, keyOffset: Int = 0, keyLength: Int) {
        self.store = store; self.path = path; self.layout = layout
        self.keyOffset = keyOffset; self.keyLength = keyLength
    }

    public func key(of rec: Record) -> [UInt8] { Array(rec.bytes[keyOffset..<(keyOffset + keyLength)]) }

    /// OPEN INPUT / I-O。存在しなければ 35。
    @discardableResult
    public func open(create: Bool = false) -> String {
        if !store.exists(path) {
            if create { store.createIndexed(path) } else { status = "35"; return status }
        }
        isOpen = true; cursor = nil; cursorInclusive = true
        status = "00"; return status
    }

    /// OPEN OUTPUT: 空で作り直す
    public func openOutput() {
        store.deleteFile(path); store.createIndexed(path)
        isOpen = true; cursor = nil; cursorInclusive = true; status = "00"
    }

    public func close() { isOpen = false; status = "00" }

    /// READ ... KEY (無ければ 23)
    public func read(key: [UInt8]) -> Record? {
        guard let d = store.read(path, key: key) else { status = "23"; return nil }
        cursor = key; cursorInclusive = false
        status = "00"
        return Record(layout, bytes: d)
    }

    public func read(key: String) -> Record? { read(key: SJIS.encode(key, size: keyLength)) }

    /// START ... KEY NOT < key
    @discardableResult
    public func start(notLessThan key: [UInt8]) -> Bool {
        guard store.seek(path, key: key, inclusive: true) != nil else { status = "23"; return false }
        cursor = key; cursorInclusive = true; status = "00"; return true
    }

    public func startFirst() { cursor = nil; cursorInclusive = true; status = "00" }

    /// READ NEXT (末尾で 10)
    public func readNext() -> Record? {
        let found: (key: [UInt8], data: [UInt8])?
        if let c = cursor { found = store.seek(path, key: c, inclusive: cursorInclusive) }
        else { found = store.seek(path, key: [], inclusive: true) }
        guard let r = found else { status = "10"; return nil }
        cursor = r.key; cursorInclusive = false; status = "00"
        return Record(layout, bytes: r.data)
    }

    /// WRITE (重複 22)
    @discardableResult
    public func write(_ rec: Record) -> String {
        status = store.write(path, key: key(of: rec), data: rec.bytes) ? "00" : "22"
        return status
    }

    /// REWRITE (無し 23)
    @discardableResult
    public func rewrite(_ rec: Record) -> String {
        status = store.rewrite(path, key: key(of: rec), data: rec.bytes) ? "00" : "23"
        return status
    }

    /// DELETE (無し 23)
    @discardableResult
    public func delete(key: [UInt8]) -> String {
        status = store.delete(path, key: key) ? "00" : "23"
        return status
    }

    public func allRecords() -> [Record] { store.all(path).map { Record(layout, bytes: $0.data) } }
}

/// 相対編成ファイル (system.dat 等)。固定長レコードを RRN (1 始まり) で読み書きする。
/// GnuCOBOL の相対編成は各レコードの前に size_t (8 バイト) のレコード長を置く。
public final class RelativeFile {
    public let store: FileStore
    public let path: String
    public let recordSize: Int
    public var status = "00"
    public init(_ store: FileStore, path: String, recordSize: Int) {
        self.store = store; self.path = path; self.recordSize = recordSize
    }
    private var slot: Int { recordSize + 8 }
    public var exists: Bool { store.exists(path) }

    public func read(_ rrn: Int) -> [UInt8]? {
        guard let d = store.readRaw(path) else { status = "35"; return nil }
        let off = (rrn - 1) * slot
        guard rrn >= 1, off + slot <= d.count else { status = "23"; return nil }
        let len = d[off..<(off + 8)].enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        if len == 0 { status = "23"; return nil }
        status = "00"
        return Array(d[(off + 8)..<(off + slot)])
    }

    /// WRITE / REWRITE (必要ならファイルを拡張)
    public func write(_ rrn: Int, _ data: [UInt8]) throws {
        var d = store.readRaw(path) ?? []
        let off = (rrn - 1) * slot
        if d.count < off + slot { d += [UInt8](repeating: 0, count: off + slot - d.count) }
        var len = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 { len[i] = UInt8((recordSize >> (8 * i)) & 0xff) }
        var rec = Array(data.prefix(recordSize))
        if rec.count < recordSize { rec += [UInt8](repeating: 0x20, count: recordSize - rec.count) }
        d.replaceSubrange(off..<(off + slot), with: len + rec)
        try store.writeRaw(path, d)
        status = "00"
    }

    public var recordCount: Int { (store.readRaw(path)?.count ?? 0) / slot }
}
