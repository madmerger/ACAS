enum StockLayout {
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
}
