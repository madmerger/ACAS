import Foundation

/// 買掛元帳 後半 (pl100〜pl190, pl900〜pl960) の共通部: レコードレイアウト、ファイル、帳票、maps99。
enum PLB {
    static let bl: FieldType = .native(bytes: 4, signed: true)
    static let bc: FieldType = .native(bytes: 1, signed: true)
    static let money8: FieldType = .comp3(digits: 10, scale: 2, signed: true)   // s9(8)v99 comp-3
    static let money7: FieldType = .comp3(digits: 9, scale: 2, signed: true)    // s9(7)v99 comp-3

    // MARK: レコードレイアウト

    /// fdpl.cob: Purch-Record (300)
    static let purch: Layout = {
        Layout("purch-record", [
            ("purch-key", .x(7)), ("purch-status", .n9(digits: 1, scale: 0, signed: false)),
            ("purch-notes-tag", .n9(digits: 1, scale: 0, signed: false)), ("purch-name", .x(30)),
            ("purch-addr1", .x(48)), ("purch-addr2", .x(48)), ("purch-phone", .x(13)), ("purch-ext", .x(4)),
            ("purch-fax", .x(13)), ("purch-email", .x(30)),
            ("purch-discount", .comp(digits: 4, scale: 2, signed: false)), ("purch-credit", bc),
            ("purch-sortcode", bl), ("purch-accountno", bl), ("purch-limit", bl), ("purch-activety", bl),
            ("purch-last-inv", bl), ("purch-last-pay", bl), ("purch-average", bl), ("purch-create-date", bl),
            ("purch-pay-activety", bl), ("purch-pay-average", bl), ("purch-pay-worst", bl),
            ("purch-current", money8), ("purch-last", money8),
            ("turnover-q1", money8), ("turnover-q2", money8), ("turnover-q3", money8), ("turnover-q4", money8),
            ("purch-unapplied", money8), ("", .filler(16))
        ])
    }()

    /// purchase/wsoi.cob: oi-header (109) = fdoi5.cob open-item-record-5
    static let oi: Layout = {
        Layout("oi-header", [
            ("oi-supplier", .x(7)), ("oi-invoice", bl), ("oi-date", bl),
            ("oi-b-nos", .comp(digits: 5, scale: 0, signed: false)), ("oi-b-item", .comp(digits: 3, scale: 0, signed: false)),
            ("oi-type", .n9(digits: 1, scale: 0, signed: false)), ("oi-ref", .x(10)), ("oi-order", .x(10)),
            ("oi-hold-flag", .x(1)), ("oi-unapl", .x(1)),
            ("oi-p-c", money7), ("oi-net", money7), ("oi-extra", money7), ("oi-carriage", money7), ("oi-vat", money7),
            ("oi-discount", money7), ("oi-e-vat", money7), ("oi-c-vat", money7), ("oi-paid", money7),
            ("oi-status", .n9(digits: 1, scale: 0, signed: false)), ("oi-deduct-days", bc),
            ("oi-deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("oi-deduct-vat", .comp(digits: 5, scale: 2, signed: true)),
            ("oi-days", bc), ("oi-cr", bl), ("oi-applied", .x(1)), ("oi-date-cleared", bl)
        ])
    }()

    /// purchase/fdpay.cob: pay-record
    static let pay: Layout = {
        var f: [(String, FieldType)] = [
            ("pay-supl-key", .x(7)), ("pay-nos", bc), ("pay-cont", .x(1)), ("pay-date", bl), ("pay-cheque", bl),
            ("pay-sortcode", bl), ("pay-account", bl), ("pay-gross", money7)
        ]
        for i in 1...9 {
            f += [("pay-folio-\(i)", bl), ("pay-period-\(i)", bc), ("pay-value-\(i)", money7),
                  ("pay-deduct-\(i)", .comp3(digits: 5, scale: 2, signed: true)), ("pay-invoice-\(i)", .x(10))]
        }
        return Layout("pay-record", f)
    }()

    /// fdval.cob: value-record
    static let value: Layout = {
        Layout("value-record", [
            ("va-code", .x(3)), ("va-gl", .n9(digits: 6, scale: 0, signed: false)), ("va-desc", .x(24)), ("va-print", .x(3)),
            ("va-t-this", .comp(digits: 5, scale: 0, signed: false)), ("va-t-last", .comp(digits: 5, scale: 0, signed: false)),
            ("va-t-year", .comp(digits: 5, scale: 0, signed: false)),
            ("va-v-this", money8), ("va-v-last", money8), ("va-v-year", money8)
        ])
    }()

    /// fdbatch.cob: batch-record
    static let batch: Layout = {
        let amt: FieldType = .comp3(digits: 11, scale: 2, signed: false)
        return Layout("batch-record", [
            ("ledger", .n9(digits: 1, scale: 0, signed: false)), ("batch-nos", .n9(digits: 5, scale: 0, signed: false)),
            ("items", .n9(digits: 2, scale: 0, signed: false)), ("batch-status", .n9(digits: 1, scale: 0, signed: false)),
            ("cleared-status", .n9(digits: 1, scale: 0, signed: false)), ("bcycle", .n9(digits: 2, scale: 0, signed: false)),
            ("entered", bl), ("proofed", bl), ("posted", bl), ("stored", bl),
            ("input-gross", amt), ("input-vat", amt), ("actual-gross", amt), ("actual-vat", amt),
            ("description", .x(24)), ("bdefault", .n9(digits: 2, scale: 0, signed: false)), ("convention", .x(2)),
            ("batch-def-ac", .n9(digits: 6, scale: 0, signed: false)), ("batch-def-pc", .n9(digits: 2, scale: 0, signed: false)),
            ("batch-def-code", .x(2)), ("batch-def-vat", .x(1)), ("batch-start", .n9(digits: 5, scale: 0, signed: false))
        ])
    }()

    /// fdpost.cob: posting-record (96)
    static let posting: Layout = {
        Layout("posting-record", [
            ("batch", .n9(digits: 5, scale: 0, signed: false)), ("post-number", .n9(digits: 5, scale: 0, signed: false)),
            ("post-code", .x(2)), ("post-date", .x(8)), ("post-dr", .n9(digits: 6, scale: 0, signed: false)),
            ("dr-pc", .n9(digits: 2, scale: 0, signed: false)), ("post-cr", .n9(digits: 6, scale: 0, signed: false)),
            ("cr-pc", .n9(digits: 2, scale: 0, signed: false)), ("post-amount", .n9(digits: 10, scale: 2, signed: true)),
            ("post-legend", .x(32)), ("vat-ac", .n9(digits: 6, scale: 0, signed: false)),
            ("vat-pc", .n9(digits: 2, scale: 0, signed: false)), ("post-vat-side", .x(2)),
            ("vat-amount", .n9(digits: 10, scale: 2, signed: true))
        ])
    }()

    /// wssys4.cob: System-Record-4 (1024)
    static let sys4: Layout = {
        let sl = ["sl-os-bal-last-month", "sl-os-bal-this-month", "sl-invoices-this-month", "sl-credit-notes-this-month",
                  "sl-variance", "sl-credit-deductions", "sl-cn-unappl-this-month", "sl-payments", "sl4-spare1", "sl4-spare2"]
        let pl = ["pl-os-bal-last-month", "pl-os-bal-this-month", "pl-invoices-this-month", "pl-credit-notes-this-month",
                  "pl-variance", "pl-credit-deductions", "pl-cn-unappl-this-month", "pl-payments", "sl4-spare3", "sl4-spare4"]
        return Layout("system-record-4", (sl + pl).map { ($0, money8) } + [("", .filler(904))])
    }()

    /// system-record-4 の数値項目へ加算 (s9(8)v99 comp-3)
    static func addSys4(_ s: Session, _ name: String, _ v: Int64) {
        var r = Record(sys4, bytes: s.sysRecord4)
        r.setInt(name, Cobol.truncate(r.int(name) + v, digits: 10))
        s.sysRecord4 = r.bytes
    }

    static func sys4Int(_ s: Session, _ name: String) -> Int64 { Record(sys4, bytes: s.sysRecord4).int(name) }
    static func setSys4(_ s: Session, _ name: String, _ v: Int64) {
        var r = Record(sys4, bytes: s.sysRecord4)
        r.setInt(name, Cobol.truncate(v, digits: 10))
        s.sysRecord4 = r.bytes
    }

    /// 帳票行などの固定長集団項目。部分項目を位置で上書きする (REDEFINES の再現用)。
    struct Buf {
        var c: [Character]
        init(_ size: Int) { c = [Character](repeating: " ", count: size) }
        mutating func clear() { c = [Character](repeating: " ", count: c.count) }
        /// offset (0 起点) から size 桁へ左詰め・空白埋めで MOVE
        mutating func put(_ offset: Int, _ size: Int, _ text: String) {
            let t = Array(Cobol.x(text, size))
            for i in 0..<size { c[offset + i] = t[i] }
        }
        func str(_ offset: Int, _ size: Int) -> String { String(c[offset..<(offset + size)]) }
        var text: String { String(c) }
        func prefix(_ n: Int) -> String { String(c[0..<n]) }
    }

    /// COMPUTE ... ROUNDED の除算: num / den を四捨五入 (0 から遠い方へ)。den は 0 でないこと。
    static func divRounded(_ num: Int64, _ den: Int64) -> Int64 {
        let q = num / den, r = num % den
        if abs(r) * 2 >= abs(den) { return q + ((num < 0) != (den < 0) ? -1 : 1) }
        return q
    }

    // MARK: ファイル

    static func purchFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "purchled.dat", layout: purch, keyLength: 7)
    }
    static func oi5File(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "openitm5.dat", layout: oi, keyLength: 11)
    }
    static func payFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "pay.dat", layout: pay, keyLength: 8)
    }
    static func valueFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "value.dat", layout: value, keyLength: 3)
    }
    static func batchFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "batch.dat", layout: batch, keyLength: 6)
    }

    /// 順編成 (固定長・区切り無し) ファイルの全レコード
    static func readSequential(_ s: Session, _ path: String, size: Int) -> [[UInt8]]? {
        guard let d = s.store.readRaw(path) else { return nil }
        return stride(from: 0, to: d.count - size + 1, by: size).map { Array(d[$0..<($0 + size)]) }
    }

    // MARK: 共通ルーチン

    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        Int(Cobol.numval(String(Array(Cobol.x(s.sys.str("file-statuses"), 32))[n - 1])).0)
    }

    /// 英数字項目へ MOVE した後の比較用 (右空白詰め)
    static func upper(_ x: String) -> String { x.uppercased() }

    /// zz070-Convert-Date: to-day (UK) を Date-Form の表示形式へ
    static func wsDate(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, s.toDay)
    }

    /// zz060-Convert-Date: 通日 (u-bin) を Date-Form の表示形式へ。maps04 が失敗した日付は空白。
    static func binDate(_ s: Session, _ bin: Int64) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let uk = Maps04.toDate(Int(bin))
        if uk.trimmingCharacters(in: .whitespaces).isEmpty { return Cobol.x("", 10) }
        return Common.convDate(s, uk)
    }

    /// zz050-Validate-Date: Date-Form 形式の入力日付を通日へ (不正は 0)
    static func validateDate(_ s: Session, _ text: String) -> Int {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Maps04.toBinary(Common.toUK(s, text))
    }

    /// 数値項目 (pic 9(n)) の ACCEPT。戻り値は項目へ MOVE した値。
    static func acceptNum(_ s: Session, at llcc: Int, digits: Int, initial: Int64? = nil,
                          options: AcceptOptions = [], color: UInt8 = 0) throws -> Int64 {
        var o = options
        if initial != nil { o.insert(.update) }
        let r = try s.console.accept(at: llcc, size: digits, kind: .numeric,
                                     initial: Cobol.z(initial ?? 0, digits), options: o, color: color)
        return Cobol.moveNumeric(r, digits: digits, scale: 0)
    }

    /// maps99.cbl: エラーメッセージ表示。error.txt (順編成 57 桁) が無ければ
    /// "T-nnn Error not in error.txt. Hit return to close" を表示して入力を待つ。
    static func maps99(_ s: Session, _ errorPass: Int) throws {
        let c = s.console
        let lines = 24
        var lin = lines - 1
        s.termCode = 0
        var serv = "T", mess = s.t("plb.maps99_missing")
        var found: [UInt8]?
        if let recs = readSequential(s, s.ledgers + "error.txt", size: 57) {
            found = recs.first { Cobol.numval(SJIS.decode($0[0..<3])).0 == Int64(errorPass) }
        }
        guard let r = found else {
            c.display(serv + "-" + Cobol.z(errorPass, 3) + " " + Cobol.x(mess, 50), at: lin * 100 + 1, color: 4)
            _ = try c.accept(at: lines * 100 + 79, size: 1)
            return
        }
        serv = SJIS.decode(r[3..<4]); mess = SJIS.decode(r[7..<57])
        let response = SJIS.decode(r[4..<5])
        let errorLine = Int(Cobol.numval(SJIS.decode(r[5..<7])).0)
        if errorLine != 0 { lin = errorLine > 19 ? lines - (24 - errorLine) : errorLine }
        c.display(serv + "-" + Cobol.z(errorPass, 3) + " " + Cobol.x(mess, 50), at: lin * 100 + 1, color: 4)
        if response == "T" || (serv == "S" && response == "S") {
            _ = try c.accept(at: lines * 100 + 79, size: 1)
            return
        }
        if serv == "T" { s.termCode = 9 }
    }

    /// FileStat-Msgs.cpy: FILE STATUS → メッセージ (25 桁)
    static func statusMessage(_ s: Session, _ status: String) -> String {
        let known: Set<String> = ["00", "02", "04", "05", "07", "10", "14", "21", "22", "23", "30", "31", "34", "35", "37",
                                  "38", "39", "41", "42", "43", "44", "46", "47", "48", "49", "51", "52", "57", "61", "91"]
        return known.contains(status) ? Cobol.x(s.t("plb.fs_" + status), 25) : Cobol.x("", 25)
    }

    /// binary-char (符号付き 1 バイト) への加算 (127 を超えると -128 へ回り込む)
    static func addChar(_ v: Int, _ d: Int) -> Int { Int(Int8(truncatingIfNeeded: v + d)) }
    /// binary-long (符号付き 4 バイト) への格納
    static func wrap32(_ v: Int64) -> Int64 { Int64(Int32(truncatingIfNeeded: v)) }

    /// 回復不能なレガシーのハング (開けていないファイルの READ が AT END にならず無限ループ) の再現。
    /// 画面は変えず、以後のキー入力を読み捨て続ける。
    static func hang(_ s: Session) throws -> Never {
        while true { _ = try s.console.waitKey() }
    }
}

/// print-file (prt-1): 132 桁固定長の順編成。WRITE ... BEFORE/AFTER ADVANCING のバイト列を再現する。
final class PLBPrint {
    let s: Session
    let path: String
    let width: Int
    private var buf: [UInt8] = []
    init(_ s: Session, name: String = "prt-1", width: Int = 132) {
        self.s = s; self.path = s.ledgers + name; self.width = width
    }
    /// OPEN OUTPUT
    func openOutput() { buf = []; s.store.writeRaw(path, []) }
    /// CLOSE
    func close() { s.store.writeRaw(path, buf) }
    private func rec(_ line: String) -> [UInt8] { SJIS.encode(line, size: width) }
    /// WRITE rec BEFORE ADVANCING n
    func before(_ line: String, _ n: Int = 1) { buf += rec(line) + [UInt8](repeating: 0x0a, count: n) }
    /// WRITE rec AFTER ADVANCING n
    func after(_ line: String, _ n: Int = 1) { buf += [UInt8](repeating: 0x0a, count: n) + rec(line) }
    /// WRITE rec AFTER ADVANCING PAGE
    func afterPage(_ line: String) { buf += [0x0c] + rec(line) }
    /// WRITE rec BEFORE ADVANCING PAGE
    func beforePage(_ line: String) { buf += rec(line) + [0x0c] }
    /// call "SYSTEM" using Print-Report (lpr): 端末内では帳票の出力を UI へ知らせる。
    func spool() { s.onReport?(path) }
}
