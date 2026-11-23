import Foundation

/// 総勘定元帳 (gl020-gl120) 共通: レコード定義 (copybook)、ファイル、日付変換、金額入力。
enum GL {
    // general/fdledger.cob (126 バイト)
    static let ledgerLayout: Layout = {
        let amt = FieldType.comp3(digits: 10, scale: 2, signed: true)
        let l = Layout("ledger-record", [
            ("ledger-nos", .n9(digits: 6, scale: 0, signed: false)),
            ("ledger-pc", .n9(digits: 2, scale: 0, signed: false)),
            ("ledger-type", .n9(digits: 1, scale: 0, signed: false)),
            ("ledger-place", .x(1)),
            ("ledger-level", .n9(digits: 1, scale: 0, signed: false)),
            ("", .filler(5)),
            ("ledger-name", .x(24)),
            ("ledger-balance", amt), ("ledger-last", amt),
            ("ledger-q1", amt), ("ledger-q2", amt), ("ledger-q3", amt), ("ledger-q4", amt),
            ("", .filler(50)),
        ])
        l.redefine("ledger-n", .n9(digits: 4, scale: 0, signed: false), at: 0)
        l.redefine("ledger-s", .n9(digits: 2, scale: 0, signed: false), at: 4)
        l.redefine("ledger-key", .x(8), at: 0)
        return l
    }()

    // copybooks/fdbatch.cob (97 バイト)
    static let batchLayout: Layout = {
        let amt = FieldType.comp3(digits: 11, scale: 2, signed: false)
        let bl = FieldType.native(bytes: 4, signed: true)
        let l = Layout("batch-record", [
            ("ledger", .n9(digits: 1, scale: 0, signed: false)),
            ("batch-nos", .n9(digits: 5, scale: 0, signed: false)),
            ("items", .n9(digits: 2, scale: 0, signed: false)),
            ("batch-status", .n9(digits: 1, scale: 0, signed: false)),
            ("cleared-status", .n9(digits: 1, scale: 0, signed: false)),
            ("bcycle", .n9(digits: 2, scale: 0, signed: false)),
            ("entered", bl), ("proofed", bl), ("posted", bl), ("stored", bl),
            ("input-gross", amt), ("input-vat", amt), ("actual-gross", amt), ("actual-vat", amt),
            ("description", .x(24)),
            ("bdefault", .n9(digits: 2, scale: 0, signed: false)),
            ("convention", .x(2)),
            ("batch-def-ac", .n9(digits: 6, scale: 0, signed: false)),
            ("batch-def-pc", .n9(digits: 2, scale: 0, signed: false)),
            ("batch-def-code", .x(2)),
            ("batch-def-vat", .x(1)),
            ("batch-start", .n9(digits: 5, scale: 0, signed: false)),
        ])
        l.redefine("batch-key", .x(6), at: 0)
        return l
    }()

    // copybooks/fdpost.cob (96 バイト、相対編成)
    static let postingLayout: Layout = {
        let l = Layout("posting-record", [
            ("batch", .n9(digits: 5, scale: 0, signed: false)),
            ("post-number", .n9(digits: 5, scale: 0, signed: false)),
            ("post-code", .x(2)),
            ("post-date", .x(8)),
            ("post-dr", .n9(digits: 6, scale: 0, signed: false)),
            ("dr-pc", .n9(digits: 2, scale: 0, signed: false)),
            ("post-cr", .n9(digits: 6, scale: 0, signed: false)),
            ("cr-pc", .n9(digits: 2, scale: 0, signed: false)),
            ("post-amount", .n9(digits: 10, scale: 2, signed: true)),
            ("post-legend", .x(32)),
            ("vat-ac", .n9(digits: 6, scale: 0, signed: false)),
            ("vat-pc", .n9(digits: 2, scale: 0, signed: false)),
            ("post-vat-side", .x(2)),
            ("vat-amount", .n9(digits: 10, scale: 2, signed: true)),
        ])
        l.redefine("post-key", .x(10), at: 0)
        return l
    }()

    // copybooks/wsdflt.cob: Default-Record (RRN 2)。def-acs comp 9(4)v99 ×33、def-codes xx ×33、def-vat x ×33
    static func defAcs(_ s: Session, _ w: Int) -> Int64 {
        let o = (w - 1) * 4
        return s.defaultRecord[o..<(o + 4)].reduce(Int64(0)) { ($0 << 8) | Int64($1) }
    }
    static func setDefAcs(_ s: Session, _ w: Int, _ v: Int64) {
        let o = (w - 1) * 4
        let t = Cobol.truncate(v, digits: 6, signed: false)
        for i in 0..<4 { s.defaultRecord[o + i] = UInt8((t >> Int64((3 - i) * 8)) & 0xff) }
    }
    static func defCodes(_ s: Session, _ w: Int) -> String {
        let o = 132 + (w - 1) * 2
        return SJIS.decode(s.defaultRecord[o..<(o + 2)])
    }
    static func setDefCodes(_ s: Session, _ w: Int, _ v: String) {
        let o = 132 + (w - 1) * 2
        s.defaultRecord.replaceSubrange(o..<(o + 2), with: SJIS.encode(v, size: 2))
    }
    static func defVat(_ s: Session, _ w: Int) -> String {
        let o = 198 + (w - 1)
        return SJIS.decode(s.defaultRecord[o..<(o + 1)])
    }
    static func setDefVat(_ s: Session, _ w: Int, _ v: String) {
        let o = 198 + (w - 1)
        s.defaultRecord.replaceSubrange(o..<(o + 1), with: SJIS.encode(v, size: 1))
    }
    /// initialize default-record
    static func initDefaults(_ s: Session) {
        var b = [UInt8](repeating: 0, count: 132) + [UInt8](repeating: 0x20, count: 99)
        b += Array(s.defaultRecord.dropFirst(231))
        s.defaultRecord = b
    }

    // ファイル (wsnames.cob: file-5 ledger.dat, file-6 posting.dat, file-7 batch.dat, file-2 archive.dat)
    static func ledgerFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "ledger.dat", layout: ledgerLayout, keyOffset: 0, keyLength: 8)
    }
    static func batchFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "batch.dat", layout: batchLayout, keyOffset: 0, keyLength: 6)
    }
    static func postingFile(_ s: Session) -> RelativeFile {
        RelativeFile(s.store, path: s.ledgers + "posting.dat", recordSize: postingLayout.size)
    }
    static func archiveFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "archive.dat", layout: postingLayout, keyOffset: 0, keyLength: 10)
    }
    static var prt1: String { "prt-1" }
    static func printPath(_ s: Session) -> String { s.ledgers + "prt-1" }

    static func key(_ nos: Int64, _ pc: Int64) -> [UInt8] { Array((Cobol.z(nos, 6) + Cobol.z(pc, 2)).utf8) }
    static func batchKey(_ ledger: Int64, _ nos: Int64) -> [UInt8] { Array((Cobol.z(ledger, 1) + Cobol.z(nos, 5)).utf8) }

    /// zz070-convert-date: to-day を Date-Form の形式へ
    static func zz070(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Maps04.format(s.toDay, dateForm: Int(s.sys.int("date-form")))
    }
    /// zz060-convert-date: バイナリ日付を Date-Form の形式へ (不正は空白)
    static func zz060(_ s: Session, _ bin: Int) -> String {
        if bin <= 0 { return Cobol.x("", 10) }
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Maps04.format(Maps04.toDate(bin), dateForm: Int(s.sys.int("date-form")))
    }
    /// zz050-validate-date: Date-Form 形式の入力を UK 形式へ直し、バイナリ日付 (不正 0) を返す
    static func zz050(_ s: Session, _ test: String) -> (uk: String, bin: Int) {
        let t = Maps04.normalized(test)
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let uk = Common.toUK(s, t)
        return (uk, Maps04.toBinary(uk))
    }

    /// accept from lines (端末は 24 行固定)
    static let lines = 24

    /// 画面右上の "at hh:mm:ss" 等で使う時刻 hh:mm:ss
    static func hhmmss(_ s: Session) -> String { s.timeHHMMSS }

    /// 帳票 1 行 (write print-record [after n]) を追記する。
    static func writePrint(_ s: Session, _ line: String, after: Int = 1) {
        GLPrint.write(s, line, after: after)
    }
}

/// print-file (line sequential "prt-1")。GnuCOBOL の WRITE ... AFTER n / AFTER PAGE を再現する。
enum GLPrint {
    static func path(_ s: Session) -> String { s.ledgers + "prt-1" }
    /// OPEN OUTPUT
    static func open(_ s: Session) { s.store.writeRaw(path(s), []) }
    static func close(_ s: Session) { s.onReport?(path(s)) }
    /// WRITE print-record AFTER n LINES (line sequential: 先に改行 n 個、その後レコード本体。AFTER 指定があると末尾改行なし)
    static func write(_ s: Session, _ line: String, after: Int) {
        var out = [UInt8](repeating: 0x0a, count: max(after, 0))
        out += SJIS.encode(Cobol.rtrim(line), size: Cobol.rtrim(line).utf8.count > 0 ? encodedCount(Cobol.rtrim(line)) : 0)
        s.store.appendRaw(path(s), out)
    }
    /// WRITE print-record AFTER PAGE (改ページ 0x0c の後にレコード)
    static func writePage(_ s: Session, _ line: String) {
        let t = Cobol.rtrim(line)
        s.store.appendRaw(path(s), [0x0c] + SJIS.encode(t, size: encodedCount(t)))
    }
    /// WRITE print-record (AFTER/BEFORE なし: レコード + 改行)
    static func writePlain(_ s: Session, _ line: String) {
        let t = Cobol.rtrim(line)
        s.store.appendRaw(path(s), SJIS.encode(t, size: encodedCount(t)) + [0x0a])
    }
    static func encodedCount(_ t: String) -> Int {
        var n = 0
        for ch in t { n += ch.isASCII ? 1 : (String(ch).data(using: .shiftJIS)?.count ?? 1) }
        return n
    }
}

/// common/maps99.cbl: エラー表示 (error.txt)。エラー番号は `s.shared["error-code"]` で受け取る。
enum GLMaps99 {
    /// error.txt: 番号 → (severity, response, error-line)
    static let table: [Int: (String, String, Int)] = [
        1: ("T", "L", 0), 2: ("T", "A", 24), 3: ("W", "W", 23), 4: ("W", "R", 23), 5: ("W", "W", 23), 6: ("W", "W", 23),
        7: ("W", "W", 23), 8: ("W", "W", 23), 9: ("W", "W", 23), 10: ("T", "A", 23), 11: ("T", "A", 23), 12: ("T", "A", 24),
        13: ("T", "A", 23), 14: ("W", "A", 23), 15: ("S", "S", 24), 16: ("W", "W", 23), 17: ("T", "A", 23), 18: ("W", "W", 24),
        19: ("T", "A", 23), 20: ("W", "W", 23), 21: ("W", "W", 23), 22: ("W", "W", 23), 23: ("T", "A", 23), 24: ("W", "W", 23),
        25: ("T", "A", 23), 26: ("T", "A", 23), 27: ("T", "W", 23), 28: ("T", "W", 5), 29: ("T", "W", 23), 30: ("T", "W", 5),
        31: ("T", "W", 5), 32: ("W", "R", 23), 33: ("T", "W", 23), 45: ("S", "S", 24), 99: ("T", "A", 23),
    ]

    static func run(_ s: Session) throws {
        let c = s.console
        let code = (s.shared["error-code"] as? Int) ?? 0
        var lin = GL.lines - 1
        s.termCode = 0
        var serv = "T"
        var mess = s.t("maps99.not_found")
        var wait = true
        if let e = table[code] {
            serv = e.0
            mess = s.t("maps99.e" + Cobol.z(code, 3))
            if e.2 != 0 { lin = e.2 > 19 ? GL.lines - (24 - e.2) : e.2 }
            wait = e.1 == "T" || (e.0 == "S" && e.1 == "S")
            if !wait {
                c.display(serv + "-" + Cobol.z(code, 3) + " " + Cobol.x(mess, 50), at: lin, 1, color: 4)
                if e.0 == "T" { s.termCode = 9 }
                return
            }
        }
        c.display(serv + "-" + Cobol.z(code, 3) + " " + Cobol.x(mess, 50), at: lin, 1, color: 4)
        _ = try c.accept(at: GL.lines, 79, size: 1)
    }
}
