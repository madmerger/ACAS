import Foundation

/// pl115.cbl: 未決済明細 (openitm5) を仕入先・日付・請求書・種別順に並べ替えて poisort.wrk を作る
enum PLB115 {
    static let progName = "PL115 (3.01.02)"

    static func run(_ s: Session) throws {
        if s.sys.str("oi-5-flag") == "N" { return }     // 前回の整列ファイルを使う
        if PLB.fileStatus(s, 29) != 1 {
            s.sys.set("oi-5-flag", "Y")
            try PLB.maps99(s, 25)
            try PLB.maps99(s, 15)
            return
        }
        try sorting1(s)
        s.sys.set("oi-5-flag", "N")
    }

    static func sorting1(_ s: Session) throws {
        let f = PLB.oi5File(s)
        // open input open-item-file-5: 開けない場合 READ NEXT が AT END にならず戻らない
        if f.open() != "00" { try PLB.hang(s) }
        var recs: [Record] = []
        while let r = f.readNext() { recs.append(r) }
        f.close()
        // sort-record は open-item-record-5 と同じ先頭配置 (s-customer, s-invoice, s-date, s-batch, s-type)
        let sorted = recs.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            let cx = x.raw("oi-supplier"), cy = y.raw("oi-supplier")
            if cx != cy { return cx.lexicographicallyPrecedes(cy) }
            for k in ["oi-date", "oi-invoice", "oi-type"] {
                let vx = x.int(k), vy = y.int(k)
                if vx != vy { return vx < vy }
            }
            return a.offset < b.offset
        }
        s.store.writeRaw(s.ledgers + "poisort.wrk", sorted.flatMap { $0.element.bytes })
    }
}
