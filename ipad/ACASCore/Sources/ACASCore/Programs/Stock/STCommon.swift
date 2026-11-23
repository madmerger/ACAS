import Foundation

/// 在庫管理の共通定義 (copybooks/wsstock.cob / fdstock.cob / selstock.cob、FileStat-Msgs.cpy)
enum ST {
    /// Stock-Record (400 バイト)
    static let layout: Layout = {
        var d: [(String, FieldType)] = [
            ("stock-key", .x(13)),
            ("stock-abrev-key", .x(7)),
            ("stock-supplier-p1", .x(7)),
            ("stock-supplier-p2", .x(7)),
            ("stock-supplier-p3", .x(7)),
            ("stock-desc", .x(32)),
            ("stock-construct-item", .x(13)),
            ("stock-location", .x(10)),
            ("stock-pa-code", .x(3)),
            ("stock-sa-code", .x(3)),
            ("stock-services-flag", .x(1)),
            ("stock-last-actual-cost", .comp3(digits: 9, scale: 2, signed: false)),
            ("filler-1", .filler(8)),
            ("stock-construct-bundle", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-under-construction", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-work-in-progress", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-reorder-pnt", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-std-reorder", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-back-ordered", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-on-order", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-held", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-pre-sales", .comp(digits: 6, scale: 0, signed: true)),
            ("stock-retail", .comp3(digits: 9, scale: 2, signed: false)),
            ("stock-cost", .comp3(digits: 11, scale: 4, signed: false)),
            ("stock-value", .comp3(digits: 11, scale: 2, signed: false)),
            ("stock-order-due", .comp(digits: 8, scale: 0, signed: false)),
            ("stock-order-date", .comp(digits: 8, scale: 0, signed: false)),
            ("stock-adds", .comp(digits: 8, scale: 0, signed: false)),
            ("stock-deducts", .comp(digits: 8, scale: 0, signed: false)),
            ("stock-wip-adds", .comp(digits: 8, scale: 0, signed: false)),
            ("stock-wip-deds", .comp(digits: 8, scale: 0, signed: false)),
        ]
        for m in 1...12 {
            d.append(("stock-td-adds-\(m)", .comp(digits: 8, scale: 0, signed: false)))
            d.append(("stock-td-deds-\(m)", .comp(digits: 8, scale: 0, signed: false)))
            d.append(("stock-td-wip-adds-\(m)", .comp(digits: 8, scale: 0, signed: false)))
            d.append(("stock-td-wip-deds-\(m)", .comp(digits: 8, scale: 0, signed: false)))
        }
        d.append(("filler-2", .filler(15)))
        let l = Layout("stock-record", d)
        precondition(l.size == 400)
        return l
    }()

    static let monthlyTotals = ["stock-adds", "stock-deducts", "stock-wip-adds", "stock-wip-deds"]
    static let historyKinds = ["stock-td-adds-", "stock-td-deds-", "stock-td-wip-adds-", "stock-td-wip-deds-"]

    /// Stock-File (file-11 = stockctl.dat)。主キー Stock-Key
    static func stockFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "stockctl.dat", layout: layout, keyOffset: 0, keyLength: 13)
    }
    static func auditPath(_ s: Session) -> String { s.ledgers + "staudit.dat" }
    static func tempStockPath(_ s: Session) -> String { s.ledgers + "tmp-stock.dat" }

    static func key(_ v: String) -> [UInt8] { SJIS.encode(v, size: 13) }

    // MARK: 副キー (alternate record key Stock-Abrev-Key / Stock-Desc with duplicates)

    /// 副キー順 (同値は主キー順) に並べたレコード
    static func sorted(_ f: IndexedFile, by field: String) -> [Record] {
        f.allRecords().sorted {
            let a = $0.raw(field), b = $1.raw(field)
            if a != b { return a.lexicographicallyPrecedes(b) }
            return $0.raw("stock-key").lexicographicallyPrecedes($1.raw("stock-key"))
        }
    }

    /// READ ... KEY Stock-Abrev-Key
    static func read(_ f: IndexedFile, abrev: String) -> Record? {
        let k = SJIS.encode(abrev, size: 7)
        if let r = f.allRecords().first(where: { $0.raw("stock-abrev-key") == k }) { f.status = "00"; return r }
        f.status = "23"; return nil
    }

    /// READ ... KEY Stock-Desc (重複可: 最初の 1 件)
    static func read(_ f: IndexedFile, desc: String) -> Record? {
        let k = SJIS.encode(desc, size: 32)
        if let r = sorted(f, by: "stock-desc").first(where: { $0.raw("stock-desc") == k }) { f.status = "00"; return r }
        f.status = "23"; return nil
    }

    /// WRITE: 副キー Stock-Abrev-Key (重複不可) も検査する
    static func write(_ f: IndexedFile, _ rec: Record) -> String {
        if f.allRecords().contains(where: { $0.raw("stock-abrev-key") == rec.raw("stock-abrev-key") && $0.raw("stock-key") != rec.raw("stock-key") }) {
            f.status = "22"; return "22"
        }
        return f.write(rec)
    }

    /// REWRITE: 副キー Stock-Abrev-Key の重複も検査する
    static func rewrite(_ f: IndexedFile, _ rec: Record) -> String {
        if f.allRecords().contains(where: { $0.raw("stock-abrev-key") == rec.raw("stock-abrev-key") && $0.raw("stock-key") != rec.raw("stock-key") }) {
            f.status = "22"; return "22"
        }
        return f.rewrite(rec)
    }

    /// 副キー順の順次読み (START ... KEY 副キー + READ NEXT)
    final class AltCursor {
        var recs: [Record]
        var pos = 0
        init(_ recs: [Record]) { self.recs = recs }
        func next() -> Record? {
            guard pos < recs.count else { return nil }
            pos += 1
            return recs[pos - 1]
        }
    }

    static func maps99(_ s: Session, _ code: Int) throws {
        s.shared["error-code"] = code
        try s.call("maps99")
    }

    /// FileStat-Msgs.cpy: FILE STATUS の説明 (25 桁)
    static func evalStatus(_ s: Session, _ status: String) -> String {
        let key = "st.fs_" + status
        return s.l10n.en[key] != nil ? Cobol.x(s.l10n.raw(key), 25) : ""
    }

    /// zz070-Convert-Date: to-day (UK) を Date-Form の表示形式へ。Date-Form = 0 は 1 に直す。
    static func convDate(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let a = Array(Cobol.x(s.toDay, 10))
        switch Int(s.sys.int("date-form")) {
        case 1: return String(a)
        case 2: return String(a[3..<5]) + "/" + String(a[0..<2]) + "/" + String(a[6..<10])
        default: return String(a[6..<10]) + "/" + String(a[3..<5]) + "/" + String(a[0..<2])
        }
    }

    // MARK: レコード領域 (FD)

    /// 起動直後のレコード領域 (全バイト 0)
    static func blankRecord() -> Record { Record(layout, bytes: [UInt8](repeating: 0, count: 400)) }

    /// INITIALIZE Stock-Record: 英数字は空白、数値は 0。FILLER は変更しない。
    static func initialize(_ rec: inout Record) {
        let keep = rec
        var fresh = Record(layout)
        for name in ["filler-1", "filler-2"] { fresh.setRaw(name, keep.raw(name)) }
        rec = fresh
    }

    /// 符号無し項目への格納 (符号を落とし、桁あふれは上位切り捨て)
    static func unsignedValue(_ v: Int64, digits: Int) -> Int64 { Cobol.truncate(abs(v), digits: digits, signed: false) }

    // MARK: system-record

    /// File-Status (n) (n は 1 始まり)
    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        Int(s.sys.raw("file-statuses")[n - 1]) - 0x30
    }
    static func setFileStatus(_ s: Session, _ n: Int, _ v: Int) {
        var b = s.sys.raw("file-statuses")
        b[n - 1] = UInt8(0x30 + v)
        s.sys.setRaw("file-statuses", b)
    }

    static func purchasePath(_ s: Session) -> String { s.ledgers + "purchled.dat" }
    static func analysisPath(_ s: Session) -> String { s.ledgers + "analysis.dat" }
    static func printPath(_ s: Session) -> String { s.ledgers + "prt-1" }

    /// OPEN INPUT Analysis-File (fdanal.cob: 36 バイト)。
    /// レガシー実測では、sl070 が作った分析ファイル (レコード長が FD と異なる) の OPEN は失敗する (ST112)。
    /// ファイル無しは 35、保存済みレコード長が FD と異なる場合は 39 を返す。
    static func openAnalysis(_ s: Session) -> String {
        let path = analysisPath(s)
        guard s.store.exists(path) else { return "35" }
        if s.store.all(path).contains(where: { $0.data.count != 36 }) { return "39" }
        return "00"
    }

    // MARK: 日付

    /// zz050-Validate-Date: Date-Form 形式の入力をバイナリ日付へ (不正は 0)
    static func validateDate(_ s: Session, _ test: String) -> Int {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let a = Array(Cobol.x(test, 10))
        switch Int(s.sys.int("date-form")) {
        case 1: return Maps04.toBinary(String(a))
        case 2: return Maps04.toBinary(String(a[3..<5]) + String(a[2]) + String(a[0..<2]) + String(a[5..<10]))
        default: return Maps04.toBinary(String(a[8..<10]) + "/" + String(a[5..<7]) + "/" + String(a[0..<4]))
        }
    }

    /// zz060-Convert-Date: バイナリ日付を Date-Form の表示形式へ
    static func convertDate(_ s: Session, _ bin: Int64) -> String {
        let u = Array(Maps04.toDate(Int(bin)))
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        switch Int(s.sys.int("date-form")) {
        case 1: return String(u)
        case 2: return String(u[3..<5]) + String(u[2]) + String(u[0..<2]) + String(u[5..<10])
        default: return String(u[6..<10]) + "/" + String(u[3..<5]) + "/" + String(u[0..<2])
        }
    }

    /// zz010/zz020-convert-date: to-day を Date-Form の表示形式へ (Date-Form の補正はしない)
    static func headingDate(_ s: Session) -> String {
        let u = Array(Cobol.x(s.toDay, 10))
        switch Int(s.sys.int("date-form")) {
        case 2: return String(u[3..<5]) + String(u[2]) + String(u[0..<2]) + String(u[5..<10])
        case 3: return String(u[6..<10]) + "/" + String(u[3..<5]) + "/" + String(u[0..<2])
        default: return String(u)
        }
    }

    // MARK: maps09 (チェックディジット)

    /// common/maps09.cbl。reply "C" = 生成 / "V" = 検証。戻り値は (customer-code, maps09-reply)
    static func maps09(_ code: String, _ reply: String) -> (String, String) {
        let alpha = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-")
        var cc = Array(Cobol.x(code, 7))
        var suma = 0
        for a in 1...6 {
            guard let q = alpha.firstIndex(of: cc[a - 1]) else { suma = 0; break }
            suma += (q + 1) * (8 - a)
        }
        if suma == 0 { return (String(cc), "N") }
        let a = 11 - (suma - 11 * (suma / 11))
        if reply == "C" {
            cc[6] = Character(String(a % 10))
            return (String(cc), "Y")
        }
        if reply == "V", let d = Int(String(cc[6])), a == d { return (String(cc), "Y") }
        return (String(cc), reply)
    }

    // MARK: 帳票 (print-file "prt-1"、132 桁固定)

    /// WRITE ... BEFORE/AFTER ADVANCING を GnuCOBOL と同じバイト列で出力する
    final class Printer {
        let s: Session
        let path: String
        let width: Int
        private var needsNewline = false
        init(_ s: Session, width: Int = 132) {
            self.s = s; self.width = width; path = ST.printPath(s)
            s.store.writeRaw(path, [])   // open output
        }
        private func bytes(_ line: String) -> [UInt8] { Array(Cobol.x(line, width).utf8) }
        func after(_ n: Int, _ line: String) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0a, count: n) + bytes(line)); needsNewline = true
        }
        func afterPage(_ line: String) {
            s.store.appendRaw(path, [0x0c] + bytes(line)); needsNewline = true
        }
        func before(_ n: Int, _ line: String) {
            s.store.appendRaw(path, bytes(line) + [UInt8](repeating: 0x0a, count: n)); needsNewline = false
        }
        func close() {
            if needsNewline { s.store.appendRaw(path, [0x0a]); needsNewline = false }
        }
        /// call "SYSTEM" using Print-Report (lpr)。端末内では帳票の出力を UI へ通知する。
        func spool() { s.onReport?(path) }
    }

    /// 数字以外は 0 とみなして数字列を数値にする (英数字集団項目の ACCEPT を数値へ移す箇所)
    static func digits(_ t: String) -> Int64 {
        var v: Int64 = 0
        for ch in t { v = v * 10 + Int64(ch.isASCII ? (ch.wholeNumberValue ?? 0) : 0) }
        return v
    }
}
