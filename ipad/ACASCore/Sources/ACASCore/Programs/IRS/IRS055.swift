import Foundation

/// incomplete_records_system/irs055.cbl: 転記ファイルを save-sequ の順に整列して postsort.dat (行順編成) へ出力
enum IRS055 {
    static let progName = "irs055 (3.01.00)"
    static let outputName = "postsort.dat"

    static func run(_ s: Session) throws {
        let c = s.console
        let ctx = IRS.context(s)
        ctx.fileNames = ctx.sys.str("system-files")
        let sequ = ctx.sys.int("save-sequ")
        guard (1...3).contains(sequ) else { return }
        var recs = [[UInt8]]()
        let f = IndexedFile(s.store, path: s.irsDir + "post.dat", layout: IRS.postLayout, keyOffset: 0, keyLength: 5)
        f.open()
        var fsReply = f.status
        if f.status == "00" {
            while let r = f.readNext() { recs.append(r.bytes) }
            f.close()
            fsReply = "00"
        }
        func k(_ r: [UInt8], _ off: Int, _ len: Int) -> [UInt8] { Array(r[off..<(off + len)]) }
        // sort-key 0-4, sort-code 5-6, sort-days 7-8, sort-month 10-11, sort-year 13-14
        func keys(_ r: [UInt8]) -> [UInt8] {
            let key = k(r, 0, 5), code = k(r, 5, 2), dd = k(r, 7, 2), mm = k(r, 10, 2), yy = k(r, 13, 2)
            switch sequ {
            case 1: return code + yy + mm + dd + key
            case 2: return yy + mm + dd + code + key
            default: return key
            }
        }
        let sorted = recs.enumerated().sorted { a, b in
            let ka = keys(a.element), kb = keys(b.element)
            return ka == kb ? a.offset < b.offset : ka.lexicographicallyPrecedes(kb)
        }.map { $0.element }
        var out = [UInt8]()
        for r in sorted {
            var d = r
            while let l = d.last, l == 0x20 { d.removeLast() }
            out += d + [0x0a]
        }
        s.store.writeRaw(s.irsDir + outputName, out)
        if fsReply != "00" {
            c.display(s.t("irs055.sort_failed"), at: 2301)
            c.display(fsReply, at: 2315)
            c.display(s.t("irs055.note_error"), at: 2410)
            _ = try c.accept(at: 2450, size: 2, kind: .numeric)
        }
    }
}
