import Foundation

extension BookkeepingService {
    public static let accountArchiveName = "coa-archived.txt"
    static let accountArchiveSizeLimit = 99_999 * (37 + 2)

    public static func readAccountArchive(at url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= accountArchiveSizeLimit {
            let count = min(65_536, accountArchiveSizeLimit + 1 - data.count)
            guard let chunk = try file.read(upToCount: count), !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw Failure.accountArchiveTooLarge
    }

    public func exportAccountArchive() throws -> (data: Data, count: Int) {
        var data: [UInt8] = []
        var count = 0
        for (_, bytes) in store.all(accountsPath) {
            let row = Record(BookkeepingRecords.nlLayout, bytes: bytes)
            guard row.str("type") == "O" else { continue }
            var line = [UInt8(ascii: "T")] + row.raw("key")
            line += Array((row.int("sub-nominal") == 0 ? "O" : "S").utf8)
            line += row.raw("name") + row.raw("ac")
            data += line.reversed().drop(while: { $0 == 0x20 }).reversed()
            data.append(0x0a)
            count += 1
        }
        try store.writeRaw(directory + Self.accountArchiveName, data)
        return (Data(data), count)
    }

    public func importAccountArchive(_ data: Data) throws -> Int {
        guard data.count <= Self.accountArchiveSizeLimit else { throw Failure.accountArchiveTooLarge }
        if data.contains(where: { $0 >= 0x80 }), String(data: data, encoding: .utf8) != nil {
            throw Failure.invalidInput
        }
        let lines = data.split(separator: 0x0a)
        guard !lines.isEmpty else { throw Failure.invalidInput }
        var records: [[UInt8]: [UInt8]] = [:]
        for line in lines {
            let bytes = Array(line.last == 0x0d ? line.dropLast() : line)
            guard (12...37).contains(bytes.count), bytes.first == 0x54,
                  let owner = Int(String(decoding: bytes[1..<6], as: UTF8.self)),
                  let child = Int(String(decoding: bytes[6..<11], as: UTF8.self)),
                  (1...99999).contains(owner), (0...99999).contains(child), owner != child else {
                throw Failure.invalidInput
            }
            var row = Record(BookkeepingRecords.nlLayout)
            row.setRaw("key", Array(bytes[1..<11]))
            row["type"] = "O"
            let tail = bytes.dropFirst(12) + Array(repeating: UInt8(ascii: " "), count: 37 - bytes.count)
            let name = Array(tail.prefix(24))
            guard String(data: Data(name), encoding: .shiftJIS) != nil else { throw Failure.invalidInput }
            row.setRaw("name", name)
            row.setRaw("ac", Array(tail.suffix(1)))
            guard records.updateValue(row.bytes, forKey: accountKey(owner, child)) == nil else { throw Failure.duplicateAccount }
            if child != 0 {
                row.setRaw("key", accountKey(child))
                row.setInt("pointer", Int64(owner))
                row["type"] = "S"
                guard records.updateValue(row.bytes, forKey: accountKey(child)) == nil else { throw Failure.duplicateAccount }
            }
        }
        try store.transaction {
            for (key, _) in store.all(accountsPath) {
                guard store.delete(accountsPath, key: key) else { throw Failure.invalidInput }
            }
            for (key, bytes) in records {
                guard store.write(accountsPath, key: key, data: bytes) else { throw Failure.duplicateAccount }
            }
        }
        return lines.count
    }
}
