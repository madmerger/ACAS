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
        s.shared["maps99-error"] = code
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
}
