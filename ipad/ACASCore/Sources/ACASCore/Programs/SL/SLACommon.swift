import Foundation

/// 売掛元帳 前半 (sales, sl000〜sl095) 共通部品
enum SLA {
    /// System-Record の File-Status (n) (pic 9 occurs 32)
    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        let b = s.sys.raw("file-statuses")
        let v = Int(b[n - 1]) - 0x30
        return (0...9).contains(v) ? v : 0
    }

    static func setFileStatus(_ s: Session, _ n: Int, _ v: Int) {
        var b = s.sys.raw("file-statuses")
        b[n - 1] = UInt8(0x30 + v)
        s.sys.setRaw("file-statuses", b)
    }

    /// zz070-Convert-Date: to-day を Date-Form の表示形式へ
    static func convertDate(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, s.toDay)
    }

    /// 帳票ファイル (レコード順編成、WRITE ... BEFORE/AFTER ADVANCING)
    final class Printer {
        let s: Session
        let path: String
        let recLen: Int
        init(_ s: Session, name: String = "prt-1", recLen: Int = 132) {
            self.s = s; self.path = s.ledgers + name; self.recLen = recLen
        }
        func open() { s.store.writeRaw(path, []) }
        private func rec(_ line: String) -> [UInt8] { SJIS.encode(line, size: recLen) }
        func after(_ n: Int, _ line: String) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0a, count: n) + rec(line))
        }
        func before(_ n: Int, _ line: String) {
            s.store.appendRaw(path, rec(line) + [UInt8](repeating: 0x0a, count: n))
        }
        func afterPage(_ line: String) { s.store.appendRaw(path, [0x0c] + rec(line)) }
        func beforePage(_ line: String) { s.store.appendRaw(path, rec(line) + [0x0c]) }
        /// close + CALL "SYSTEM" using Print-Report (印刷スプールは iPad 版では UI へ通知)
        func close(spool: Bool = true) { if spool { s.onReport?(path) } }
    }

    // MARK: レコード (fdsl.cob / fddel.cob)

    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static let bs = FieldType.native(bytes: 2, signed: true)
    private static let amt = FieldType.comp3(digits: 10, scale: 2, signed: true)
    private static func d(_ n: String, _ digits: Int = 1) -> (String, FieldType) { (n, .n9(digits: digits, scale: 0, signed: false)) }

    static let salesLayout = Layout("sales-record", [
        ("sales-key", .x(7)), ("sales-name", .x(30)), ("sales-addr1", .x(48)), ("sales-addr2", .x(48)),
        ("sales-phone", .x(13)), ("sales-ext", .x(4)), ("sales-email", .x(30)), ("sales-fax", .x(13)),
        d("sales-status"), d("sales-late"), d("sales-dunning"), d("email-invoice"), d("email-statement"),
        d("email-letters"), d("delivery-tag"), d("notes-tag"), ("", .filler(3)), d("sales-credit", 2),
        ("sales-discount", .comp(digits: 4, scale: 2, signed: false)),
        ("sales-late-min", bs), ("sales-late-max", bs), ("sales-limit", bl), ("sales-activety", bl),
        ("sales-last-inv", bl), ("sales-last-pay", bl), ("sales-average", bl), ("sales-pay-activety", bl),
        ("sales-pay-average", bl), ("sales-pay-worst", bl), ("sales-create-date", bl),
        ("sales-current", amt), ("sales-last", amt), ("turnover-q1", amt), ("turnover-q2", amt),
        ("turnover-q3", amt), ("turnover-q4", amt), ("sales-unapplied", amt), ("", .filler(10)),
    ])
    static let deliveryLayout = Layout("delivery-record", [
        ("deliv-key-type", .x(1)), ("deliv-sales-key", .x(7)), ("deliv-name", .x(30)),
        ("deliv-addr1", .x(48)), ("deliv-addr2", .x(48)),
    ])
    static func salesFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "salesled.dat", layout: salesLayout, keyLength: 7)
    }
    static func deliveryFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "delivery.dat", layout: deliveryLayout, keyLength: 8)
    }

    /// INITIALIZE record: 英数字は空白、数値は 0、FILLER は変更しない
    static func initialize(_ rec: inout Record) {
        var n = Record(rec.layout)
        for f in rec.layout.order {
            if case .filler(let len) = f.type { n.bytes.replaceSubrange(f.offset..<(f.offset + len), with: rec.bytes[f.offset..<(f.offset + len)]) }
        }
        rec = n
    }

    /// common/maps99.cbl: エラー番号を error.txt から引いて 23 行目に表示する。
    /// error.txt が無い/該当なしのときは "T-nnn Error not in error.txt. Hit return to close" を表示して入力待ち。
    static func maps99(_ s: Session, _ code: Int) throws {
        let c = s.console
        var lin = 23
        s.termCode = 0
        var serv = "T", mess = s.t("sl.maps99.notfound"), wait = true
        if let b = s.store.readRaw("error.txt") {
            for l in String(decoding: b, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                let a = Array(Cobol.x(String(l), 57))
                guard Int(String(a[0..<3])) == code else { continue }
                let severity = String(a[3]), response = String(a[4])
                let errLine = Int(String(a[5..<7])) ?? 0
                serv = severity; mess = String(a[7..<57])
                if errLine != 0 { lin = errLine > 19 ? 24 - (24 - errLine) : errLine }
                wait = response == "T" || (severity == "S" && response == "S")
                if !wait && severity == "T" { s.termCode = 9 }
                break
            }
        }
        c.display(serv + "-" + Cobol.z(code, 3) + " " + Cobol.x(mess, 50), at: lin, 1, color: 4)
        if wait { _ = try c.accept(at: 24, 79, size: 1) }
    }

    /// STRING ... INTO target WITH POINTER ptr (1 起点)。範囲外は何もしない。
    static func string(_ src: String, into target: inout [Character], pointer ptr: inout Int) {
        if ptr < 1 || ptr > target.count { return }
        for ch in src {
            if ptr > target.count { return }
            target[ptr - 1] = ch; ptr += 1
        }
    }

    /// DELIMITED BY "  " (空白 2 個の手前まで)
    static func delimited(_ src: String) -> String {
        if let r = src.range(of: "  ") { return String(src[..<r.lowerBound]) }
        return src
    }

    /// zz060-Convert-Date: バイナリ日付を Date-Form の表示形式へ
    static func convertBin(_ s: Session, _ bin: Int64) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, Maps04.toDate(Int(bin)))
    }

    /// zz050-Validate-Date: 表示形式の日付 → バイナリ日付 (不正は 0)
    static func validateDate(_ s: Session, _ date: String) -> Int {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let d = String(Cobol.x(date, 10).map { ".,-".contains($0) ? Character("/") : $0 })
        return Maps04.toBinary(Common.toUK(s, d))
    }

    static func spaces(_ n: Int) -> String { String(repeating: " ", count: n) }
}
