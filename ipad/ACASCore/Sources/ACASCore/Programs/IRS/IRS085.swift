import Foundation

/// incomplete_records_system/irs085.cbl: 転記を科目・月順に整列し workpost.tmp (月次分析の入力) を作る
enum IRS085 {
    static let progName = "irs085 (3.01.03)"
    static let outputName = "workpost.tmp"
    /// output-record: 月 9(2) + 科目 9(5) comp + 金額 s9(7)v99 comp
    static let layout = Layout("irs-workpost", [
        ("mm", .x(2)),
        ("account", .comp(digits: 5, scale: 0, signed: false)),
        ("amount", .comp(digits: 9, scale: 2, signed: true))
    ])

    static func run(_ s: Session) throws {
        let c = s.console
        let ctx = IRS.context(s)
        ctx.fileNames = ctx.sys.str("system-files")
        try IRSub3.read(s)
        var recs = [Record]()
        let f = IndexedFile(s.store, path: s.irsDir + "post.dat", layout: IRS.postLayout, keyOffset: 0, keyLength: 5)
        f.open()
        if f.status != "00" {
            c.display(s.t("irs085.open_error"), at: 2401, color: 4)
            c.display(f.status, at: 2426, color: 4)
            _ = try c.accept(at: 2478, size: 1)
        } else {
            while let post = f.readNext() {
                var r = Record(layout)
                r["mm"] = String(Array(post.str("date"))[3..<5])
                let amount = IRS.getSigned(post, "amount")
                r.setInt("amount", amount)
                r.setInt("account", post.int("cr"))
                recs.append(r)
                r.setInt("amount", -amount)
                r.setInt("account", post.int("dr"))
                recs.append(r)
                let def = Int(post.int("vat-ac-def"))
                if def == 0 { continue }
                r.setInt("amount", IRS.getSigned(post, "vat-amount"))
                r.setInt("account", Int64(IRS.defAc(ctx.dflt, def)))
                recs.append(r)
            }
        }
        f.close()
        let sorted = recs.enumerated().sorted { a, b in
            let ka = a.element.int("account"), kb = b.element.int("account")
            if ka != kb { return ka < kb }
            let ma = a.element.raw("mm"), mb = b.element.raw("mm")
            if ma != mb { return ma.lexicographicallyPrecedes(mb) }
            return a.offset < b.offset
        }
        s.store.writeRaw(s.irsDir + outputName, sorted.flatMap { $0.element.bytes })
    }
}
