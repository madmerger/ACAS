import Foundation

/// 買掛元帳 前半が使うファイルのレコード定義 (purchase/*.cob, copybooks/*.cob と同一配置) と共通部品
extension PLA {
    static let bc = FieldType.native(bytes: 1, signed: true)
    static let bs = FieldType.native(bytes: 2, signed: true)
    static let bl = FieldType.native(bytes: 4, signed: true)
    static func money(_ digits: Int = 9) -> FieldType { .comp3(digits: digits, scale: 2, signed: true) }
    static func d(_ n: Int) -> FieldType { .n9(digits: n, scale: 0, signed: false) }

    /// fdpl.cob Purch-Record (300 バイト)
    static let purchLayout: Layout = {
        let l = Layout("purch-record", [
            ("purch-key", .x(7)), ("purch-status", d(1)), ("purch-notes-tag", d(1)), ("purch-name", .x(30)),
            ("purch-addr1", .x(48)), ("purch-addr2", .x(48)), ("purch-phone", .x(13)), ("purch-ext", .x(4)),
            ("purch-fax", .x(13)), ("purch-email", .x(30)), ("purch-discount", .comp(digits: 4, scale: 2, signed: false)),
            ("purch-credit", bc), ("purch-sortcode", bl), ("purch-accountno", bl), ("purch-limit", bl),
            ("purch-activety", bl), ("purch-last-inv", bl), ("purch-last-pay", bl), ("purch-average", bl),
            ("purch-create-date", bl), ("purch-pay-activety", bl), ("purch-pay-average", bl), ("purch-pay-worst", bl),
            ("purch-current", money(10)), ("purch-last", money(10)),
            ("turnover-q1", money(10)), ("turnover-q2", money(10)), ("turnover-q3", money(10)), ("turnover-q4", money(10)),
            ("purch-unapplied", money(10)), ("", .filler(16)),
        ])
        l.redefine("purch-address", .x(96), at: l.offset("purch-addr1"))
        return l
    }()

    /// fdpinv2.cob / wspinv.cob invoice-header (129 バイト)
    static let invHeaderLayout: Layout = {
        let l = Layout("invoice-header", [
            ("ih-invoice", d(8)), ("ih-test", bc), ("ih-supplier", .x(7)), ("ih-date", bl), ("ih-order", .x(10)),
            ("ih-type", d(1)), ("ih-ref", .x(10)),
            ("ih-p-c", money()), ("ih-net", money()), ("ih-extra", money()), ("ih-carriage", money()),
            ("ih-vat", money()), ("ih-discount", money()), ("ih-e-vat", money()), ("ih-c-vat", money()),
            ("ih-status", .x(1)), ("ih-lines", bc), ("ih-deduct-days", bc),
            ("ih-deduct-amt", .comp(digits: 5, scale: 2, signed: false)), ("ih-deduct-vat", .comp(digits: 5, scale: 2, signed: false)),
            ("ih-days", bc), ("ih-cr", bl), ("ih-day-book-flag", .x(1)), ("ih-update", .x(1)), ("", .filler(30)),
        ])
        l.redefine("invoice-key", .x(9), at: 0)
        l.redefine("ih-nos", .x(6), at: 9)
        l.redefine("ih-check", d(1), at: 15)
        return l
    }()

    /// fdpinv2.cob invoice-line (74 バイト、レコードは 129 バイト)
    static let invLineLayout: Layout = {
        let l = Layout("invoice-line", [
            ("il-invoice", d(8)), ("il-line", bc), ("il-product", .x(13)), ("il-pa", .x(2)), ("", .filler(2)),
            ("il-qty", bs), ("il-type", .x(1)), ("il-description", .x(24)), ("", .filler(2)),
            ("il-net", money()), ("il-unit", money()), ("il-discount", .comp(digits: 4, scale: 2, signed: false)),
            ("il-vat", money()), ("il-vat-code", d(1)), ("il-update", .x(1)), ("", .filler(55)),
        ])
        l.redefine("invoice-key", .x(9), at: 0)
        return l
    }()

    /// wsoi.cob oi-header / fdoi5.cob open-item-record-5 (109 バイト、キー = supplier(7) + invoice(binary-long))
    static let oiLayout: Layout = {
        let l = Layout("oi-header", [
            ("oi-supplier", .x(7)), ("oi-invoice", bl), ("oi-date", bl),
            ("oi-b-nos", .comp(digits: 5, scale: 0, signed: false)), ("oi-b-item", .comp(digits: 3, scale: 0, signed: false)),
            ("oi-type", d(1)), ("oi-ref", .x(10)), ("oi-order", .x(10)), ("oi-hold-flag", .x(1)), ("oi-unapl", .x(1)),
            ("oi-p-c", money()), ("oi-net", money()), ("oi-extra", money()), ("oi-carriage", money()), ("oi-vat", money()),
            ("oi-discount", money()), ("oi-e-vat", money()), ("oi-c-vat", money()), ("oi-paid", money()),
            ("oi-status", d(1)), ("oi-deduct-days", bc),
            ("oi-deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("oi-deduct-vat", .comp(digits: 5, scale: 2, signed: true)),
            ("oi-days", bc), ("oi-cr", bl), ("oi-applied", .x(1)), ("oi-date-cleared", bl),
        ])
        l.redefine("oi-approp", money(), at: l.offset("oi-net"))
        l.redefine("oi5-key", .x(11), at: 0)
        return l
    }()

    /// fdpay.cob pay-record (237 バイト)
    static let payLayout: Layout = {
        var f: [(String, FieldType)] = [
            ("pay-supl-key", .x(7)), ("pay-nos", bc), ("pay-cont", .x(1)), ("pay-date", bl), ("pay-cheque", bl),
            ("pay-sortcode", bl), ("pay-account", bl), ("pay-gross", money()),
        ]
        for i in 1...9 {
            f += [("pay-folio-\(i)", bl), ("pay-period-\(i)", bc), ("pay-value-\(i)", money()),
                  ("pay-deduct-\(i)", .comp3(digits: 5, scale: 2, signed: true)), ("pay-invoice-\(i)", .x(10))]
        }
        return Layout("pay-record", f)
    }()

    static func purchaseFile(_ s: Session) -> IndexedFile { IndexedFile(s.store, path: s.ledgers + "purchled.dat", layout: purchLayout, keyLength: 7) }
    static func invoiceFile(_ s: Session) -> IndexedFile { IndexedFile(s.store, path: s.ledgers + "pinvoice.dat", layout: invHeaderLayout, keyLength: 9) }
    static func openItem5(_ s: Session) -> IndexedFile { IndexedFile(s.store, path: s.ledgers + "openitm5.dat", layout: oiLayout, keyLength: 11) }
    static func openItem4Path(_ s: Session) -> String { s.ledgers + "openitm4.dat" }
    static func payFile(_ s: Session) -> IndexedFile { IndexedFile(s.store, path: s.ledgers + "pay.dat", layout: payLayout, keyLength: 8) }

    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        let a = Array(s.sys.str("file-statuses").utf8)
        return n <= a.count ? Int(a[n - 1]) - 48 : 0
    }
    static func setFileStatus(_ s: Session, _ n: Int, _ v: Int) {
        var a = Array(s.sys.raw("file-statuses"))
        a[n - 1] = UInt8(48 + v)
        s.sys.setRaw("file-statuses", a)
    }

    /// zz070-Convert-Date: to-day を Date-Form の表示形式へ
    static func toDayDisplay(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, s.toDay)
    }
    /// zz060-Convert-Date: 日数 (u-bin) → 表示形式の日付
    static func dateDisplay(_ s: Session, _ bin: Int64) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, Maps04.toDate(Int(bin)))
    }
    /// zz050-Validate-Date: 表示形式の入力 → (UK 形式, 日数。不正は 0)
    static func validateDate(_ s: Session, _ input: String) -> (uk: String, bin: Int) {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let uk = Common.toUK(s, input)
        return (uk, Maps04.toBinary(uk))
    }
    /// UNSTRING ... DELIMITED BY delim INTO target(size) WITH POINTER (1 起点)。pointer を進める。
    static func unstring(_ src: [Character], delim: Character, pointer: inout Int, size: Int) -> String {
        if pointer < 1 || pointer > src.count { return String(repeating: " ", count: size) }
        var out: [Character] = []
        var i = pointer - 1
        while i < src.count, src[i] != delim { out.append(src[i]); i += 1 }
        pointer = i < src.count ? i + 2 : i + 1
        return Cobol.x(String(out), size)
    }
    /// print-file (prt-1) への 1 行出力
    static func printPath(_ s: Session) -> String { s.ledgers + "prt-1" }
}

extension PLA {
    /// fdanal.cob analysis-record (36 バイト)
    static let analLayout: Layout = {
        let l = Layout("analysis-record", [
            ("pa-system", .x(1)), ("pa-group", .x(2)), ("pa-gl", d(6)), ("pa-desc", .x(24)), ("pa-print", .x(3)),
        ])
        l.redefine("pa-code", .x(3), at: 0)
        return l
    }()

    /// wspinv.cob の invoice-line (75 バイト) を invoice-record (129 バイト) へ MOVE した形
    static let wsLineLayout: Layout = {
        let l = Layout("ws-invoice-line", [
            ("il-invoice", d(8)), ("il-line", bc), ("il-product", .x(12)), ("il-pa", .x(2)), ("", .filler(3)),
            ("il-qty", bs), ("il-type", .x(1)), ("il-description", .x(24)), ("", .filler(2)),
            ("il-net", money()), ("il-unit", money()), ("il-discount", .comp(digits: 4, scale: 2, signed: false)),
            ("il-vat", money()), ("il-vat-code", d(1)), ("il-update", .x(1)), ("", .filler(55)),
        ])
        l.redefine("invoice-key", .x(9), at: 0)
        return l
    }()

    /// 索引ファイルのラッパ。既存ファイルのレコード長が FD と異なる場合、レガシー (GnuCOBOL) では OPEN が
    /// 失敗し (39)、以後の READ は INVALID KEY にならないままレコード領域が変化しない。その挙動を再現する。
    final class CheckedFile {
        enum ReadResult { case ok(Record), invalidKey, notOpen }
        let file: IndexedFile
        let store: FileStore
        private(set) var opened = false
        var status = "00"
        init(_ s: Session, _ file: IndexedFile) { self.file = file; store = s.store }

        @discardableResult
        func open() -> String {
            let st = file.open()
            if st != "00" { opened = false; status = st; return st }
            if let first = store.seek(file.path, key: [], inclusive: true), first.data.count != file.layout.size {
                file.close(); opened = false; status = "39"; return status
            }
            opened = true; status = "00"; return status
        }
        func openOutput() { file.openOutput(); opened = true; status = "00" }
        func close() { file.close(); status = opened ? "00" : "42"; opened = false }
        func read(key: [UInt8]) -> ReadResult {
            guard opened else { status = "47"; return .notOpen }
            if let r = file.read(key: key) { status = "00"; return .ok(r) }
            status = "23"; return .invalidKey
        }
        func start(notLessThan key: [UInt8]) -> Bool? {
            guard opened else { status = "47"; return nil }
            let ok = file.start(notLessThan: key); status = file.status; return ok
        }
        func readNext() -> Record? {
            guard opened else { status = "47"; return nil }
            let r = file.readNext(); status = file.status; return r
        }
        @discardableResult func write(_ r: Record) -> String { guard opened else { status = "48"; return status }; status = file.write(r); return status }
        @discardableResult func rewrite(_ r: Record) -> String { guard opened else { status = "49"; return status }; status = file.rewrite(r); return status }
        @discardableResult func delete(key: [UInt8]) -> String { guard opened else { status = "49"; return status }; status = file.delete(key: key); return status }
    }
    static func analysisFile(_ s: Session) -> CheckedFile {
        CheckedFile(s, IndexedFile(s.store, path: s.ledgers + "analysis.dat", layout: analLayout, keyLength: 3))
    }

    /// 9(n) "." v99 の集団項目を英数字として ACCEPT ... UPDATE する (accept-money)。値は scale 2。
    static func acceptMoney(_ s: Session, at line: Int, _ col: Int, digits: Int, value: Int64) throws -> Int64 {
        let c = s.console
        let shown = Cobol.z(value / 100 % Cobol.pow10(digits), digits) + "." + Cobol.z(value % 100, 2)
        c.display(shown, at: line, col, color: 3)
        let a = Array(try c.accept(at: line, col, size: digits + 3, initial: shown, options: [.update], color: 3).unicodeScalars)
        func num(_ r: Range<Int>) -> Int64 { r.reduce(Int64(0)) { $0 * 10 + Int64(a[$1].value & 0x0F) } }
        return num(0..<digits) * 100 + num((digits + 1)..<(digits + 3))
    }

    /// 順編成 (固定長) の del-inv-nos-file 等
    final class SeqFile {
        let s: Session, path: String, recSize: Int
        var pos = 0
        var isOpen = false
        init(_ s: Session, path: String, recSize: Int) { self.s = s; self.path = path; self.recSize = recSize }
        func openInput() -> Bool { guard s.store.readRaw(path) != nil else { return false }; pos = 0; isOpen = true; return true }
        func openOutput() { s.store.writeRaw(path, []); pos = 0; isOpen = true }
        func openExtend() { if s.store.readRaw(path) == nil { s.store.writeRaw(path, []) }; isOpen = true }
        func close() { isOpen = false }
        func read() -> [UInt8]? {
            guard isOpen, let d = s.store.readRaw(path), pos + recSize <= d.count else { return nil }
            defer { pos += recSize }
            return Array(d[pos..<(pos + recSize)])
        }
        func write(_ rec: [UInt8]) { s.store.appendRaw(path, rec) }
    }
}

extension PLA {
    /// 2 進ゼロ等の非表示文字を含む項目の DISPLAY (画面上は空白)
    static func shown(_ raw: [UInt8]) -> String {
        SJIS.decode(ArraySlice(raw.map { $0 < 0x20 ? 0x20 : $0 }))
    }
}
