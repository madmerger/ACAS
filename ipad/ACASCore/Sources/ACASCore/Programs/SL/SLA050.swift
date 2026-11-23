import Foundation

/// sales/sl050.cbl: Invoice Proof Report (未転記売上取引プルーフリスト)
enum SLA050 {
    static let progName = "SL050 (3.01.10)"

    // total-group (3) の 1 群内の添字 (comp-3 s9(8)v99 × 11)
    static let ded = 0, gds = 1, car = 2, net = 3, vat = 4, grs = 5, dis = 6, cvat = 7
    static let groupSize = 12

    final class WS {
        var error = 0
        var uDate = SLA.spaces(10)
        var j = 0
        var a = 0
        var firstTime = "Y"
        /// total-group occurs 3 を平坦に持つ (total-cvat (a, k) の k > 5 は次の群へはみ出す: レガシーの癖)
        var totals = [Int64](repeating: 0, count: 3 * groupSize + 8)
        var lineCnt = 0
        var fsReply = 0
        var type: Int64 = 0
        var lb = "", lc = "", ld = "", le = ""
        var lbOn = false, lcOn = false, ldOn = false, leOn = false
        var p: SLA.Printer!
        var inv: IndexedFile!
    }

    static func cr(_ v: Int64) -> String { Pic.edit("z(6)9.99cr", value: v, scale: 2) }
    static func add(_ w: WS, _ a: Int, _ f: Int, _ v: Int64) {
        let i = (a - 1) * groupSize + f
        w.totals[i] = Cobol.truncate(w.totals[i] + v, digits: 10, signed: true)
    }
    static func total(_ w: WS, _ a: Int, _ f: Int) -> Int64 { w.totals[(a - 1) * groupSize + f] }

    static func run(_ s: Session) throws {
        let c = s.console
        let w = WS()
        func r(_ k: String, _ n: Int) -> String { Cobol.x(s.l10n.raw(k), n) }
        let pageLines = Int(s.sys.int("page-lines"))
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("sl050.title"), at: 132, color: 2)
        c.display(SLA.convertDate(s), at: 171, color: 2)
        if SLA.fileStatus(s, 16) == 0 {
            c.display(s.t("sl050.sl120"), at: 501, color: 4)
            _ = try c.accept(at: 563, size: 1, color: 6)
            return
        }
        let sales = SLA.salesFile(s)
        _ = sales.open()
        w.p = SLA.Printer(s)
        w.p.open()
        headings1(s, w)
        w.inv = SLA.invoiceFile(s)
        _ = w.inv.open()
        w.inv.startFirst()
        while let rec = w.inv.readNext() {
            let ih = rec
            if ih.int("ih-test") != 0 { continue }
            let st = ih.str("ih-status")
            if st == "z" || st == "Z" { continue }
            w.type = ih.int("ih-type")
            if w.type == 4 { continue }
            let cust = ih.str("ih-customer")
            var name: String
            if let sr = sales.read(key: SJIS.encode(cust, size: 7)) {
                name = Cobol.x(sr.str("sales-name"), 25)
            } else {
                name = r("report.sl050.unknown", 25)
                w.error = 1
            }
            var hNet = ih.int("ih-net"), hExtra = ih.int("ih-extra"), hCarriage = ih.int("ih-carriage"), hVat = ih.int("ih-vat")
            var hCVat = ih.int("ih-c-vat"), hEVat = ih.int("ih-e-vat"), hDiscount = ih.int("ih-discount")
            var dedAmt = ih.int("ih-deduct-amt"), dedVat = ih.int("ih-deduct-vat")
            if w.type == 3 {
                hNet = -hNet; hExtra = -hExtra; hCarriage = -hCarriage; hVat = -hVat; hCVat = -hCVat
                hEVat = -hEVat; hDiscount = -hDiscount; dedAmt = -dedAmt; dedVat = -dedVat
            }
            let pad = SLA.spaces(46)
            w.lbOn = dedAmt != 0
            w.lb = pad + r("report.sl050.late_charge", 12) + SLA.spaces(14) + cr(dedAmt)
            w.lcOn = hDiscount != 0
            w.lc = pad + r("report.sl050.discount", 12) + SLA.spaces(14) + cr(hDiscount) + SLA.spaces(11) + "0"
            w.ldOn = hCarriage != 0
            w.ld = pad + r("report.sl050.carriage", 12) + SLA.spaces(14) + cr(hCarriage) + SLA.spaces(11) + (hCVat == 0 ? "0" : "1")
            let extraDesc = Cobol.x(s.sys.str("extra-desc"), 12)
            w.leOn = hExtra != 0 && extraDesc != SLA.spaces(12)
            w.le = pad + extraDesc + SLA.spaces(14) + cr(hExtra) + SLA.spaces(11) + (hEVat == 0 ? "0" : "1")
            w.a = 2
            var typeLit: String
            if w.type == 1 { typeLit = r("report.sl050.receipt", 14); w.a = 1 }
            else if w.type == 2 { typeLit = r("report.sl050.invoice", 14) }
            else { w.a = 3; typeLit = r("report.sl050.cr_note", 14) }
            add(w, w.a, cvat, hCVat + hEVat)
            let lVat = hVat + hCVat + hEVat + dedVat
            let lNet = hNet + hExtra + hCarriage + hDiscount + dedAmt
            add(w, w.a, gds, hNet)
            add(w, w.a, dis, hDiscount + hExtra)
            add(w, w.a, ded, dedAmt)
            add(w, w.a, car, hCarriage)
            add(w, w.a, vat, lVat)
            add(w, w.a, net, lNet)
            add(w, w.a, grs, lVat + lNet)
            if w.lineCnt > pageLines - 2 { headings1(s, w) }
            let line5 = Pic.edit("z(7)9", value: ih.int("ih-invoice"), scale: 0) + " "
                + Cobol.x(SLA.convertBin(s, ih.int("ih-date"), uDate: &w.uDate), 11) + Cobol.x(cust, 8) + name + SLA.spaces(5) + typeLit
                + cr(hNet) + SLA.spaces(13) + cr(lNet) + cr(lVat) + cr(lNet + lVat)
            w.p.after(2, line5)
            w.lineCnt += 2
            w.firstTime = "Y"
            w.fsReply = 0
            let lines = Int(ih.int("ih-lines"))
            if lines > 0 { for _ in 0..<lines { analysisPrint(s, w, pageLines) } }
            // extra-analysis
            if w.lineCnt > pageLines - 4 { headings1(s, w) }
            if w.lbOn { w.p.after(1, w.lb); w.lineCnt += 1 }
            if w.lcOn { w.p.after(1, w.lc); w.lineCnt += 1 }
            if w.ldOn { w.p.after(1, w.ld); w.lineCnt += 1 }
            if w.leOn { w.p.after(1, w.le); w.lineCnt += 1 }
        }
        // main-end
        sales.close()
        w.inv.close()
        if w.lineCnt < pageLines - 16 { w.p.after(3, "") } else { main12(s, w) }
        w.p.after(2, SLA.spaces(36) + r("report.sl050.line7", 78))
        w.p.after(1, "")
        for a in 1...3 {
            w.p.after(1, SLA.spaces(7) + r("report.sl050.total", 6) + r("report.sl050.group\(a)", 18)
                + cr(total(w, a, gds)) + cr(total(w, a, dis)) + cr(total(w, a, ded)) + cr(total(w, a, car))
                + cr(total(w, a, net)) + cr(total(w, a, vat)) + cr(total(w, a, grs)))
        }
        if w.error == 1 { w.p.after(2, s.l10n.raw("report.sl050.missing")) }
        w.p.after(2, r("report.sl050.line9", 70))
        w.p.after(1, "")
        func line8(_ i: Int) {
            w.p.after(1, r("report.sl050.vat_code", 9) + "\(i)" + "   " + Pic.edit("z9.99", value: s.sys.int("vat-rate-\(i)"), scale: 2)
                + Cobol.x("%", 5) + Pic.edit("z(7)9.99cr", value: total(w, 1, cvat + i - 1), scale: 2)
                + Pic.edit("z(9)9.99cr", value: total(w, 2, cvat + i - 1), scale: 2)
                + Pic.edit("z(9)9.99cr", value: total(w, 3, cvat + i - 1), scale: 2))
        }
        for i in 1...3 { line8(i) }
        if s.sys.int("vat-rate-4") != 0 || s.sys.int("vat-rate-5") != 0 { for i in 4...5 { line8(i) } }
        w.p.close()
    }

    static func main12(_ s: Session, _ w: WS) {
        w.j += 1
        let line1 = Cobol.x(progName, 49) + Cobol.x(s.l10n.raw("report.sl050.title"), 75) + Cobol.x(s.l10n.raw("report.sl050.page"), 5)
            + Pic.edit("zz9", value: Int64(w.j % 1000), scale: 0)
        if w.j != 1 { w.p.afterPage(line1) } else { w.p.after(1, line1) }
        w.p.after(1, Cobol.x(s.sys.str("usera"), 49) + SLA.spaces(73) + Cobol.x(SLA.convertDate(s), 10))
    }

    static func headings1(_ s: Session, _ w: WS) {
        main12(s, w)
        w.p.after(2, Cobol.x(s.l10n.raw("report.sl050.line4a"), 66) + SLA.spaces(9) + Cobol.x(s.l10n.raw("report.sl050.line4b"), 57))
        w.p.after(1, "")
        w.lineCnt = 5
    }

    static func analysisPrint(_ s: Session, _ w: WS, _ pageLines: Int) {
        if w.fsReply == 99 { return }
        guard let rec = w.inv.readNext() else { w.fsReply = 99; return }
        let il = Record(SLA.ilLayout, bytes: Array(rec.bytes.prefix(80)))
        if il.str("il-product").hasPrefix("/") { return }
        var net = il.int("il-net"), vat = il.int("il-vat")
        if w.type == 3 { net = -net; vat = -vat }
        let k = Int(il.int("il-vat-code"))
        if k > 0 { add(w, w.a, cvat + k - 1, vat) }
        func r(_ key: String, _ n: Int) -> String { w.firstTime == "Y" ? Cobol.x(s.l10n.raw(key), n) : SLA.spaces(n) }
        let line = SLA.spaces(46) + r("report.sl050.analysis", 12) + Cobol.x(il.str("il-pa"), 6) + r("report.sl050.value", 8)
            + cr(net) + "  " + r("report.sl050.vat_code", 9) + "\(k)"
        w.firstTime = "N"
        w.p.after(1, line)
        w.lineCnt += 1
        if w.lineCnt > pageLines { headings1(s, w) }
    }
}
