import Foundation

/// stock/st060.cbl: 在庫品目一括取込 (Stock File Importer)。
/// レガシーではメニューから外されている (stock.cbl の load06 は到達しない) 隠し機能。
/// Import-Mode は定数 1 (カンマ区切り) のため、到達しない ba020-Process-Regular は移植していない。
enum ST060 {
    static let progName = "ST060 (3.01.00)"
    private static let quotes: [UInt8] = [0x22, 0x27, 0x60]
    private static let sp: UInt8 = 0x20, zero: UInt8 = 0x30

    private static func isNumeric(_ b: [UInt8]) -> Bool { b.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }
    /// 部分参照 (pos:len)。範囲外は読まない
    private static func sub(_ b: [UInt8], _ pos: Int, _ len: Int) -> [UInt8] {
        guard len > 0, pos >= 1, pos <= b.count else { return [] }
        return Array(b[(pos - 1)..<min(b.count, pos - 1 + len)])
    }
    /// 英数字 MOVE (左詰め・空白埋め)
    private static func alpha(_ src: [UInt8], _ size: Int) -> [UInt8] {
        Array(src.prefix(size)) + [UInt8](repeating: sp, count: max(0, size - src.count))
    }
    private static func put(_ dst: inout [UInt8], _ pos: Int, _ src: [UInt8]) {
        for (i, v) in src.enumerated() where pos - 1 + i >= 0 && pos - 1 + i < dst.count { dst[pos - 1 + i] = v }
    }
    private static func value(_ b: [UInt8]) -> Int64 { b.reduce(0) { $0 * 10 + Int64($1 >= 0x30 && $1 <= 0x39 ? $1 - 0x30 : 0) } }

    /// UNSTRING Import-Record DELIMITED BY ... INTO 項目 COUNT c POINTER b
    private static func unstring(_ rec: [UInt8], _ delims: [UInt8], _ ptr: inout Int) -> [UInt8]? {
        guard ptr >= 1, ptr <= rec.count else { return nil }
        var i = ptr - 1
        while i < rec.count, !delims.contains(rec[i]) { i += 1 }
        let field = Array(rec[(ptr - 1)..<i])
        ptr = i < rec.count ? i + 2 : rec.count + 1
        return field
    }

    static func run(_ s: Session) throws {
        let c = s.console
        // zz010-Display-Heading
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.sys.str("usera"), at: 301, color: 3)
        c.display(ST.headingDate(s), at: 171, color: 2)
        c.display(s.t("st060.title"), at: 124, color: 2)
        c.display(s.t("st060.ask_file"), at: 701, color: 2)
        let file = try c.accept(at: 902, size: 64, initial: "", options: [.update], color: 6)
        try importStock(s, Cobol.rtrim(file))
    }

    /// ba000-Import-Stock
    private static func importStock(_ s: Session, _ path: String) throws {
        let c = s.console
        let f = ST.stockFile(s)
        if f.open() != "00" {
            f.close()
            f.openOutput(); f.close()
            _ = f.open()
            s.sys["stock-control"] = "Y"
            ST.setFileStatus(s, 11, 1)
        }
        if ST.fileStatus(s, 15) != 1 {
            s.processFunc = 1; s.subFunction = 1
            try s.call("sl070")
        }
        // open input Import-File (固定長 512 バイトの順編成)
        guard let data = s.store.readRaw(path) else {
            try fileError(s, "st060.st601", at: 2337, "35", highlight: false)
            f.close()
            return
        }
        var readCount = 0, writeCount = 0
        var abrevValue: Int64 = 0
        var cnt = 0
        var offset = 0
        var rec = ST.blankRecord()
        while offset < data.count {
            let imp = alpha(Array(data[offset..<min(data.count, offset + 512)]), 512)
            offset += 512
            readCount += 1
            ST.initialize(&rec)
            // ba030-Process-Comma
            var b = 1
            if let v = unstring(imp, [0x2c], &b) { rec.setRaw("stock-key", alpha(v, 13)); cnt = v.count }
            if cnt <= 7 {
                rec.setRaw("stock-abrev-key", alpha(rec.raw("stock-key"), 7))
            } else {
                abrevValue += 1
                rec.setRaw("stock-abrev-key", Array(Cobol.z(abrevValue % 10_000_000, 7).utf8))
            }
            rec["stock-supplier-p1"] = "A000011"
            var desc = [UInt8](repeating: sp, count: 36)
            if let v = unstring(imp, [0x2c], &b) { desc = alpha(v, 36) }
            if quotes.contains(desc[0]) {
                var k = 36
                while !(k < 4 || desc[k - 1] == desc[0]) { k -= 1 }
                rec.setRaw("stock-desc", alpha(sub(desc, 2, k - 2), 32))
            } else {
                rec.setRaw("stock-desc", alpha(desc, 32))
            }
            rec["stock-pa-code"] = "Pa1"
            rec["stock-sa-code"] = "Sa1"
            rec["stock-services-flag"] = "N"
            for name in ["stock-reorder-pnt", "stock-std-reorder", "stock-back-ordered", "stock-on-order", "stock-held", "stock-pre-sales"] {
                var x8 = alpha([zero], 8)          // move zero to ws-Number-X-8
                if let v = unstring(imp, [0x2c], &b) { x8 = alpha(v, 8); cnt = v.count }
                rec.setInt(name, formatNumber(x8, &cnt))
            }
            for name in ["stock-retail", "stock-cost", "stock-value"] {
                var x14 = alpha([zero], 14)
                let delims: [UInt8] = name == "stock-value" ? [0x2c, sp] : [0x2c]
                if let v = unstring(imp, delims, &b) { x14 = alpha(v, 14); cnt = v.count }
                let v4 = try formatAmount(s, x14, &cnt, f)     // 9(9)v9(4)
                let scale = ST.layout.fields[name]!.type.scale
                let digits = name == "stock-retail" ? 9 : 11
                rec.setInt(name, Cobol.rescale(v4, from: 4, to: scale) % Cobol.pow10(digits))
            }
            for name in ["stock-order-date", "stock-order-due"] {
                var d12 = [UInt8](repeating: sp, count: 12)   // move spaces to ws-stock-dates
                if let v = unstring(imp, [0x2c, sp], &b) { d12 = alpha(v, 12) }
                // zz050-Validate-Date (ws-Import-Date-Format = 1: UK)
                let bin = Maps04.toBinary(String(decoding: sub(d12, 2, 10), as: UTF8.self))
                if bin != 0 { rec.setInt(name, Int64(bin)) }
            }
            // ba040-Write-Stock
            let st = ST.write(f, rec)
            if st != "00" {
                try fileError(s, "st060.st000", at: 2338, st, highlight: true)
                f.close()
                return
            }
            writeCount += 1
        }
        // ba998-Main-End
        f.close()
        c.display(s.t("st060.imported"), at: 601, color: 2, eraseEOS: true)
        c.display(disp(readCount), at: 620, color: 2)
        c.display(s.t("st060.written"), at: 601, color: 2)
        c.display(disp(writeCount), at: 620, color: 2)
        c.display(s.t("st060.st603"), at: 801, color: 2)
        _ = try c.accept(at: 835, size: 1)
    }

    private static func disp(_ n: Int) -> String {
        let d = String(n % 10_000_000)
        return String(repeating: " ", count: 7 - d.count) + d
    }

    /// Declaratives: File-Error-On-IF / File-Error-On-Stock
    private static func fileError(_ s: Session, _ key: String, at: Int, _ status: String, highlight: Bool) throws {
        let c = s.console
        if highlight {
            c.display(s.t(key), at: 2301, color: 4, highlight: true)
            c.display(status, at: at, color: 4, highlight: true)
        } else {
            c.display(s.t(key), at: 2301)
            c.display(status, at: at)
        }
        c.display(Cobol.x(ST.evalStatus(s, status), 25), at: 2340)
        c.display(s.t("st060.st602"), at: 2401)
        _ = try c.accept(at: 2433, size: 1)
    }

    /// zz025-Format-Number / zz027-Clean-Number。cnt は UNSTRING の COUNT (c)
    private static func formatNumber(_ x8: [UInt8], _ cnt: inout Int) -> Int64 {
        var number = [UInt8](repeating: zero, count: 6)
        let c2 = cnt
        if quotes.contains(x8[0]) {
            cnt = 8
            while !(cnt < 3 || x8[cnt - 1] == x8[0]) { cnt -= 1 }
            // 英数字 → 9(6): 右詰め・左ゼロ埋め
            let src = sub(x8, 2, cnt - 2)
            let tail = Array(src.suffix(6))
            number = [UInt8](repeating: zero, count: 6 - tail.count) + tail
        } else {
            number = alpha(sub(x8, 1, c2), 6)
        }
        if !isNumeric(number) { number = [UInt8](repeating: zero, count: 6) }
        var chk = [UInt8](repeating: zero, count: 6)
        var d = 6
        while cnt >= 1 {
            if cnt <= 6, d >= 1 { chk[d - 1] = number[cnt - 1] }
            cnt -= 1
            d -= 1
        }
        return value(chk)
    }

    /// zz030-Format-Amount。戻り値は 9(9)v9(4) (スケール 4)
    private static func formatAmount(_ s: Session, _ x14: [UInt8], _ cnt: inout Int, _ f: IndexedFile) throws -> Int64 {
        let c = s.console
        var amount = [UInt8](repeating: zero, count: 13)
        var c2 = cnt
        func quit(_ key: String, _ extra: [UInt8]?) throws -> Never {
            c.display(s.t("st060.problem"), at: 1601, color: 3, highlight: true)
            c.display(String(decoding: x14, as: UTF8.self), at: 1623, color: 3)
            c.display(s.t(key), at: 1638, color: 3, highlight: true)
            if let e = extra { c.display(String(decoding: e, as: UTF8.self), at: 1651, color: 3) }
            c.display(s.t("st060.st604"), at: 1701, color: 3)
            _ = try c.accept(at: 1741, size: 1)
            f.close()
            throw StopRun()
        }
        if quotes.contains(x14[0]) {
            cnt = c2
            while !(cnt < 3 || (cnt <= 14 && x14[cnt - 1] == x14[0])) { cnt -= 1 }
            amount = alpha(sub(x14, 2, c2 - 2), 13)
            if cnt == c2 { c2 -= 2 } else { try quit("st060.bad_quotes", nil) }
        } else {
            amount = alpha(sub(x14, 1, c2), 13)
        }
        let amountLength = c2
        let e = amount.filter { $0 == 0x2e }.count
        if e != 0 {
            cnt = c2
            while !((cnt >= 1 && cnt <= 13 && amount[cnt - 1] == 0x2e) || cnt < 2) { cnt -= 1 }
        }
        var chk = [UInt8](repeating: zero, count: 13)
        if e != 0 && cnt > 1 {
            let pence = c2 - cnt, pounds = cnt - 1
            put(&chk, 10, sub(amount, cnt + 1, pence))
            put(&chk, 10 - pounds, sub(amount, 1, pounds))
        }
        if e == 0 {
            put(&chk, 10 - amountLength, sub(amount, 1, amountLength))
        }
        if !isNumeric(chk) { try quit("st060.has_become", chk) }
        return value(chk)
    }
}
