import Foundation

/// sales/sl050.cbl: Invoice Proof Report (未転記売上取引プルーフリスト)
public enum SalesProofReport {
    public static let exportPath = "ledgers/acas/prt-1"

    public struct Entry: Identifiable, Equatable {
        public let id: Int
        public let customer: String
        public let name: String
        public let net: Int64
        public let tax: Int64
        public var gross: Int64 { net + tax }
    }

    public enum Error: Swift.Error { case missingCompany, noTransactions }

    private struct Context {
        let store: FileStore
        let sys: Record
        let toDay: String
        var ledgers: String { "ledgers/acas/" }
    }
    static let progName = "SL050 (3.01.10)"

    // total-group (3) の 1 群内の添字 (comp-3 s9(8)v99 × 11)
    static let ded = 0, gds = 1, car = 2, net = 3, vat = 4, grs = 5, dis = 6, cvat = 7
    static let groupSize = 12

    final class WS {
        var error = 0
        var uDate = SalesProofRecords.spaces(10)
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
        var p: SalesProofRecords.Printer!
        var inv: IndexedFile!
    }

    static func cr(_ v: Int64) -> String { Pic.edit("z(6)9.99cr", value: v, scale: 2) }
    static func add(_ w: WS, _ a: Int, _ f: Int, _ v: Int64) {
        let i = (a - 1) * groupSize + f
        w.totals[i] = Cobol.truncate(w.totals[i] + v, digits: 10, signed: true)
    }
    static func total(_ w: WS, _ a: Int, _ f: Int) -> Int64 { w.totals[(a - 1) * groupSize + f] }

    public static func generate(in context: BusinessContext) throws -> [Entry] {
        let store = context.store
        let file = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        guard let bytes = file.read(1) else { throw Error.missingCompany }
        let sys = Record(SystemLayout.layout, bytes: bytes)
        guard sys.raw("file-statuses")[15] != 0x30, store.exists("ledgers/acas/invoice.dat") else {
            throw Error.noTransactions
        }
        let day = context.calendar.dateComponents([.day, .month, .year], from: context.now())
        let s = Context(store: store, sys: sys, toDay: String(format: "%02d/%02d/%04d", day.day!, day.month!, day.year!))
        let w = WS()
        var entries: [Entry] = []
        func r(_ k: String, _ n: Int) -> String { Cobol.x(label(k), n) }
        let pageLines = Int(s.sys.int("page-lines"))
        let sales = SalesProofRecords.salesFile(store)
        _ = sales.open()
        w.p = SalesProofRecords.Printer(store)
        w.p.open()
        headings1(s, w)
        w.inv = SalesProofRecords.invoiceFile(store)
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
            let pad = SalesProofRecords.spaces(46)
            w.lbOn = dedAmt != 0
            w.lb = pad + r("report.sl050.late_charge", 12) + SalesProofRecords.spaces(14) + cr(dedAmt)
            w.lcOn = hDiscount != 0
            w.lc = pad + r("report.sl050.discount", 12) + SalesProofRecords.spaces(14) + cr(hDiscount) + SalesProofRecords.spaces(11) + "0"
            w.ldOn = hCarriage != 0
            w.ld = pad + r("report.sl050.carriage", 12) + SalesProofRecords.spaces(14) + cr(hCarriage) + SalesProofRecords.spaces(11) + (hCVat == 0 ? "0" : "1")
            let extraDesc = Cobol.x(s.sys.str("extra-desc"), 12)
            w.leOn = hExtra != 0 && extraDesc != SalesProofRecords.spaces(12)
            w.le = pad + extraDesc + SalesProofRecords.spaces(14) + cr(hExtra) + SalesProofRecords.spaces(11) + (hEVat == 0 ? "0" : "1")
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
            entries.append(Entry(id: entries.count, customer: cust, name: name.trimmingCharacters(in: .whitespaces), net: lNet, tax: lVat))
            if w.lineCnt > pageLines - 2 { headings1(s, w) }
            let line5 = Pic.edit("z(7)9", value: ih.int("ih-invoice"), scale: 0) + " "
                + Cobol.x(convertedDate(s, ih.int("ih-date"), previous: &w.uDate), 11) + Cobol.x(cust, 8) + name + SalesProofRecords.spaces(5) + typeLit
                + cr(hNet) + SalesProofRecords.spaces(13) + cr(lNet) + cr(lVat) + cr(lNet + lVat)
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
        w.p.after(2, SalesProofRecords.spaces(36) + r("report.sl050.line7", 78))
        w.p.after(1, "")
        for a in 1...3 {
            w.p.after(1, SalesProofRecords.spaces(7) + r("report.sl050.total", 6) + r("report.sl050.group\(a)", 18)
                + cr(total(w, a, gds)) + cr(total(w, a, dis)) + cr(total(w, a, ded)) + cr(total(w, a, car))
                + cr(total(w, a, net)) + cr(total(w, a, vat)) + cr(total(w, a, grs)))
        }
        if w.error == 1 { w.p.after(2, label("report.sl050.missing")) }
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
        try w.p.close()
        return entries
    }

    private static func main12(_ s: Context, _ w: WS) {
        w.j += 1
        let line1 = Cobol.x(progName, 49) + Cobol.x(label("report.sl050.title"), 75) + Cobol.x(label("report.sl050.page"), 5)
            + Pic.edit("zz9", value: Int64(w.j % 1000), scale: 0)
        if w.j != 1 { w.p.afterPage(line1) } else { w.p.after(1, line1) }
        w.p.after(1, Cobol.x(s.sys.str("usera"), 49) + SalesProofRecords.spaces(73) + Cobol.x(Maps04.format(s.toDay, dateForm: Int(s.sys.int("date-form"))), 10))
    }

    private static func headings1(_ s: Context, _ w: WS) {
        main12(s, w)
        w.p.after(2, Cobol.x(label("report.sl050.line4a"), 66) + SalesProofRecords.spaces(9) + Cobol.x(label("report.sl050.line4b"), 57))
        w.p.after(1, "")
        w.lineCnt = 5
    }

    private static func analysisPrint(_ s: Context, _ w: WS, _ pageLines: Int) {
        if w.fsReply == 99 { return }
        guard let rec = w.inv.readNext() else { w.fsReply = 99; return }
        let il = Record(SalesProofRecords.ilLayout, bytes: Array(rec.bytes.prefix(80)))
        if il.str("il-product").hasPrefix("/") { return }
        var net = il.int("il-net"), vat = il.int("il-vat")
        if w.type == 3 { net = -net; vat = -vat }
        let k = Int(il.int("il-vat-code"))
        if k > 0 { add(w, w.a, cvat + k - 1, vat) }
        func r(_ key: String, _ n: Int) -> String { w.firstTime == "Y" ? Cobol.x(label(key), n) : SalesProofRecords.spaces(n) }
        let line = SalesProofRecords.spaces(46) + r("report.sl050.analysis", 12) + Cobol.x(il.str("il-pa"), 6) + r("report.sl050.value", 8)
            + cr(net) + "  " + r("report.sl050.vat_code", 9) + "\(k)"
        w.firstTime = "N"
        w.p.after(1, line)
        w.lineCnt += 1
        if w.lineCnt > pageLines { headings1(s, w) }
    }

    private static func convertedDate(_ context: Context, _ day: Int64, previous: inout String) -> String {
        if day > 0 { previous = Maps04.toDate(Int(day)) }
        return Maps04.format(previous, dateForm: Int(context.sys.int("date-form")))
    }

    private static func label(_ key: String) -> String { labels[key]! }

    private static let labels = [
        "report.sl050.title": "Unapplied Sales Transaction Report",
        "report.sl050.page": "Page ",
        "report.sl050.line4a": "  Number ---Date--- <------------Customer------------>  --Type--",
        "report.sl050.line4b": "Goods                 <---Net-->  <---Vat-->  <--Gross->",
        "report.sl050.unknown": "!! Customer Unknown",
        "report.sl050.late_charge": "Late Charge ",
        "report.sl050.discount": "Discount    ",
        "report.sl050.carriage": "Carriage    ",
        "report.sl050.receipt": "Receipt",
        "report.sl050.invoice": "Invoice",
        "report.sl050.cr_note": "Cr. Note",
        "report.sl050.line7": "Goods    Discount  Prompt Pay    Carriage         Net         Vat       Gross",
        "report.sl050.total": "Total",
        "report.sl050.group1": "Receipts",
        "report.sl050.group2": "Invoices",
        "report.sl050.group3": "Credit Notes",
        "report.sl050.missing": "Warning Record/s Missing In Sales File",
        "report.sl050.line9": "V.A.T. Reconciliation       Receipts       Invoices   Credit Notes",
        "report.sl050.vat_code": "Vat Code",
        "report.sl050.analysis": "Analysis",
        "report.sl050.value": "Value",
    ]
}
