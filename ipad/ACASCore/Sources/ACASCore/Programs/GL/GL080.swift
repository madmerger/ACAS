import Foundation

/// general/gl080.cbl: End Of Cycle Processing (バッチ検査、仕訳のアーカイブ/削除、posting.dat の圧縮、期末処理)
enum GL080 {
    static let progName = "gl080 (3.00.02)"
    static let workRecordSize = 96

    final class WS {
        let s: Session
        let c: Console
        let batchFile: IndexedFile
        var batch = Record(GL.batchLayout, bytes: [UInt8](repeating: 0, count: GL.batchLayout.size))
        var a = 0, y = 0
        var lin2 = "00"
        var file2 = ""
        init(_ s: Session) { self.s = s; c = s.console; batchFile = GL.batchFile(s) }
        func d(_ t: String, _ at: Int, _ color: UInt8 = 2) { c.display(t, at: at, color: color) }
        func t(_ k: String) -> String { s.t("gl080." + k) }
        /// read batch-file next (未オープンなら at end にならず読み続ける)
        func eachBatch(_ body: () throws -> Void) throws {
            while true {
                switch batchFile.glNext() {
                case .ok(let r): batch = r
                case .miss: return
                case .error: try GL.hang(s)
                }
                try body()
            }
        }
    }

    /// FileStat-Msgs.cpy
    static func statusMessage(_ s: Session, _ status: String) -> String {
        let known = ["00", "02", "04", "05", "07", "10", "14", "21", "22", "23", "30", "31", "34", "35", "37", "38", "39",
                     "41", "42", "43", "44", "46", "47", "48", "49", "51", "52", "57", "61", "91"]
        return known.contains(status) ? Cobol.x(s.t("gl080.fs_" + status), 25) : Cobol.x("", 25)
    }

    static func run(_ s: Session) throws {
        let ws = WS(s), c = ws.c
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        ws.d(ws.t("title"), 130)
        let dates = GLDates(s)
        dates.zz070()
        ws.d(dates.wsDate, 171)
        ws.d(s.sys.str("usera"), 301, 3)
        ws.a = 0
        ws.lin2 = Cobol.z(s.sys.int("scycle") % 100, 2)
        ws.d(ws.t("gl115"), 801, 3)
        c.display(ws.t("gl116"), at: 901, color: 3, highlight: true)
        c.display(ws.t("gl117"), at: 1001, color: 3, highlight: true)
        let reply = try c.accept(at: 1065, size: 1, initial: " ", options: [.update, .auto])
        if c.crtStatus == GL050.esc || reply == "A" || reply == "a" { return }

        c.display(ws.t("phase1"), at: 801, color: 2, eraseEOS: true)
        try gl080a(ws)
        if ws.a == 1 { return }
        if s.sys.str("arch") == "Y" {
            ws.d(ws.t("phase2"), 801)
            try gl080b(ws)
        } else {
            ws.d(ws.t("phase3"), 801)
            try gl080c(ws)
        }
        try compressPost(ws)
        let scycle = s.sys.int("scycle"), period = s.sys.int("period")
        if ws.a == 9 || scycle < period { return }
        if period != 0 {
            // divide scycle by period giving a rounded (a: pic 99)
            ws.a = Int(((2 * scycle + period) / (2 * period)) % 100)
        }
        ws.y = Int((Int64(ws.a) * period) % 100)
        if scycle != Int64(ws.y) { return }
        s.sys.setInt("scycle", scycle + 1)

        ws.d(ws.t("phase5"), 801)
        let ledgerFile = GL.ledgerFile(s)
        ledgerFile.open()
        let q1 = GL.ledgerLayout.offset("ledger-q1")
        while true {
            guard case .ok(let rec) = ledgerFile.glNext() else { break }
            var r = rec
            // ledger-q (a): 添字は検査されない
            let off = q1 + (ws.a - 1) * 6
            if off >= 0 && off + 6 <= r.bytes.count { r.bytes.replaceSubrange(off..<(off + 6), with: r.raw("ledger-balance")) }
            if s.sys.int("current-quarter") == 4 { r.setRaw("ledger-last", r.raw("ledger-balance")) }
            ledgerFile.rewrite(r)
        }
        ledgerFile.close()
        var q = (s.sys.int("current-quarter") + 1) % 10
        if q == 5 { q = 1 }
        s.sys.setInt("current-quarter", q)
        if period == 3 && s.sys.int("scycle") > 12 { s.sys.setInt("scycle", 1) }
        if period == 13 && s.sys.int("scycle") > 52 { s.sys.setInt("scycle", 1) }
    }

    /// 当サイクルに未締め・未転記のバッチがあれば a = 1
    static func gl080a(_ ws: WS) throws {
        ws.d(ws.t("checking"), 2301)
        ws.batchFile.open()
        try ws.eachBatch {
            if ws.batch.int("bcycle") != ws.s.sys.int("scycle") { return }
            if ws.batch.int("batch-status") != 1 && ws.batch.int("cleared-status") != 1 { ws.a = 1 }
        }
        ws.batchFile.close()
    }

    static func progress(_ ws: WS, _ key: String) {
        ws.d(ws.t(key), 2301)
        ws.d(ws.lin2, 2330)
        ws.d(ws.t("batch"), 2334)
        ws.d(ws.t("item"), 2352)
    }

    static func closeBatch(_ ws: WS) {
        ws.batch.setInt("cleared-status", 2)
        ws.batch.setInt("stored", ws.s.sys.int("run-date"))
        ws.batch.setInt("batch-start", 0)
        ws.batchFile.rewrite(ws.batch)
    }

    /// 仕訳を archive (line sequential) へ書き出して posting-file から削除
    static func gl080b(_ ws: WS) throws {
        progress(ws, "archiving")
        try diskChange(ws)
        if ws.a == 9 { return }
        if !ws.s.store.exists(ws.file2) { ws.s.store.writeRaw(ws.file2, []) }
        ws.batchFile.open()
        try ws.eachBatch {
            if ws.batch.int("bcycle") != ws.s.sys.int("scycle") { return }
            try process(ws, archive: true)
            closeBatch(ws)
        }
        ws.batchFile.close()
    }

    static func gl080c(_ ws: WS) throws {
        progress(ws, "deleting")
        ws.batchFile.open()
        try ws.eachBatch {
            if ws.batch.int("bcycle") != ws.s.sys.int("scycle") { return }
            try process(ws, archive: false)
            closeBatch(ws)
        }
        ws.batchFile.close()
    }

    /// arc-process / del-process
    static func process(_ ws: WS, archive: Bool) throws {
        let s = ws.s
        let nos = Cobol.z(ws.batch.int("batch-nos"), 5)
        if archive { ws.d(nos, 2345) } else { ws.c.display(nos, at: 2345) }
        if !GL.postingFile(s).exists { try GL.hang(s) }
        var rrn = 0
        while let n = GL.relNext(s, after: rrn) {
            rrn = n.rrn
            let p = Record(GL.postingLayout, bytes: n.data)
            if p.raw("post-key").allSatisfy({ $0 == 0x30 }) || p.int("batch") != ws.batch.int("batch-nos") { continue }
            ws.d(Cobol.z(p.int("post-number"), 5), 2364)
            if archive {
                let side = p.str("post-vat-side")
                func line(_ ac: Int64, _ pc: Int64, _ amount: Int64, _ cac: Int64?, _ cpc: Int64?) {
                    var r = arc
                    r.setInt("arc-ac", ac); r.setInt("arc-pc", pc)
                    r.setInt("arc-amount", Cobol.truncate(amount, digits: 10, signed: true))
                    if let cac, let cpc { r.setInt("arc-c-ac", cac); r.setInt("arc-c-pc", cpc) }
                    arc = r
                    s.store.appendRaw(ws.file2, r.bytes + [0x0a])
                }
                var arc = Record(arcLayout, bytes: lastArc(ws))
                arc.setInt("arc-batch", p.int("batch"))
                arc.setInt("arc-post", p.int("post-number"))
                arc.set("arc-code", p.str("post-code"))
                arc.set("arc-date", p.str("post-date"))
                arc.set("arc-legend", p.str("post-legend"))
                let gross = Cobol.truncate(p.int("post-amount") + p.int("vat-amount"), digits: 10, signed: true)
                line(p.int("post-dr"), p.int("dr-pc"), side == "CR" ? gross : p.int("post-amount"), p.int("post-cr"), p.int("cr-pc"))
                line(p.int("post-cr"), p.int("cr-pc"), -(side == "DR" ? gross : p.int("post-amount")), p.int("post-dr"), p.int("dr-pc"))
                if p.int("vat-ac") != 0 && p.int("vat-amount") != 0 {
                    line(p.int("vat-ac"), p.int("vat-pc"), side == "CR" ? -p.int("vat-amount") : p.int("vat-amount"), nil, nil)
                }
                ws.s.shared["gl080.arc"] = arc.bytes
            }
            GL.relDelete(s, rrn)
        }
    }

    static let arcLayout = Layout("arc-trans-record", [
        ("arc-batch", .n9(digits: 5, scale: 0, signed: false)),
        ("arc-post", .n9(digits: 5, scale: 0, signed: false)),
        ("arc-code", .x(2)),
        ("arc-date", .x(8)),
        ("arc-ac", .n9(digits: 6, scale: 0, signed: false)),
        ("arc-pc", .n9(digits: 2, scale: 0, signed: false)),
        ("arc-amount", .n9(digits: 10, scale: 2, signed: true)),
        ("arc-legend", .x(32)),
        ("arc-c-ac", .n9(digits: 6, scale: 0, signed: false)),
        ("arc-c-pc", .n9(digits: 2, scale: 0, signed: false)),
    ])
    /// レコード域は呼び出しの間保持される (VAT 行は直前の相手勘定を残す)
    static func lastArc(_ ws: WS) -> [UInt8] {
        (ws.s.shared["gl080.arc"] as? [UInt8]) ?? [UInt8](repeating: 0, count: arcLayout.size)
    }

    /// disk-change: アーカイブ先のパスを確認する
    static func diskChange(_ ws: WS) throws {
        let s = ws.s, c = ws.c
        // file-24 + "archives" + 区切り + file-2 (ソースのまま)
        ws.file2 = GLTrans.archivesPath(s, GLTrans.file2(s))
        s.shared["gl.file-2"] = ws.file2
        c.display(ws.t("gl115"), at: 1201, color: 2, eraseEOL: true)
        c.display(ws.t("gl114"), at: 1301, color: 2, eraseEOL: true)
        while true {
            ws.a = Int(Cobol.moveNumeric(try c.accept(at: 1369, size: 2, kind: .numeric), digits: 2, scale: 0))
            if ws.a == 9 { return }
            if ws.a != 0 { continue }
            c.display(ws.t("current_path"), at: 1401, color: 2, eraseEOL: true)
            c.display(ws.file2, at: 1501, color: 2, eraseEOL: true)
            ws.file2 = Cobol.rtrim(try c.accept(at: 1501, size: 532, initial: ws.file2, options: [.update], color: 2))
            s.shared["gl.file-2"] = ws.file2
            if ws.file2.isEmpty || ws.file2.hasPrefix(" ") { continue }
            return
        }
    }

    /// compress-post: posting-file を work-file 経由で詰め直す
    static func compressPost(_ ws: WS) throws {
        let s = ws.s, c = ws.c
        ws.d(ws.t("phase4"), 801)
        if GL.postingLayout.size != workRecordSize {
            ws.d(ws.t("gl112"), 1001, 3)
            ws.d(ws.t("gl113"), 1101, 3)
            ws.d(ws.t("gl011"), 1201, 3)
            _ = try c.accept(at: 1227, size: 1)
            throw StopRun()
        }
        let work = s.ledgers + "work.tmp"
        guard GL.postingFile(s).exists else {
            // 未オープンの posting-file の READ は状態 47
            s.store.writeRaw(work, [])
            ws.d(ws.t("gl111"), 1501)
            ws.d("47", 1539)
            c.display(statusMessage(s, "47"), at: 1542)
            c.display(ws.t("gl011"), at: 1601, color: 2, eraseEOL: true)
            _ = try c.accept(at: 1627, size: 1)
            c.display(" ", at: 1601, eraseEOL: true)
            return
        }
        var recs: [[UInt8]] = []
        var rrn = 0
        while let n = GL.relNext(s, after: rrn) { rrn = n.rrn; recs.append(n.data) }
        s.store.writeRaw(work, recs.flatMap { $0 })
        s.store.writeRaw(s.ledgers + "posting.dat", [])
        for (i, r) in recs.enumerated() { GL.postingFile(s).write(i + 1, r) }
    }
}
