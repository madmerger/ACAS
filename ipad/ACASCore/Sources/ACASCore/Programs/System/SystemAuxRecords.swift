public enum SystemAuxRecords {
    /// initialize default-record: Def-Acs (comp 9(4)v99 × 33 = 132 バイト) は 0、Def-Codes / Def-Vat は空白。残りは空白。
    static func initialDefault() -> [UInt8] {
        [UInt8](repeating: 0, count: 132) + [UInt8](repeating: 0x20, count: 1024 - 132)
    }
    /// move spaces to final-record
    /// INITIALIZE system-record (FD レコード領域)。FILLER と REDEFINES 項目は初期化対象外なので、
    /// FILLER は領域確保時の 0x00 のまま、IRS-Data-Block (filler-dummy4 pic x(128)) と
    /// Order-Entry-Block (filler-Dummy) は空白、File-Status (9 occurs 32) は "0" になる。
    static func initialSystem() -> Record {
        var r = Record(SystemLayout.layout)
        let l = SystemLayout.layout
        let size = l.size
        for f in l.order {
            if case .filler(let n) = f.type, f.offset < size - 256 {
                r.bytes.replaceSubrange(f.offset..<f.offset + n, with: [UInt8](repeating: 0, count: n))
            }
        }
        r.bytes.replaceSubrange(size - 256..<size, with: [UInt8](repeating: 0x20, count: 256))
        let fs = l.offset("file-statuses")
        r.bytes.replaceSubrange(fs..<fs + 32, with: [UInt8](repeating: 0x30, count: 32))
        return r
    }

    static func initialFinal() -> [UInt8] { [UInt8](repeating: 0x20, count: 1024) }
    /// initialize system-record-4: comp-3 s9(8)v99 × 20 は +0 (00000000000c)、filler x(904) は空白
    static func initialRecord4() -> [UInt8] {
        var b: [UInt8] = []
        for _ in 0..<20 { b += [0, 0, 0, 0, 0, 0x0c] }
        return b + [UInt8](repeating: 0x20, count: 1024 - b.count)
    }
}
