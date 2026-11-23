import Foundation

/// sales/sl165.cbl: 得意先を名称順に整列しキーを custsort.tmp へ書き出す
enum SLB165 {
    static let progName = "SL165 (3.01.01)"

    static func run(_ s: Session) throws {
        let sales = SLB.salesFile(s)
        _ = sales.open()
        var recs: [(key: [UInt8], name: [UInt8])] = []
        while let r = sales.readNext() { recs.append((r.raw("sales-key"), r.raw("sales-name"))) }
        sales.close()
        let sorted = recs.enumerated().sorted {
            $0.element.name != $1.element.name ? $0.element.name.lexicographicallyPrecedes($1.element.name) : $0.offset < $1.offset
        }
        s.store.writeRaw(s.ledgers + "custsort.tmp", sorted.flatMap { $0.element.key })
    }
}
