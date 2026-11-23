import Foundation

/// sales/sl060.cbl: Invoice Posting & Report (請求書転記・転記リスト)
enum SLA060 {
    static let progName = "SL060 (3.01.14)"

    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static func n(_ name: String, _ digits: Int) -> (String, FieldType) { (name, .n9(digits: digits, scale: 0, signed: false)) }
    private static let bAmt = FieldType.comp3(digits: 11, scale: 2, signed: false)

    /// copybooks/fdbatch.cob
    static let batchLayout = Layout("batch-record", [
        n("ledger", 1), n("batch-nos", 5), n("items", 2), n("batch-status", 1), n("cleared-status", 1), n("bcycle", 2),
        ("entered", bl), ("proofed", bl), ("posted", bl), ("stored", bl),
        ("input-gross", bAmt), ("input-vat", bAmt), ("actual-gross", bAmt), ("actual-vat", bAmt),
        ("description", .x(24)), n("bdefault", 2), ("convention", .x(2)), n("batch-def-ac", 6), n("batch-def-pc", 2),
        ("batch-def-code", .x(2)), ("batch-def-vat", .x(1)), n("batch-start", 5),
    ])
    /// copybooks/fdpost.cob (98 バイト)
    static let postLayout = Layout("posting-record", [
        n("batch", 5), n("post-number", 5), ("post-code", .x(2)), ("post-date", .x(8)), n("post-dr", 6), n("dr-pc", 2),
        n("post-cr", 6), n("cr-pc", 2), ("post-amount", .n9(digits: 10, scale: 2, signed: true)), ("post-legend", .x(32)),
        n("vat-ac", 6), n("vat-pc", 2), ("post-vat-side", .x(2)), ("vat-amount", .n9(digits: 10, scale: 2, signed: true)),
    ])

    final class WS {
        var reply = " "
        var error = 0
        var work1: Int64 = 0, work2: Int64 = 0, workA: Int64 = 0, workB: Int64 = 0
        var firstPass = "Y"
        var j = 0
        var workNet: Int64 = 0, workVat: Int64 = 0, workGoods: Int64 = 0
        var totalNet = [Int64](repeating: 0, count: 4), totalVat = [Int64](repeating: 0, count: 4)
        var a = 0
        var lineCnt = 0
        var deduction: Int64 = 0, totalDeduct: Int64 = 0, totalMovDed: Int64 = 0
        var uDate = SLA.spaces(10)
        var rrn = 0
        var pageLines = 0
        // レコード領域 (FD は NUL 初期値)
        var sales = Record(SLA.salesLayout, bytes: [UInt8](repeating: 0, count: 300))
        var oi = Record(SLA.oiLayout, bytes: [UInt8](repeating: 0, count: 114))
        var si = Record(SLA.oiLayout)
        var batch = Record(batchLayout, bytes: [UInt8](repeating: 0, count: batchLayout.size))
        var post = Record(postLayout, bytes: [UInt8](repeating: 0, count: 98))
        var value = Record(SLA070.valueLayout)
        var salesFile: IndexedFile!, oi3: IndexedFile!, batchFile: IndexedFile!
        var posting: RelativeFile!
        var p: SLA.Printer!
    }

    static func m9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9, signed: true) }
    static func cr(_ v: Int64) -> String { Pic.edit("z(6)9.99cr", value: v, scale: 2) }
    static func r(_ s: Session, _ k: String, _ n: Int) -> String { Cobol.x(s.l10n.raw(k), n) }
    static func oiTotal(_ oi: Record) -> Int64 {
        oi.int("oi-net") + oi.int("oi-extra") + oi.int("oi-carriage") + oi.int("oi-vat") + oi.int("oi-discount")
            + oi.int("oi-e-vat") + oi.int("oi-c-vat") + oi.int("oi-deduct-amt") + oi.int("oi-deduct-vat")
    }
    static func gl(_ s: Session) -> Bool { s.sys.int("level-1") == 1 }
    static func irsUsed(_ s: Session) -> Bool { s.sys.str("irs-instead") == "Y" }
    static func evalMsg(_ s: Session, _ status: String) -> String { SLA.fileStatMsg(s, status) }

    static func run(_ s: Session) throws {
        let c = s.console
        let w = WS()
        w.pageLines = Int(s.sys.int("page-lines"))
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("sl060.title"), at: 131, color: 2)
        c.display(SLA.convertDate(s), at: 171, color: 2)
        while true {
            c.display(s.t("sl060.ok_to_post"), at: 812, color: 2)
            let x = Cobol.x(try c.accept(at: 855, size: 3, initial: "   ", options: [.update], color: 6).uppercased(), 3)
            if x == "NO " { return }
            if x == "YES" { break }
        }
        c.display(" ", at: 801, eraseEOL: true)
        s.sys.setInt("s-flag-i", 2)
        s.sys.setInt("s-flag-a", 1)
        s.sys["oi-3-flag"] = "Y"
        w.oi3 = SLA.openItemFile3(s)
        if SLA.fileStatus(s, 19) != 1 {
            w.oi3.openOutput()
            w.oi3.close()
            SLA.setFileStatus(s, 19, 1)
        }
        if gl(s) { blOpen(s, w) }
        w.salesFile = SLA.salesFile(s)
        // open i-o sales-file: 失敗時は declarative (use after error) → goback
        if !s.store.exists(w.salesFile.path) {
            try salesError(s, "35")
            return
        }
        _ = w.salesFile.open()
        w.p = SLA.Printer(s)
        w.p.open()
        c.display(s.t("sl060.posting"), at: 1201, color: 2, eraseEOL: true)
        c.display(s.t("sl060.phase1"), at: 1401, color: 2, eraseEOL: true)
        w.j = 0
        headings(s, w)
        w.totalNet = [0, 0, 0, 0]; w.totalVat = [0, 0, 0, 0]
        let oi2Path = s.ledgers + "openitm2.dat"
        // open input open-item-file-2: ファイルが無いと OPEN は失敗するが宣言部が無いのでそのまま進み、
        // READ は AT END にならず失敗し続ける (レコード領域は変わらない)。レガシー実測の挙動。
        let oi2 = s.store.readRaw(oi2Path)
        var oi2Pos = 0
        _ = w.oi3.open()
        var oi2Area = [UInt8](repeating: 0, count: 114)
        while true {
            if let d = oi2 {
                if oi2Pos + 114 > d.count { break }
                oi2Area = Array(d[oi2Pos..<(oi2Pos + 114)])
                oi2Pos += 114
            }
            w.oi = Record(SLA.oiLayout, bytes: oi2Area)
            let custRaw = w.oi.raw("oi-customer")
            let type = w.oi.int("oi-type")
            w.reply = " "
            var name: String
            if let sr = w.salesFile.read(key: custRaw) {
                w.sales = sr
                name = Cobol.x(sr.str("sales-name"), 25)
            } else {
                w.reply = "X"
                w.error = 1
                SLA.initialize(&w.sales)
                w.sales["sales-name"] = s.l10n.raw("report.sl060.unknown")
                w.sales.setRaw("sales-key", custRaw)
                name = Cobol.x(s.l10n.raw("report.sl060.unknown"), 25)
            }
            let nos = Pic.edit("z(7)9", value: Cobol.truncate(w.oi.int("oi-invoice"), digits: 8, signed: false), scale: 0) + " "
            let date = SLA.convertBin(s, w.oi.int("oi-date"), uDate: &w.uDate)
            w.a = Int(type)
            var typeLit = SLA.spaces(9)
            if type == 2 { typeLit = r(s, "report.sl060.invoice", 9) }
            else if type == 3 { typeLit = r(s, "report.sl060.cr_note", 9) }
            else if type == 1 { typeLit = r(s, "report.sl060.receipt", 9) }
            w.workVat = m9(w.oi.int("oi-vat") + w.oi.int("oi-c-vat") + w.oi.int("oi-e-vat") + w.oi.int("oi-deduct-vat"))
            w.workGoods = m9(w.oi.int("oi-net") + w.oi.int("oi-extra"))
            let lVat = w.workVat
            w.workNet = m9(w.oi.int("oi-net") + w.oi.int("oi-extra") + w.oi.int("oi-carriage") + w.oi.int("oi-discount") + w.oi.int("oi-deduct-amt"))
            let lNet = w.workNet
            if w.a >= 1 && w.a <= 3 {
                w.totalVat[w.a] = m9(w.totalVat[w.a] + w.workVat)
                w.totalNet[w.a] = m9(w.totalNet[w.a] + w.workNet)
            } else if w.a == 0 {
                // total-group (0) は直前の work-vat / work-goods に重なる (添字チェックなし: レガシーの癖)
                w.workGoods = m9(w.workGoods + w.workVat)
                w.workVat = m9(w.workVat + w.workNet)
            }
            w.work1 = m9(m9(w.workNet) + w.workVat)
            let lGross = w.work1
            w.deduction = 0
            if gl(s) { try blWrite(s, w) }
            let oldBal = w.sales.int("sales-current") - w.sales.int("sales-unapplied")
            let q = "turnover-q\(max(1, min(4, Int(s.sys.int("current-quarter")))))"
            func addTurnover() { w.sales.setInt(q, Cobol.truncate(w.sales.int(q) + w.workGoods, digits: 10, signed: true)) }
            func addCurrent(_ v: Int64) { w.sales.setInt("sales-current", Cobol.truncate(w.sales.int("sales-current") + v, digits: 10, signed: true)) }
            if type == 1 || type == 2 { salesComp(w) }
            if type == 1 {
                addTurnover()
                w.sales.setInt("sales-last-inv", w.oi.int("oi-date")); w.sales.setInt("sales-last-pay", w.oi.int("oi-date"))
            }
            if type == 2 {
                addTurnover()
                addCurrent(w.workVat + w.workNet)
                w.sales.setInt("sales-last-inv", w.oi.int("oi-date"))
            }
            if type == 3 {
                addTurnover()
                addCurrent(w.workVat + w.workNet)
                w.sales.setInt("sales-last-pay", w.oi.int("oi-date"))
                crNotes(w)
                creditComp(w)
            }
            let lDed = w.deduction == 0 ? SLA.spaces(7) : Pic.edit("zzz9.99", value: abs(w.deduction) % 1_000_000, scale: 2)
            w.totalDeduct = m9(w.totalDeduct + w.deduction)
            if w.sales.int("sales-status") == 0 { w.sales.setInt("sales-status", 1) }
            if w.sales.int("sales-current") < 0 {
                let cur = -w.sales.int("sales-current")
                w.sales.setInt("sales-unapplied", Cobol.truncate(w.sales.int("sales-unapplied") + cur, digits: 10, signed: true))
                w.sales.setInt("sales-current", 0)
            }
            let newBal = w.sales.int("sales-current") - w.sales.int("sales-unapplied")
            if w.reply == "X" {
                w.sales.setInt("sales-status", 1)
                if w.salesFile.write(w.sales) != "00" { try salesError(s, w.salesFile.status); return }
            } else {
                if w.salesFile.rewrite(w.sales) != "00" { try salesError(s, w.salesFile.status); return }
            }
            if w.oi3.write(w.oi) != "00" {
                let st = w.oi3.status
                c.display(s.t("sl060.sl130"), at: 1601)
                c.display(w.oi.str("oi-customer").replacingOccurrences(of: "\0", with: " "), at: 1701)
                c.display(nos, at: 1801)
                c.display("fs-reply = ", at: 1901)
                c.display(st, at: 1912)
                c.display(evalMsg(s, st), at: 1915)
                c.display(s.t("sl060.sl133"), at: 2401, color: 4)
                c.display(s.t("sl060.sl002"), at: 2412)
                _ = try c.accept(at: 2450, size: 1)
            }
            w.p.after(1, nos + Cobol.x(date, 11) + Cobol.x(w.oi.str("oi-customer"), 9) + name + "  " + typeLit
                + cr(oldBal) + cr(newBal) + lDed + cr(lNet) + cr(lVat) + cr(lGross))
            w.lineCnt += 1
            if w.lineCnt > w.pageLines { headings(s, w) }
        }
        // aa030-Main-End
        w.salesFile.close(); w.oi3.close()
        func line6(_ i: Int) -> String {
            SLA.spaces(11) + r(s, "report.sl060.total_posted", 14) + r(s, "report.sl060.group\(i)", 18)
                + Pic.edit("z(7)9.99cr", value: w.totalNet[i], scale: 2) + Pic.edit("z(7)9.99cr", value: w.totalVat[i], scale: 2)
                + Pic.edit("z(7)9.99cr", value: m9(w.totalNet[i] + w.totalVat[i]), scale: 2)
        }
        if w.lineCnt > w.pageLines - 7 { headings(s, w) }
        w.p.after(3, line6(1))
        w.p.after(2, line6(2))
        w.p.after(2, line6(3))
        w.p.after(2, r(s, "report.sl060.late_deductions", 43) + Pic.edit("z(7)9.99cr", value: w.totalDeduct, scale: 2))
        SLA.addSys4(s, 5, w.totalDeduct)
        if w.totalDeduct != 0 { analiseDeductions(s, w) }
        if gl(s) { try blClose(s, w) }
        _ = w.oi3.open()
        w.workB = 0
        c.display(s.t("sl060.phase2"), at: 1407, color: 2, eraseEOL: true)
        w.oi3.startFirst()
        while let rec = w.oi3.readNext() {
            w.oi = rec
            if w.oi.int("oi-status") == 1 { continue }
            if w.oi.int("oi-type") == 3 { try crSwop(s, w) }
        }
        s.store.writeRaw(oi2Path, [])
        w.oi3.close()
        if w.lineCnt > w.pageLines - 6 && SLA.fileStatus(s, 18) == 1 { newHeading(s, w) }
        if SLA.fileStatus(s, 18) == 1 {
            w.p.after(3, SLA.spaces(24) + r(s, "report.sl060.unapplied_cf", 32)
                + (w.workB == 0 ? SLA.spaces(11) : Pic.edit("z(7)9.99", value: abs(w.workB), scale: 2)))
        }
        SLA.addSys4(s, 6, w.workB)
        if w.error == 1 { w.p.after(3, s.l10n.raw("sl060.sl134")) }
        w.p.close()
        SLA.setFileStatus(s, 18, 0)
    }

    /// declaratives: use after error procedure on Sales-File
    static func salesError(_ s: Session, _ status: String) throws {
        let c = s.console
        c.display(s.t("sl060.sl135"), at: 23, 1)
        c.display(status, at: 23, 37)
        c.display(evalMsg(s, status), at: 23, 40)
        c.display(s.t("sl060.sl002"), at: 24, 1)
        _ = try c.accept(at: 24, 33, size: 1)
    }

    // MARK: ba000-Cr-Swop section

    static func crSwop(_ s: Session, _ w: WS) throws {
        let c = s.console
        w.work1 = m9(m9(oiTotal(w.oi)) + w.oi.int("oi-paid"))
        if w.work1 == 0 {
            c.display(s.t("sl060.sl131"), at: 2401, color: 4)
            _ = try c.accept(at: 2434, size: 1)
        }
        if SLA.fileStatus(s, 18) == 0 { newHeading(s, w) }
        w.oi.setInt("oi-status", 1)
        func bwz(_ pic: String, _ v: Int64, _ scale: Int, _ width: Int) -> String {
            v == 0 ? SLA.spaces(width) : Pic.edit(pic, value: abs(v), scale: scale)
        }
        let inv = Cobol.truncate(w.oi.int("oi-invoice"), digits: 8, signed: false)
        let crn = Cobol.truncate(w.oi.int("oi-cr"), digits: 8, signed: false)
        w.p.after(1, Cobol.x(w.oi.str("oi-customer"), 12) + (inv == 0 ? SLA.spaces(10) : Pic.edit("z(7)9", value: inv, scale: 0) + "  ")
            + SLA.spaces(4) + bwz("z(7)9.99", w.work1, 2, 11) + SLA.spaces(4) + bwz("z(7)9.99", w.oi.int("oi-paid"), 2, 11) + SLA.spaces(4)
            + (crn == 0 ? SLA.spaces(10) : Pic.edit("z(7)9", value: crn, scale: 0) + "  ") + SLA.spaces(4) + r(s, "report.sl060.cr_note7", 12))
        w.lineCnt += 1
        if w.lineCnt > w.pageLines { newHeading(s, w) }
        w.workB = m9(w.workB + w.work1)
        w.work1 = -w.work1
        w.oi.setInt("oi-paid", m9(w.oi.int("oi-paid") + w.work1))
        _ = w.oi3.rewrite(w.oi)
    }

    // MARK: 見出し

    static func line1(_ s: Session, _ w: WS) -> String {
        Cobol.x(progName, 54) + r(s, "report.sl060.title", 70) + r(s, "report.sl060.page", 5) + Pic.edit("zz9", value: Int64(w.j % 1000), scale: 0)
    }
    static func line2(_ s: Session) -> String { Cobol.x(s.sys.str("usera"), 54) + SLA.spaces(68) + Cobol.x(SLA.convertDate(s), 10) }

    static func newHeading(_ s: Session, _ w: WS) {
        if SLA.fileStatus(s, 18) == 0 { SLA.setFileStatus(s, 18, 1) }
        w.j += 1
        let line1a = SLA.spaces(56) + r(s, "report.sl060.unapplied", 18)
        if w.j != 1 {
            w.p.afterPage(line1(s, w))
            w.p.after(1, line2(s))
            w.p.after(1, line1a)
            w.p.after(1, "")
        } else {
            w.p.before(1, line1(s, w))
            w.p.before(1, line2(s))
            w.p.before(1, line1a)
        }
        w.p.after(1, r(s, "report.sl060.line4a", 82))
        w.p.after(1, "")
        w.lineCnt = 6
    }

    static func headings(_ s: Session, _ w: WS) {
        w.j += 1
        if w.j != 1 {
            w.p.afterPage(line1(s, w))
            w.p.after(1, line2(s))
            w.p.after(1, "")
        } else {
            w.p.before(1, line1(s, w))
            w.p.before(1, line2(s))
        }
        w.p.after(1, r(s, "report.sl060.line4a_main", 64) + r(s, "report.sl060.line4b_main", 68))
        w.p.after(1, "")
        w.lineCnt = 5
    }

    // MARK: 平均取引額

    static func salesComp(_ w: WS) {
        let act = w.sales.int("sales-activety"), avg = w.sales.int("sales-average")
        w.work2 = (act != 0 && avg != 0) ? act * avg : 0
        w.sales.setInt("sales-activety", act + 1)
        w.work2 = (w.work2 * 100 + w.workGoods) / 100
        let d = w.sales.int("sales-activety")
        if d != 0 { w.sales.setInt("sales-average", w.work2 / d) }
    }

    static func creditComp(_ w: WS) {
        let act = w.sales.int("sales-activety"), avg = w.sales.int("sales-average")
        w.work2 = (act != 0 && avg != 0) ? act * avg : 0
        if w.work2 != 0 {
            w.work2 = (w.work2 * 100 + w.workGoods) / 100
            w.sales.setInt("sales-average", w.work2 / act)
        }
    }

    // MARK: ba000-CR-Notes section

    static func crNotes(_ w: WS) {
        w.si = w.oi
        w.firstPass = "Y"
        var looping = w.oi3.start(notLessThan: SLA.oiKey(w.oi.str("oi-customer"), w.oi.int("oi-cr")))
        if looping {
            w.workB = 0
            if w.work1 < 0 { w.work1 = -w.work1 }
            w.work1 = m9(w.work1 - w.si.int("oi-paid"))
        }
        while true {
            if looping {
                // ba010-read-loop
                while let rec = w.oi3.readNext() {
                    w.oi = rec
                    if w.oi.int("oi-type") != 2 { continue }
                    if w.oi.str("oi-customer") != w.si.str("oi-customer") { break }
                    if w.oi.int("oi-status") == 1 { continue }
                    w.workB = m9(w.oi.int("oi-deduct-amt") + w.oi.int("oi-deduct-vat"))
                    let uBin = w.oi.int("oi-date") + 1 + w.oi.int("oi-deduct-days")
                    if uBin <= w.si.int("oi-date") { w.workB = 0 }
                    if w.si.int("oi-cr") == w.oi.int("oi-invoice") || w.firstPass == "N" { apportion(w) }
                    if w.work1 == 0 { break }
                }
            }
            // ba020-end-loop
            if w.work1 == 0 || w.firstPass != "Y" { break }
            w.firstPass = "N"
            if !w.oi3.start(notLessThan: SLA.oiKey(w.si.str("oi-customer"), 0)) { break }
            looping = true
        }
        w.oi = w.si
    }

    // MARK: ba000-Apportion section

    static func apportion(_ w: WS) {
        func add(_ rec: inout Record, _ f: String, _ v: Int64) { rec.setInt(f, m9(rec.int(f) + v)) }
        w.workA = m9(m9(oiTotal(w.oi)) - w.oi.int("oi-paid"))
        if w.workA == 0 {
            w.oi.setInt("oi-status", 1)
            _ = w.oi3.rewrite(w.oi)
            return
        }
        if w.workA <= 0 { return }
        w.workA = m9(w.workA - w.workB)
        if w.workA == w.work1 {
            add(&w.oi, "oi-paid", w.work1); add(&w.si, "oi-paid", w.work1); add(&w.oi, "oi-p-c", w.work1)
            w.work1 = 0
            clearInvoiceDeduct(w)
            w.oi.setInt("oi-status", 1); w.si.setInt("oi-status", 1)
        } else if w.workA > w.work1 {
            add(&w.oi, "oi-paid", w.work1); add(&w.si, "oi-paid", w.work1); add(&w.oi, "oi-p-c", w.work1)
            w.work1 = 0
            w.si.setInt("oi-status", 1)
        } else {
            add(&w.oi, "oi-paid", w.workA); add(&w.si, "oi-paid", w.workA); add(&w.oi, "oi-p-c", w.workA)
            w.work1 = m9(w.work1 - w.workA)
            clearInvoiceDeduct(w)
            w.oi.setInt("oi-status", 1)
        }
        if w.work1 == 0 { w.si.setInt("oi-status", 1) }
        _ = w.oi3.rewrite(w.oi)
    }

    static func clearInvoiceDeduct(_ w: WS) {
        if w.workB > 0 {
            w.sales.setInt("sales-current", Cobol.truncate(w.sales.int("sales-current") - w.workB, digits: 10, signed: true))
            w.deduction = m9(w.deduction + w.workB)
            w.totalMovDed = Cobol.truncate(w.totalMovDed + 1, digits: 5, signed: true)
            w.oi.setInt("oi-deduct-amt", 0); w.oi.setInt("oi-deduct-vat", 0)
        }
    }

    // MARK: ba000-Analise-Deductions section

    static func analiseDeductions(_ s: Session, _ w: WS) {
        let vf = SLA070.valueFile(s)
        _ = vf.open()
        defer { vf.close() }
        func sub() {
            for f in ["va-t-this", "va-t-year"] { w.value.setInt(f, Cobol.truncate(abs(w.value.int(f) - w.totalMovDed), digits: 5, signed: false)) }
            for f in ["va-v-this", "va-v-year"] { w.value.setInt(f, Cobol.truncate(w.value.int(f) - w.totalDeduct, digits: 10, signed: true)) }
            _ = vf.rewrite(w.value)
        }
        guard let v = vf.read(key: "Szd") else { return }
        w.value = v
        sub()
        guard let v2 = vf.read(key: "Sz ") else { return }
        w.value = v2
        sub()
    }

    // MARK: ca000 (GL / IRS 転記バッチ)

    static func blOpen(_ s: Session, _ w: WS) {
        w.batchFile = IndexedFile(s.store, path: s.ledgers + "batch.dat", layout: batchLayout, keyLength: 6)
        if w.batchFile.open() != "00" {
            w.batchFile.close()
            w.batchFile.openOutput()
        }
        w.batch.setInt("batch-nos", Cobol.truncate(s.sys.int("next-batch"), digits: 5, signed: false))
        w.batch.setInt("ledger", 3)
        s.sys.setInt("next-batch", s.sys.int("next-batch") + 1)
        w.batch.setInt("batch-status", 0); w.batch.setInt("cleared-status", 0)
        w.batch.setInt("bcycle", s.sys.int("scycle"))
        w.batch.setInt("entered", s.sys.int("run-date"))
        w.batch["description"] = s.l10n.raw("sl060.batch_desc")
        for f in ["bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"] { w.batch.setInt(f, 0) }
        w.batch["convention"] = "CR"
        w.batch["batch-def-code"] = "SL"
        w.batch["batch-def-vat"] = "O"
        w.batch.setInt("batch-start", Cobol.truncate(s.sys.int("postings") + 1, digits: 5, signed: false))
        if irsUsed(s) {
            // open extend irs-post-file (無ければ作成)
            let path = s.ledgers + "postings2irs.dat"
            if !s.store.exists(path) { s.store.writeRaw(path, []) }
        } else {
            w.posting = RelativeFile(s.store, path: s.ledgers + "posting.dat", recordSize: 98)
            if !w.posting.exists { s.store.writeRaw(w.posting.path, []) }
        }
        w.rrn = Int(w.batch.int("batch-start"))
    }

    static func blWrite(_ s: Session, _ w: WS) throws {
        let u = Array(Cobol.x(w.uDate, 10))
        w.post["post-date"] = String(u[0..<6]) + String(u[8..<10])
        w.post.setInt("batch", w.batch.int("batch-nos"))
        w.batch.setInt("items", (w.batch.int("items") + 1) % 100)
        w.post.setInt("post-number", w.batch.int("items"))
        w.post.setInt("post-amount", w.workNet)
        let m = Pic.edit("z(7)9", value: Cobol.truncate(w.oi.int("oi-invoice"), digits: 8, signed: false), scale: 0)
        var legend = Array(Cobol.x(w.post.str("post-legend"), 32))
        var ptr = 1
        SLA.string(m.trimmingCharacters(in: .whitespaces) + " : " + Cobol.x(w.sales.str("sales-name"), 30), into: &legend, pointer: &ptr)
        w.post["post-legend"] = String(legend)
        w.post.setInt("post-dr", Cobol.truncate(s.sys.int("s-debtors"), digits: 6, signed: false))
        w.post.setInt("post-cr", Cobol.truncate(s.sys.int("sl-sales-ac"), digits: 6, signed: false))
        w.post.setInt("dr-pc", 0); w.post.setInt("cr-pc", 0); w.post.setInt("vat-pc", 0)
        w.post.setInt("vat-ac", Cobol.truncate(s.sys.int("vat-ac"), digits: 6, signed: false))
        let vat = Cobol.truncate(w.oi.int("oi-vat") + w.oi.int("oi-e-vat") + w.oi.int("oi-c-vat"), digits: 10, signed: true)
        w.post.setInt("vat-amount", vat)
        w.post["post-vat-side"] = "CR"
        w.post["post-code"] = "SL"
        func addU(_ f: String, _ v: Int64) { w.batch.setInt(f, Cobol.truncate(abs(w.batch.int(f) + v), digits: 11, signed: false)) }
        addU("input-gross", w.workNet); addU("actual-gross", w.workNet)
        addU("input-vat", vat); addU("actual-vat", vat)
        if irsUsed(s) {
            // irs-posting-record (fdpost-irs.cob, 84 バイト, sign leading)
            func lead(_ v: Int64) -> String {
                var d = Array(Cobol.z(abs(v) % 1_000_000_000, 9))
                if v < 0, let n = d[0].wholeNumberValue { d[0] = Character(UnicodeScalar(UInt8(0x70 + n))) }
                return String(d)
            }
            let rec = Cobol.z(w.post.int("batch"), 5) + Cobol.z(w.post.int("post-number"), 5) + "SL" + w.post.str("post-date")
                + Cobol.z(w.post.int("post-dr") % 100_000, 5) + Cobol.z(w.post.int("post-cr") % 100_000, 5)
                + lead(w.workNet) + Cobol.x(w.post.str("post-legend"), 32) + "32" + "CR" + lead(vat)
            s.store.appendRaw(s.ledgers + "postings2irs.dat", SJIS.encode(rec, size: 84))
        } else if w.posting.read(w.rrn) == nil {
            w.posting.write(w.rrn, w.post.bytes)
        }
        w.rrn += 1
        if w.batch.int("items") == 99 {
            try blClose(s, w)
            blOpen(s, w)
        }
    }

    static func blClose(_ s: Session, _ w: WS) throws {
        let c = s.console
        if w.batchFile.write(w.batch) != "00" {
            let st = w.batchFile.status
            c.display(s.t("sl060.sl132"), at: 2301)
            c.display(st, at: 2333)
            c.display(evalMsg(s, st), at: 2336)
            c.display(s.t("sl060.sl002"), at: 2401, color: 2)
            _ = try c.accept(at: 2433, size: 1)
        }
        s.sys.setInt("postings", Int64(w.rrn))
        w.batchFile.close()
    }
}
