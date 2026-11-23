import Foundation

/// general/gl071.cbl: Transaction Posting — Phase 3 (pretrans.tmp をバッチ・勘定・P/C・仕訳番号順に整列し postrans.tmp へ)
enum GL071 {
    static let progName = "gl071 (3.00.02)"

    static func run(_ s: Session) throws {
        s.console.display(s.t("gl071.sorting"), at: 801, color: 2)
        guard let recs = GLTrans.readAll(s, GLTrans.prePath(s)) else { return }
        func key(_ r: Record) -> [Int64] { [r.int("batch"), r.int("ac"), r.int("pc"), r.int("post")] }
        let sorted = recs.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            for i in 0..<4 where ka[i] != kb[i] { return ka[i] < kb[i] }
            return a.offset < b.offset
        }
        s.store.writeRaw(GLTrans.postPath(s), [])
        for r in sorted { GLTrans.append(s, GLTrans.postPath(s), r.element) }
    }
}
