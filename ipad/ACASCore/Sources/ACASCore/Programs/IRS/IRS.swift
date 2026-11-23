import Foundation

/// IRS (不完全記録システム) 共通: レコードレイアウト、system-record、下位ルーチン (irsub1〜irsub5)
enum IRS {
    // MARK: レイアウト

    /// wssystem.cob (system-record, 312 桁。system.dat は行順編成で末尾空白が落ちる)
    static let systemLayout: Layout = {
        let l = Layout("irs-system", [
            ("run-date", .x(8)), ("suser", .x(24)), ("client", .x(24)),
            ("address-1", .x(24)), ("address-2", .x(24)), ("address-3", .x(24)), ("address-4", .x(24)),
            ("start-date", .x(8)), ("end-date", .x(8)),
            ("fn-1", .x(9)), ("fn-2", .x(10)), ("fn-3", .x(8)), ("fn-4", .x(8)), ("fn-5", .x(12)),
            ("fn-filler", .x(1)), ("system-ops", .x(1)),
            ("pass-word", .x(4)), ("next-post", .n9(digits: 5, scale: 0, signed: false)),
            ("vat", .n9(digits: 4, scale: 2, signed: false)), ("vat2", .n9(digits: 4, scale: 2, signed: false)),
            ("vat3", .n9(digits: 4, scale: 2, signed: false)),
            ("pass-value", .n9(digits: 1, scale: 0, signed: false)), ("save-sequ", .n9(digits: 1, scale: 0, signed: false)),
            ("system-work-group", .x(18)), ("pl-app-created", .x(1)),
            ("pl-approp-ac", .n9(digits: 5, scale: 0, signed: false)),
            ("print-spool-name", .x(32)), ("first-time-flag", .n9(digits: 1, scale: 0, signed: false)),
            ("filler-9", .n9(digits: 7, scale: 0, signed: false)), ("filler-x", .x(8)),
        ])
        l.redefine("system-files", .x(49), at: l.offset("fn-1"))
        return l
    }()

    /// wsnl.cob (nl-record, 116 桁)
    static let nlLayout: Layout = {
        var defs: [(String, FieldType)] = [
            ("owning", .n9(digits: 5, scale: 0, signed: false)), ("sub-nominal", .n9(digits: 5, scale: 0, signed: false)),
            ("type", .x(1)), ("name", .x(24)),
            ("dr", .comp(digits: 10, scale: 2, signed: false)), ("cr", .comp(digits: 10, scale: 2, signed: false)),
        ]
        for i in 1...4 { defs.append(("dr-last-\(i)", .comp(digits: 10, scale: 2, signed: false))) }
        for i in 1...4 { defs.append(("cr-last-\(i)", .comp(digits: 10, scale: 2, signed: false))) }
        defs.append(("ac", .x(1)))
        let l = Layout("irs-nl", defs)
        l.redefine("key", .x(10), at: 0)
        l.redefine("pointer", .n9(digits: 5, scale: 0, signed: false), at: 11)
        l.redefine("data", .x(105), at: 11)
        return l
    }()

    /// wspost.cob (posting-record, 77 桁)
    static let postLayout: Layout = {
        let l = Layout("irs-post", [
            ("key", .n9(digits: 5, scale: 0, signed: false)), ("code", .x(2)), ("date", .x(8)),
            ("dr", .n9(digits: 5, scale: 0, signed: false)), ("cr", .n9(digits: 5, scale: 0, signed: false)),
            ("amount", .x(9)), ("legend", .x(32)),
            ("vat-ac-def", .n9(digits: 2, scale: 0, signed: false)), ("vat-side", .x(2)),
            ("vat-amount", .x(9)),
        ])
        return l
    }()

    /// fdpost-irs.cob (postings2irs.dat: SL/PL から IRS への転記受け渡しファイル, 84 桁)
    static let ledgerPostLayout = Layout("irs-ledger-post", [
        ("batch", .n9(digits: 5, scale: 0, signed: false)), ("post-number", .n9(digits: 5, scale: 0, signed: false)),
        ("code", .x(2)), ("date", .x(8)),
        ("dr", .n9(digits: 5, scale: 0, signed: false)), ("cr", .n9(digits: 5, scale: 0, signed: false)),
        ("amount", .x(9)), ("legend", .x(32)),
        ("vat-ac-def", .n9(digits: 2, scale: 0, signed: false)), ("vat-side", .x(2)),
        ("vat-amount", .x(9)),
    ])

    /// wsdflt.cob (default-record, 256 桁)
    static let defaultSize = 256
    /// wsfinal.cob (final-record, 655 桁)
    static let finalSize = 655

    // MARK: 数値補助

    /// pic s9(7)v99 sign leading (separate ではない: 先頭桁にオーバーパンチ) の読み書き
    static func getSigned(_ rec: Record, _ name: String) -> Int64 {
        let b = rec.raw(name)
        var v: Int64 = 0
        var neg = false
        for (i, c) in b.enumerated() {
            var d = c
            if i == 0, c >= 0x70, c <= 0x79 { neg = true; d = c - 0x40 }
            v = v * 10 + ((d >= 0x30 && d <= 0x39) ? Int64(d - 0x30) : 0)
        }
        return neg ? -v : v
    }

    static func setSigned(_ rec: inout Record, _ name: String, _ value: Int64) {
        var b = Array(Cobol.z(abs(value) % Cobol.pow10(rec.raw(name).count), rec.raw(name).count).utf8)
        if value < 0 { b[0] += 0x40 }
        rec.setRaw(name, b)
    }

    static func isNumeric(_ b: [UInt8]) -> Bool { b.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }
    static func isNumeric(_ s: String) -> Bool { isNumeric(Array(s.utf8)) }

    static func initialSystemRecord() -> Record { Record(systemLayout) }
    static func newNL() -> Record { Record(nlLayout) }
    static func newPost() -> Record {
        var r = Record(postLayout)
        r.setRaw("amount", Array("000000000".utf8)); r.setRaw("vat-amount", Array("000000000".utf8))
        return r
    }

    // MARK: 共有領域

    final class Context {
        var sys = IRS.initialSystemRecord()
        /// file-access の file-names (irsub2 の読込で system-files から設定される)
        var fileNames = Cobol.x("", 49)
        var nlFile: IndexedFile?
        var postFile: IndexedFile?
        /// irsubp: postsort.dat の読込位置 (nil = 未オープン)
        var sortPos: Int?
        var sortData = [UInt8]()
        /// wsdflt.cob: default-record
        var dflt = [UInt8](repeating: 0x20, count: IRS.defaultSize)
        var file1: String { Cobol.rtrim(String(Array(fileNames)[0..<9])) }
        var file3: String { Cobol.rtrim(String(Array(fileNames)[19..<27])) }
    }

    static func context(_ s: Session) -> Context {
        if let c = s.shared["irs.context"] as? Context { return c }
        let c = Context()
        s.shared["irs.context"] = c
        return c
    }

    // MARK: default-record 補助 (def-acs 9(5) x32, def-codes xx x32, def-vat x x32)

    static func defAc(_ d: [UInt8], _ i: Int) -> Int {
        Int(Cobol.numval(String(decoding: d[((i - 1) * 5)..<(i * 5)], as: UTF8.self)).0)
    }
    static func defAcRaw(_ d: [UInt8], _ i: Int) -> String { String(decoding: d[((i - 1) * 5)..<(i * 5)], as: UTF8.self) }
    static func setDefAc(_ d: inout [UInt8], _ i: Int, _ v: Int) {
        d.replaceSubrange(((i - 1) * 5)..<(i * 5), with: Array(Cobol.z(v % 100000, 5).utf8))
    }
    static func defCode(_ d: [UInt8], _ i: Int) -> String {
        SJIS.decode(d[(160 + (i - 1) * 2)..<(160 + i * 2)])
    }
    static func setDefCode(_ d: inout [UInt8], _ i: Int, _ v: String) {
        d.replaceSubrange((160 + (i - 1) * 2)..<(160 + i * 2), with: SJIS.encode(v, size: 2))
    }
    static func defVat(_ d: [UInt8], _ i: Int) -> String { SJIS.decode(d[(224 + i - 1)..<(224 + i)]) }
    static func setDefVat(_ d: inout [UInt8], _ i: Int, _ v: String) {
        d.replaceSubrange((224 + i - 1)..<(224 + i), with: SJIS.encode(v, size: 1))
    }

    // MARK: fsdispfe.cob

    static func displayFileError(_ s: Session, _ status: String) throws {
        if status != "00" {
            let c = s.console
            c.display(s.t("irs.error_code"), at: 2430, color: 4)
            c.display(status, at: 2443, color: 4)
            c.display(s.t("irs.hit_return"), at: 2448)
            _ = try c.accept(at: 2472, size: 2)
        }
    }

    /// 行順編成 1 レコードの読込 (末尾空白は書込時に落ちているので size まで空白で埋める)
    static func readLine(_ s: Session, _ path: String, size: Int) -> [UInt8]? {
        guard let raw = s.store.readRaw(path) else { return nil }
        var line = Array(raw.prefix { $0 != 0x0a })
        if raw.isEmpty { return [] }
        if line.count > size { line = Array(line.prefix(size)) }
        while line.count < size { line.append(0x20) }
        return line
    }

    static func writeLine(_ s: Session, _ path: String, _ data: [UInt8]) {
        var d = data
        while let l = d.last, l == 0x20 { d.removeLast() }
        s.store.writeRaw(path, d + [0x0a])
    }
}

/// irsub1.cbl: 勘定科目ファイル (acnts.dat) の入出力
enum IRSub1 {
    enum Mode { case input, io, output }
    enum StartMode { case equal, notLess, greater, none }

    private static func file(_ s: Session) -> IndexedFile {
        let ctx = IRS.context(s)
        if let f = ctx.nlFile { return f }
        let f = IndexedFile(s.store, path: s.irsDir + ctx.file1, layout: IRS.nlLayout, keyOffset: 0, keyLength: 10)
        ctx.nlFile = f
        return f
    }

    /// fn-open。戻り値は we-error
    @discardableResult
    static func open(_ s: Session, _ mode: Mode) throws -> Int {
        let ctx = IRS.context(s)
        let f = IndexedFile(s.store, path: s.irsDir + ctx.file1, layout: IRS.nlLayout, keyOffset: 0, keyLength: 10)
        ctx.nlFile = f
        switch mode {
        case .input, .io: f.open()
        case .output: f.openOutput()
        }
        if f.status != "00" {
            s.console.display(s.t("irs.sub1_open_fail"), at: 2401, color: 4)
            try IRS.displayFileError(s, f.status)
            return 1
        }
        return 0
    }

    static func close(_ s: Session) { file(s).close() }

    /// fn-read-indexed (副科目レコードなら主科目側の実体まで辿る)
    static func readIndexed(_ s: Session, _ nl: inout Record) -> Int {
        let f = file(s)
        while true {
            guard f.isOpen, let r = f.read(key: nl.raw("key")) else { return 2 }
            nl = r
            if nl.str("type") == "S" {
                nl.setInt("sub-nominal", nl.int("owning"))
                nl.setInt("owning", nl.int("pointer"))
                continue
            }
            return 0
        }
    }

    /// fn-read-next (副科目ポインタレコードは読み飛ばす)
    static func readNext(_ s: Session, _ nl: inout Record) -> Int {
        let f = file(s)
        while true {
            guard f.isOpen, let r = f.readNext() else { return 3 }
            nl = r
            if nl.str("type") == "S" { continue }
            return 0
        }
    }

    /// fn-write
    static func write(_ s: Session, _ nl: inout Record) throws {
        let f = file(s)
        let c = s.console
        if f.write(nl) != "00" {
            c.display(s.t("irs.sub1_exists_owning"), at: 2401, color: 4)
            _ = try c.accept(at: 2438, size: 1)
        }
        if nl.str("type") == "O" { return }
        nl["type"] = "O"
        if f.rewrite(nl) != "00" {
            c.display(s.t("irs.sub1_exists_rewrite"), at: 2401, color: 4)
            _ = try c.accept(at: 2432, size: 1)
        }
        nl.setInt("pointer", nl.int("owning"))
        nl.setInt("owning", nl.int("sub-nominal"))
        nl.setInt("sub-nominal", 0)
        nl["type"] = "S"
        if f.write(nl) != "00" {
            c.display(s.t("irs.sub1_exists_sub"), at: 2401, color: 4)
            _ = try c.accept(at: 2435, size: 1)
        }
        nl.setInt("sub-nominal", nl.int("owning"))
        nl.setInt("owning", nl.int("pointer"))
    }

    /// fn-delete (直前に読んだレコード = FD の key-1 を削除する。nl-key は読込後変更されない前提)
    static func delete(_ s: Session, _ nl: inout Record, fdKey: [UInt8]? = nil) {
        let f = file(s)
        f.delete(key: fdKey ?? nl.raw("key"))
        if nl.str("type") == "O" { return }
        nl.setInt("owning", nl.int("sub-nominal"))
        nl.setInt("sub-nominal", 0)
        f.delete(key: nl.raw("key"))
    }

    /// fn-re-write
    static func rewrite(_ s: Session, _ nl: Record) { file(s).rewrite(nl) }

    /// fn-start (+ 続けて次レコードを読む)。key-1 の sub-nominal は 0 にされる。
    static func start(_ s: Session, _ nl: inout Record, _ mode: StartMode) -> Int {
        let f = file(s)
        guard f.isOpen else { return 2 }
        var key = nl.raw("key")
        for i in 5..<10 { key[i] = 0x30 }
        switch mode {
        case .equal:
            guard s.store.read(f.path, key: key) != nil else { return 2 }
            f.start(notLessThan: key)
        case .notLess:
            if !f.start(notLessThan: key) { return 2 }
        case .greater:
            guard let r = s.store.seek(f.path, key: key, inclusive: false) else { return 2 }
            f.start(notLessThan: r.key)
        case .none: break
        }
        return readNext(s, &nl)
    }
}

/// irsub2.cbl: システムファイル (system.dat) の入出力
enum IRSub2 {
    /// 読込。成功で true (we-error = 0)
    static func read(_ s: Session) -> Bool {
        let ctx = IRS.context(s)
        guard let line = IRS.readLine(s, s.irsDir + "system.dat", size: 312), !line.isEmpty else { return false }
        ctx.sys = Record(IRS.systemLayout, bytes: line)
        ctx.fileNames = ctx.sys.str("system-files")
        return true
    }

    static func write(_ s: Session) {
        IRS.writeLine(s, s.irsDir + "system.dat", IRS.context(s).sys.bytes)
    }
}

/// irsub3.cbl: デフォルト科目ファイル (dflt.dat) の入出力
enum IRSub3 {
    static func write(_ s: Session) {
        let ctx = IRS.context(s)
        IRS.writeLine(s, s.irsDir + ctx.file3, ctx.dflt)
    }

    /// 読込。戻り値は we-error
    @discardableResult
    static func read(_ s: Session) throws -> Int {
        let ctx = IRS.context(s)
        guard let line = IRS.readLine(s, s.irsDir + ctx.file3, size: IRS.defaultSize) else {
            s.console.display(s.t("irs.sub3_open_fail"), at: 2301, color: 4)
            try IRS.displayFileError(s, "35")
            return 1
        }
        if !line.isEmpty { ctx.dflt = line }
        return 0
    }
}

/// irsub4.cbl: 転記ファイル (post.dat) の入出力
enum IRSub4 {
    private static func file(_ s: Session) -> IndexedFile {
        let ctx = IRS.context(s)
        if let f = ctx.postFile { return f }
        let f = IndexedFile(s.store, path: s.irsDir + "post.dat", layout: IRS.postLayout, keyOffset: 0, keyLength: 5)
        ctx.postFile = f
        return f
    }

    @discardableResult
    static func open(_ s: Session, _ mode: IRSub1.Mode) throws -> Int {
        let ctx = IRS.context(s)
        let f = IndexedFile(s.store, path: s.irsDir + "post.dat", layout: IRS.postLayout, keyOffset: 0, keyLength: 5)
        ctx.postFile = f
        switch mode {
        case .input, .io: f.open()
        case .output: f.openOutput()
        }
        if f.status != "00" {
            s.console.display(s.t("irs.sub4_open_fail"), at: 2301, color: 4)
            try IRS.displayFileError(s, f.status)
            return 1
        }
        return 0
    }

    static func close(_ s: Session) { file(s).close() }

    static func readIndexed(_ s: Session, _ post: inout Record) -> Int {
        let f = file(s)
        guard f.isOpen, let r = f.read(key: post.raw("key")) else { return 2 }
        post = r
        return 0
    }

    static func readNext(_ s: Session, _ post: inout Record) -> Int {
        let f = file(s)
        guard f.isOpen, let r = f.readNext() else { return 3 }
        post = r
        return 0
    }

    /// fn-write: キー重複なら post-key を 1 ずつ進めて再試行
    static func write(_ s: Session, _ post: inout Record) {
        let f = file(s)
        guard f.isOpen else { return }
        var guardCount = 0
        while f.write(post) != "00" {
            post.setInt("key", (post.int("key") + 1) % 100000)
            guardCount += 1
            if guardCount > 100000 { return }
        }
    }

    static func delete(_ s: Session, key: [UInt8]) { file(s).delete(key: key) }
    static func rewrite(_ s: Session, _ post: Record) { file(s).rewrite(post) }

    static func start(_ s: Session, _ post: inout Record, _ mode: IRSub1.StartMode) -> Int {
        let f = file(s)
        guard f.isOpen else { return 2 }
        let key = post.raw("key")
        switch mode {
        case .equal:
            guard s.store.read(f.path, key: key) != nil else { return 2 }
            f.start(notLessThan: key)
        case .notLess:
            if !f.start(notLessThan: key) { return 2 }
        case .greater:
            guard let r = s.store.seek(f.path, key: key, inclusive: false) else { return 2 }
            f.start(notLessThan: r.key)
        case .none: break
        }
        return readNext(s, &post)
    }
}

/// irsub5.cbl: 決算書設定ファイル (final.dat) の入出力
enum IRSub5 {
    static let path = "final.dat"

    static func write(_ s: Session, _ final: [UInt8]) {
        IRS.writeLine(s, s.irsDir + path, final)
    }

    /// 読込。無ければ初期化した final-record を書き出す。
    static func read(_ s: Session, _ final: inout [UInt8]) {
        guard let line = IRS.readLine(s, s.irsDir + path, size: IRS.finalSize) else {
            final = [UInt8](repeating: 0x20, count: IRS.finalSize)
            IRS.writeLine(s, s.irsDir + path, final)
            return
        }
        if !line.isEmpty { final = line }
    }
}

extension IRS {
    /// 行順編成の印刷ファイル (WRITE ... AFTER n / AFTER PAGE)
    final class Printer {
        let s: Session
        let path: String
        init(_ s: Session, _ name: String, extend: Bool = false) {
            self.s = s
            path = s.irsDir + name
            if !extend { s.store.writeRaw(path, []) }
        }
        func write(_ line: String, after n: Int = 1) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0a, count: n) + SJIS.encode(Cobol.rtrim(line), size: CellWidth.of(Cobol.rtrim(line))))
        }
        func writePage(_ line: String) {
            s.store.appendRaw(path, [0x0c] + SJIS.encode(Cobol.rtrim(line), size: CellWidth.of(Cobol.rtrim(line))))
        }
        /// WRITE (AFTER 指定なし): 行 + 改行
        func writeLine(_ line: String) {
            s.store.appendRaw(path, SJIS.encode(Cobol.rtrim(line), size: CellWidth.of(Cobol.rtrim(line))) + [0x0a])
        }
        /// CALL "SYSTEM" using Print-Report (lpr) 相当: 端末内では帳票として通知する
        func spool() {
            // CLOSE 時、最後の WRITE が AFTER 指定なら行末の改行が 1 つ補われる
            if let b = s.store.readRaw(path), let last = b.last, last != 0x0a { s.store.appendRaw(path, [0x0a]) }
            s.onReport?(path)
        }
    }

    /// 画面見出し共通 (プログラム名、反転タイトル、処理日)
    static func heading(_ s: Session, prog: String, titleKey: String, col: Int) {
        let c = s.console
        c.eraseScreen()
        c.display(prog, at: 101, color: 2)
        c.display(s.t(titleKey), at: 100 + col, color: 7, reverse: true)
        c.display(context(s).sys.str("run-date"), at: 173, color: 2)
    }

    /// Client - / Start date - / End date - の行 (3 行目)
    static func clientLine(_ s: Session, clientSize: Int = 24) {
        let c = s.console
        let sys = context(s).sys
        c.display(s.t("irs.client"), at: 301, color: 2)
        c.display(Cobol.x(sys.str("client"), clientSize), at: 310, color: 3)
        c.display(s.t("irs.start_date"), at: 339, color: 2)
        c.display(sys.str("start-date"), at: 352, color: 3)
        c.display(s.t("irs.end_date"), at: 362, color: 2)
        c.display(sys.str("end-date"), at: 373, color: 3)
    }

    static func num(_ str: String) -> Int { Int(Cobol.numval(str).0) }
    static func zeroAmounts(_ nl: inout Record) {
        nl.setInt("dr", 0); nl.setInt("cr", 0)
        for i in 1...4 { nl.setInt("dr-last-\(i)", 0); nl.setInt("cr-last-\(i)", 0) }
    }
}
