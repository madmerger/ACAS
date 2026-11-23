import Foundation

/// sales/sl115.cbl: Open Item ファイル (openitm3) を得意先・日付・請求書番号・種別順に整列し oisort.wrk を作る
enum SLB115 {
    static let progName = "SL115 (3.01.04)"

    static func run(_ s: Session) throws {
        if s.sys.str("oi-3-flag") == "N" { return }
        if SLB.fileStatus(s, 19) != 1 {
            s.sys["oi-3-flag"] = "Y"
            try SLB.maps99(s, 19)
            try SLB.maps99(s, 15)
            return
        }
        // sort-record: s-customer x(7), s-invoice binary-long, s-date binary-long, s-batch, s-type 9
        let oi = SLB.oi3File(s)
        _ = oi.open()
        var recs: [Record] = []
        while let r = oi.readNext() { recs.append(r) }
        oi.close()
        func less(_ a: Record, _ b: Record) -> Bool {
            let ca = a.raw("oi-customer"), cb = b.raw("oi-customer")
            if ca != cb { return ca.lexicographicallyPrecedes(cb) }
            if a.int("oi-date") != b.int("oi-date") { return a.int("oi-date") < b.int("oi-date") }
            if a.int("oi-invoice") != b.int("oi-invoice") { return a.int("oi-invoice") < b.int("oi-invoice") }
            return a.int("oi-type") < b.int("oi-type")
        }
        let sorted = recs.enumerated().sorted { less($0.element, $1.element) || (!less($1.element, $0.element) && $0.offset < $1.offset) }
        s.store.writeRaw(s.ledgers + "oisort.wrk", sorted.flatMap { $0.element.bytes })
        s.sys["oi-3-flag"] = "N"
    }
}
