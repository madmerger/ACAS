import Foundation

/// incomplete_records_system/irsubp.cbl: 整列済み転記ファイル (postsort.dat, 行順編成) の入出力
enum IRSubP {
    static func path(_ s: Session) -> String { s.irsDir + IRS055.outputName }

    /// fn-open。戻り値 we-error (99 = オープン失敗)
    static func open(_ s: Session, _ mode: IRSub1.Mode) -> Int {
        let ctx = IRS.context(s)
        switch mode {
        case .input, .io:
            guard let raw = s.store.readRaw(path(s)) else { ctx.sortPos = nil; return 99 }
            ctx.sortData = raw; ctx.sortPos = 0
        case .output:
            s.store.writeRaw(path(s), [])
            ctx.sortData = []; ctx.sortPos = 0
        }
        return 0
    }

    static func close(_ s: Session) { IRS.context(s).sortPos = nil }

    /// fn-read-next。3 = ファイル終端。
    /// 未オープン時、レガシーは READ が失敗しても we-error を立てない (呼出側が無限ループになる) ため、ここでは 99 を返す。
    static func readNext(_ s: Session, _ post: inout Record) -> Int {
        let ctx = IRS.context(s)
        guard let pos = ctx.sortPos else { return 99 }
        if pos >= ctx.sortData.count { return 3 }
        var end = pos
        while end < ctx.sortData.count && ctx.sortData[end] != 0x0a { end += 1 }
        var line = Array(ctx.sortData[pos..<end])
        ctx.sortPos = min(end + 1, ctx.sortData.count)
        let size = IRS.postLayout.size
        if line.count > size { line = Array(line.prefix(size)) }
        while line.count < size { line.append(0x20) }
        post = Record(IRS.postLayout, bytes: line)
        return 0
    }

    /// fn-write
    static func write(_ s: Session, _ post: Record) {
        var d = post.bytes
        while let l = d.last, l == 0x20 { d.removeLast() }
        s.store.appendRaw(path(s), d + [0x0a])
    }

    static func run(_ s: Session) throws {}
}
