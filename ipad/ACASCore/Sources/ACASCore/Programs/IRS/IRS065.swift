import Foundation

/// incomplete_records_system/irs065.cbl: 勘定元帳 (補助科目を除く) を決算書区分 (ac) 順に整列し worksort.tmp へ出力
enum IRS065 {
    static let progName = "irs065 (3.01.02)"
    static let outputName = "worksort.tmp"

    static func run(_ s: Session) throws {
        let c = s.console
        let ctx = IRS.context(s)
        ctx.fileNames = ctx.sys.str("system-files")
        let f = IndexedFile(s.store, path: s.irsDir + "acnts.dat", layout: IRS.nlLayout, keyOffset: 0, keyLength: 10)
        f.open()
        if f.status != "00" {
            c.display(s.t("irs065.open_fail"), at: 2401)
            _ = try c.accept(at: 2441, size: 1)
            s.store.writeRaw(s.irsDir + outputName, [])
            throw StopRun()
        }
        var recs = [[UInt8]]()
        while let r = f.readNext() {
            if r.str("type") == "S" { continue }
            recs.append(r.bytes)
        }
        f.close()
        let sorted = recs.enumerated().sorted { a, b in
            let ka = a.element[a.element.count - 1], kb = b.element[b.element.count - 1]
            return ka == kb ? a.offset < b.offset : ka < kb
        }
        s.store.writeRaw(s.irsDir + outputName, sorted.flatMap { $0.element })
    }
}
