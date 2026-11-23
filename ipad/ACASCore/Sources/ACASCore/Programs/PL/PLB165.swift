import Foundation

/// pl165.cbl: 仕入先名順の索引 (suppsort.inx) を作る
enum PLB165 {
    static let progName = "PL165 (3.01.01)"
    static let sortName = "suppsort.inx"

    static func run(_ s: Session) throws {
        let pf = PLB.purchFile(s)
        // open input purchase-file: 開けない場合 READ NEXT が AT END にならず戻らない
        if pf.open() != "00" { try PLB.hang(s) }
        var recs: [(key: [UInt8], name: [UInt8])] = []
        while let r = pf.readNext() {
            recs.append((r.raw("purch-key"), r.raw("purch-name")))
        }
        // sort on ascending key sort-name
        let sorted = recs.enumerated().sorted { a, b in
            if a.element.name != b.element.name { return a.element.name.lexicographicallyPrecedes(b.element.name) }
            return a.offset < b.offset
        }
        s.store.writeRaw(s.ledgers + sortName, sorted.flatMap { $0.element.key })
        pf.close()
    }
}
