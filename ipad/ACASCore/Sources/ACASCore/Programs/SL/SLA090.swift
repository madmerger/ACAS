import Foundation

/// sales/sl090.cbl: 入金プルーフ用の未決済明細ソート (openitm3.dat → oisort.wrk)
enum SLA090 {
    static let progName = "SL090 (3.01.02)"

    /// sd sort-file の Sort-Record (114 バイト)
    static let sortLayout = Layout("sort-record", [
        ("s-customer", .x(7)), ("s-invoice", .native(bytes: 4, signed: true)), ("s-date", .native(bytes: 4, signed: true)),
        ("s-b-nos", .comp(digits: 5, scale: 0, signed: false)), ("s-b-item", .comp(digits: 3, scale: 0, signed: false)),
        ("s-type", .n9(digits: 1, scale: 0, signed: false)), ("", .filler(92)),
    ])

    static func sortedPath(_ s: Session) -> String { s.ledgers + "oisort.wrk" }

    static func run(_ s: Session) throws {
        let c = s.console
        c.display(progName, at: 101, eraseEOS: true)
        let itm3Length = SLA.oiLayout.size, itmsLength = sortLayout.size
        if itm3Length != itmsLength {
            c.display(s.t("sl090.syserr"), at: 1201, color: 3, highlight: true)
            c.display(Cobol.z(itm3Length, 3), at: 1246, color: 3)
            c.display(s.t("sl090.sorted"), at: 1250, color: 3)
            c.display(Cobol.z(itmsLength, 3), at: 1262, color: 3)
            c.display(s.t("sl090.note"), at: 1401, color: 3)
            _ = try c.accept(at: 1438, size: 1)
            return
        }
        if s.sys.int("s-flag-p") == 0 {
            try SLA.maps99(s, 30)
            try SLA.maps99(s, 15)
            return
        }
        s.sys["oi-3-flag"] = "Y"
        // sorting-1 / input-to-sort
        var recs: [Record] = []
        let oi3 = SLA.openItemFile3(s)
        if oi3.open() == "00" {
            oi3.startFirst()
            while let r = oi3.readNext() {
                let type = r.int("oi-type")
                if type == 1 || type == 3 { continue }
                if r.int("oi-b-nos") == 0 && r.int("oi-b-item") == 0 { continue }
                recs.append(r)
            }
            oi3.close()
        } else {
            oi3.close()
        }
        func key(_ r: Record) -> [Int64] {
            [r.int("oi-b-nos"), r.int("oi-b-item"), -r.int("oi-type"), r.int("oi-date"), r.int("oi-invoice")]
        }
        let sorted = recs.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            return ka == kb ? a.offset < b.offset : ka.lexicographicallyPrecedes(kb)
        }
        s.store.writeRaw(sortedPath(s), sorted.flatMap { $0.element.bytes })
    }
}
