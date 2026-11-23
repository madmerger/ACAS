import Foundation

/// general/gl100.cbl: Ledger Print - Sort (アーカイブを勘定・P/C・バッチ・仕訳番号順に整列し workarc.tmp へ)
enum GL100 {
    static let progName = "gl100 (3.00.01)"

    /// レガシー実測 (GL-011, GL-228): 表題の表示直後、disk-change の最初の文で実行単位が異常終了し
    /// (終了コード 1)、GL115 以降は表示されない。原因はソースからは特定できていないため、実測の動作に合わせる。
    static let abortsInDiskChange = true

    static func run(_ s: Session) throws {
        let c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("gl100.title"), at: 131, color: 2)
        let a = try diskChange(s)
        if a == 9 { s.termCode = 5; return }
        let file2 = GLTrans.file2(s)
        guard let recs = GLTrans.readAll(s, file2, GL080.arcLayout) else { s.termCode = 4; return }
        func key(_ r: Record) -> [Int64] { [r.int("arc-ac"), r.int("arc-pc"), r.int("arc-batch"), r.int("arc-post")] }
        let sorted = recs.enumerated().sorted { x, y in
            let kx = key(x.element), ky = key(y.element)
            for i in 0..<4 where kx[i] != ky[i] { return kx[i] < ky[i] }
            return x.offset < y.offset
        }
        let out = GLTrans.archivesPath(s, "workarc.tmp")
        s.store.writeRaw(out, [])
        for r in sorted { GLTrans.append(s, out, r.element) }
    }

    static func diskChange(_ s: Session) throws -> Int {
        let c = s.console
        if abortsInDiskChange { throw StopRun(code: 1) }
        var file2 = GLTrans.archivesPath(s, GLTrans.file2(s))
        s.shared["gl.file-2"] = file2
        c.display(s.t("gl100.gl115"), at: 1201, color: 2, eraseEOL: true)
        c.display(s.t("gl100.gl114"), at: 1301, color: 2, eraseEOL: true)
        while true {
            let a = Int(Cobol.moveNumeric(try c.accept(at: 1369, size: 1, kind: .numeric), digits: 1, scale: 0))
            if a == 9 { return a }
            if a != 0 { continue }
            c.display(s.t("gl100.current_path"), at: 1401, color: 2, eraseEOL: true)
            file2 = Cobol.rtrim(try c.accept(at: 1501, size: 532, initial: file2, options: [.update], color: 2))
            s.shared["gl.file-2"] = file2
            if file2.isEmpty || file2.hasPrefix(" ") { continue }
            return a
        }
    }
}
