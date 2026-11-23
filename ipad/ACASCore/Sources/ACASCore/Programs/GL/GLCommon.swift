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
        return (uk, toBinary(uk))
    }

    /// maps04 (日付 → バイナリ)。a-year は数字検査をしないため、数字以外 (空白等) は下位 4 ビットを数字として扱う
    /// (例: 8 桁項目から渡された "23/11/20  " は 2000 年になる)。
    static func toBinary(_ date: String) -> Int {
        let a = Array(SJIS.encode(Maps04.normalized(date), size: 10))
        func isNum(_ r: Range<Int>) -> Bool { a[r].allSatisfy { (0x30...0x39).contains($0) } }
        func val(_ r: Range<Int>) -> Int { a[r].reduce(0) { $0 * 10 + Int($1 & 0x0f) } }
        guard a.filter({ $0 == 0x2f }).count == 2, isNum(0..<2), isNum(3..<5), isNum(6..<8),
              (1...31).contains(val(0..<2)), (1...12).contains(val(3..<5)) else { return 0 }
        guard a[8..<10].allSatisfy({ ($0 & 0x0f) <= 9 }) else { return 0 }
        let y = val(6..<8) * 100 + val(8..<10)
        guard Maps04.validYMD(y, val(3..<5), val(0..<2)) else { return 0 }
        return Maps04.integerOfDate(year: y, month: val(3..<5), day: val(0..<2))
    }

    // 相対編成 posting.dat の補助 (レコード長 8 バイト + 本体)
    static func relRead(_ s: Session, _ rrn: Int) -> [UInt8]? { rrn >= 1 ? postingFile(s).read(rrn) : nil }
    /// WRITE (既にあれば invalid key で false)
    @discardableResult
    static func relWrite(_ s: Session, _ rrn: Int, _ data: [UInt8]) -> Bool {
        guard rrn >= 1 else { return false }
        let f = postingFile(s)
        if f.read(rrn) != nil { return false }
        f.write(rrn, data)
        return true
    }
    static func relRewrite(_ s: Session, _ rrn: Int, _ data: [UInt8]) { if rrn >= 1 { postingFile(s).write(rrn, data) } }
    static func relDelete(_ s: Session, _ rrn: Int) {
        let path = s.ledgers + "posting.dat"
        guard rrn >= 1, var d = s.store.readRaw(path) else { return }
        let slot = postingLayout.size + 8, off = (rrn - 1) * slot
        guard off + slot <= d.count else { return }
        d.replaceSubrange(off..<(off + slot), with: [UInt8](repeating: 0, count: slot))
        s.store.writeRaw(path, d)
    }
    static func relCount(_ s: Session) -> Int { postingFile(s).recordCount }
    /// READ NEXT: rrn より後で最初に存在するレコード
    static func relNext(_ s: Session, after rrn: Int) -> (rrn: Int, data: [UInt8])? {
        let n = relCount(s)
        var r = max(rrn, 0) + 1
        while r <= n {
            if let d = relRead(s, r) { return (r, d) }
            r += 1
        }
        return nil
    }

    /// accept from lines (端末は 24 行固定)
    static let lines = 24

    /// 画面右上の "at hh:mm:ss" 等で使う時刻 hh:mm:ss
    static func hhmmss(_ s: Session) -> String { s.timeHHMMSS }

}

/// print-file (line sequential "prt-1"、レコード長 132)。GnuCOBOL の WRITE ... AFTER/BEFORE ADVANCING を再現する。
/// AFTER n: 改行 n 個 → レコード (行末の改行は次の WRITE か CLOSE で補われる)。BEFORE n: レコード → 改行 n 個。指定なし: レコード → 改行。
enum GLPrint {
    static let recordSize = 132
    static func path(_ s: Session) -> String { s.ledgers + "prt-1" }
    private static func needsNL(_ s: Session) -> Bool { (s.shared["gl.print.needs-nl"] as? Bool) ?? false }
    private static func setNeedsNL(_ s: Session, _ v: Bool) { s.shared["gl.print.needs-nl"] = v }
    private static func record(_ line: String) -> [UInt8] { SJIS.encode(line, size: recordSize) }

    /// OPEN OUTPUT
    static func open(_ s: Session) { s.store.writeRaw(path(s), []); setNeedsNL(s, false) }
    /// OPEN EXTEND
    static func openExtend(_ s: Session) { if !s.store.exists(path(s)) { s.store.writeRaw(path(s), []) }; setNeedsNL(s, false) }
    static func close(_ s: Session) {
        if needsNL(s) { s.store.appendRaw(path(s), [0x0a]); setNeedsNL(s, false) }
        s.onReport?(path(s))
    }
    /// WRITE print-record AFTER n LINES
    static func write(_ s: Session, _ line: String, after: Int) {
        s.store.appendRaw(path(s), [UInt8](repeating: 0x0a, count: max(after, 0)) + record(line))
        setNeedsNL(s, true)
    }
    /// WRITE print-record AFTER PAGE
    static func writePage(_ s: Session, _ line: String) {
        s.store.appendRaw(path(s), [0x0c] + record(line))
        setNeedsNL(s, true)
    }
    /// WRITE print-record BEFORE n LINES
    static func write(_ s: Session, _ line: String, before: Int) {
        var out = needsNL(s) ? [UInt8(0x0a)] : []
        out += record(line) + [UInt8](repeating: 0x0a, count: max(before, 0))
        s.store.appendRaw(path(s), out)
        setNeedsNL(s, false)
    }
    /// WRITE print-record BEFORE PAGE
    static func writeBeforePage(_ s: Session, _ line: String) {
        var out = needsNL(s) ? [UInt8(0x0a)] : []
        out += record(line) + [0x0c]
        s.store.appendRaw(path(s), out)
        setNeedsNL(s, false)
    }
    /// WRITE print-record (ADVANCING 指定なし)
    static func writePlain(_ s: Session, _ line: String) { write(s, line, before: 1) }
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

/// wsmaps03 (u-date / u-bin) と ws-date を持ち、maps04・zz050/zz060/zz070 を再現する (各プログラムの WS に 1 つ)。
final class GLDates {
    let s: Session
    var uDate = Cobol.x("", 10)
    var uBin = 0
    var wsDate = Cobol.x("", 10)
    init(_ s: Session) { self.s = s }

    private func form() -> Int {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Int(s.sys.int("date-form"))
    }
    /// call "maps04": u-bin > 0 なら日付へ展開、そうでなければ u-date を検査してバイナリへ
    func maps04() {
        if uBin > 0 { uDate = Maps04.toDate(uBin); return }
        uDate = Maps04.normalized(uDate)
        let b = GL.toBinary(uDate)
        if b != 0 { uBin = b }
    }
    /// zz050-validate-date: 区切りを正規化した入力値を返す。u-bin = 0 なら不正。
    func zz050(_ test: String) -> String {
        let t = Maps04.normalized(test)
        _ = form()
        wsDate = Common.toUK(s, t)
        uDate = wsDate
        uBin = 0
        maps04()
        return t
    }
    /// zz060-convert-date: u-bin → ws-date (Date-Form 形式)
    func zz060() {
        maps04()
        if uDate.allSatisfy({ $0 == " " }) { wsDate = Cobol.x("", 10); return }
        wsDate = Maps04.format(uDate, dateForm: form())
    }
    /// zz070-convert-date: to-day → ws-date
    func zz070() { wsDate = Maps04.format(s.toDay, dateForm: form()) }
}

extension GL {
    /// レガシーが無限ループに入る箇所 (未オープンのファイルを READ し続ける等) の再現。
    /// 画面はそのまま、キー入力は捨て続け、プログラムからは戻らない (セッション終了でのみ抜ける)。
    static func hang(_ s: Session) throws -> Never {
        while true { _ = try s.console.waitKey() }
    }

    /// DISPLAY 時の表示文字列。制御文字 (レコード域が low-values のまま等) は curses と同じく ^@ 形式になる。
    static func shown(_ raw: [UInt8]) -> String {
        if !raw.contains(where: { $0 < 0x20 }) { return SJIS.decode(raw[...]) }
        var out = ""
        for b in raw { out += b < 0x20 ? "^" + String(UnicodeScalar(b + 0x40)) : String(UnicodeScalar(b)) }
        return out
    }
    static func shown(_ rec: Record, _ name: String) -> String { shown(rec.raw(name)) }

    /// レコード項目への ACCEPT ... UPDATE。項目が low-values を含む場合は ^@ 表示のまま入力させ、触れなかった桁は元のバイトを保つ。
    static func acceptRaw(_ s: Session, _ rec: inout Record, _ name: String, at: Int, numeric: Bool, color: UInt8) throws {
        let raw = rec.raw(name)
        let c = s.console
        guard raw.contains(where: { $0 < 0x20 }) else {
            if numeric {
                let v = try c.accept(at: at, size: raw.count, kind: .numeric, initial: SJIS.decode(raw[...]), options: [.update], color: color)
                rec.setInt(name, Cobol.moveNumeric(v, digits: raw.count, scale: 0))
            } else {
                rec.set(name, try c.accept(at: at, size: raw.count, initial: rec.str(name), options: [.update], color: color))
            }
            return
        }
        let all = shown(raw)
        c.display(all, at: at, color: color)
        let ini = Array(all.prefix(raw.count))
        let r = Array(try c.accept(at: at, size: raw.count, initial: String(ini), options: [.update], color: color))
        var out = raw
        for i in 0..<raw.count where !(r[i] == ini[i] && raw[i] < 0x20) {
            var b = SJIS.encode(String(r[i]), size: 1)[0]
            if numeric && !(0x30...0x39).contains(b) { b = 0x30 }
            out[i] = b
        }
        rec.setRaw(name, out)
    }
}

/// 未オープンのファイルへの READ (状態 47) は invalid key / at end のどちらにもならず、次の文へ進む。
enum GLRead {
    case ok(Record)
    case miss       // invalid key / at end
    case error      // 未オープン: レコード域は変わらない
}

extension IndexedFile {
    func glRead(key: [UInt8]) -> GLRead {
        guard isOpen else { return .error }
        if let r = read(key: key) { return .ok(r) }
        return .miss
    }
    func glNext() -> GLRead {
        guard isOpen else { return .error }
        if let r = readNext() { return .ok(r) }
        return .miss
    }
}

/// gl070/gl071/gl072 の作業ファイル (pretrans.tmp / postrans.tmp: line sequential、70 バイト)
enum GLTrans {
    static let layout = Layout("trans-record", [
        ("batch", .n9(digits: 5, scale: 0, signed: false)),
        ("post", .n9(digits: 5, scale: 0, signed: false)),
        ("code", .x(2)),
        ("date", .x(8)),
        ("ac", .n9(digits: 6, scale: 0, signed: false)),
        ("pc", .n9(digits: 2, scale: 0, signed: false)),
        ("amount", .n9(digits: 10, scale: 2, signed: true)),
        ("legend", .x(32)),
    ])
    static func prePath(_ s: Session) -> String { s.ledgers + "pretrans.tmp" }
    static func postPath(_ s: Session) -> String { s.ledgers + "postrans.tmp" }
    /// line sequential の全レコード (各行を 70 バイトへ空白で伸長)
    static func readAll(_ s: Session, _ path: String) -> [Record]? {
        guard let d = s.store.readRaw(path) else { return nil }
        var out: [Record] = []
        for line in d.split(separator: 0x0a, omittingEmptySubsequences: false).dropLast(d.last == 0x0a || d.isEmpty ? 1 : 0) {
            var b = Array(line.prefix(layout.size))
            if b.count < layout.size { b += [UInt8](repeating: 0x20, count: layout.size - b.count) }
            out.append(Record(layout, bytes: b))
        }
        return out
    }
    /// line sequential の WRITE は末尾の空白を落とす
    static func append(_ s: Session, _ path: String, _ r: Record) {
        var b = r.bytes
        while b.last == 0x20 { b.removeLast() }
        s.store.appendRaw(path, b + [0x0a])
    }
}
