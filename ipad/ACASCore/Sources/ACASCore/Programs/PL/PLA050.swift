import Foundation

/// purchase/pl050.cbl: 仕入取引検証帳票 (Invoice Proof Report)
final class PLA050 {
    static let progName = "PL050 (3.01.04)"
    static func run(_ s: Session) throws { try PLA050(s).main() }

    let s: Session
    var c: Console { s.console }
    var j = 0
    var lineCnt = 0
    var printOut = " "
    var wsError = 0
    /// total-group (1..3): ded, gds, car, net, vat, grs, cvat(1..3)
    var ded = [Int64](repeating: 0, count: 4), gds = [Int64](repeating: 0, count: 4), car = [Int64](repeating: 0, count: 4)
    var net = [Int64](repeating: 0, count: 4), vat = [Int64](repeating: 0, count: 4), grs = [Int64](repeating: 0, count: 4)
    var cvat = [[Int64]](repeating: [Int64](repeating: 0, count: 4), count: 4)
    var l1Date = ""

    init(_ s: Session) { self.s = s }

    func cr(_ pic: String, _ v: Int64, int: Int) -> String {
        Pic.edit(pic, value: (v < 0 ? -1 : 1) * (abs(v) % Cobol.pow10(int + 2)), scale: 2)
    }
    func add(_ a: inout Int64, _ v: Int64) { a = Cobol.truncate(a + v, digits: 10) }

    func main() throws {
        let p = PLA.Printer(s)
        c.display(" ", at: 101, eraseEOS: true)
        l1Date = PLA.toDayDisplay(s)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA050.progName, at: 101)
        c.display(s.t("pl050.title"), at: 132, color: 2)
        c.display(l1Date, at: 171, color: 2)
        let purchase = PLA.purchaseFile(s), invoice = PLA.invoiceFile(s)
        _ = purchase.open(); _ = invoice.open()
        p.openOutput()
        j = 0
        let pageLines = Int(s.sys.int("page-lines"))

        func main12() {
            j += 1
            let line1 = Cobol.x(PLA050.progName, 49) + Cobol.x(s.t("pl050.rep_title"), 75) + s.t("pl050.rep_page") + Pic.edit("zz9", value: Int64(j % 1000), scale: 0)
            let line2 = Cobol.x(s.sys.str("usera"), 49) + Cobol.x("", 73) + Cobol.x(l1Date, 10)
            if j != 1 {
                p.writePage(line1)
                p.write(line2, after: 1)
                p.write("", after: 1)
            } else {
                p.writeBefore(line1, before: 1)
                p.writeBefore(line2, before: 1)
            }
        }
        func headings() {
            main12()
            p.write(Cobol.x(s.t("pl050.rep_line4a"), 66) + "    " + Cobol.x(s.t("pl050.rep_line4b"), 62), after: 1)
            p.write("", after: 1)
            lineCnt = 5
        }
        headings()

        var invArea = [UInt8](repeating: 0, count: 129)
        var purch = PLA.fdArea(PLA.purchLayout)
        while let rec = invoice.readNext() {
            invArea = rec.bytes
            var ih = Record(PLA.invHeaderLayout, bytes: Array(invArea[0..<100]) + [UInt8](repeating: 0x20, count: 29))
            if ih.int("ih-test") != 0 { continue }
            if ih.str("ih-status").uppercased() == "Z" { continue }
            purch.set("purch-key", ih.str("ih-supplier"))
            var l5Name: String
            if let pr = purchase.read(key: ih.str("ih-supplier")) {
                purch = pr
                l5Name = Cobol.x(purch.str("purch-name"), 25)
            } else {
                l5Name = Cobol.x(s.l10n.raw("pl050.supplier_unknown"), 25)
                wsError = 1
            }
            let l5Date = Cobol.x(PLA.dateDisplay(s, ih.int("ih-date")), 11)
            var wsDeduct = ih.int("ih-deduct-amt")
            let type = ih.int("ih-type")
            if type == 3 {
                for f in ["ih-net", "ih-carriage", "ih-vat", "ih-c-vat"] { ih.setInt(f, -ih.int(f)) }
            }
            if type == 2 { wsDeduct = -wsDeduct }
            // line-b / line-d
            var lbA = Cobol.x("", 12), lbAmount = cr("z(6)9.99cr", 0, int: 7)
            if wsDeduct != 0 {
                lbA = Cobol.x(s.l10n.raw("pl050.prompt_pay"), 12)
                lbAmount = cr("z(6)9.99cr", wsDeduct, int: 7)
            }
            var ldA = Cobol.x("", 12), ldAmount = cr("z(6)9.99cr", 0, int: 7), ldVat = "0"
            if ih.int("ih-carriage") != 0 {
                ldA = Cobol.x(s.l10n.raw("pl050.carriage"), 12)
                ldAmount = cr("z(6)9.99cr", ih.int("ih-carriage"), int: 7)
                ldVat = ih.int("ih-c-vat") == 0 ? "0" : "1"
            }
            // a は pic 9。種別 0 や 4 以上は添字範囲外になるため集計しない
            let a = Int(type)
            let l5Type = Cobol.x(s.l10n.raw(type == 1 ? "pl050.type_receipt" : (type == 2 ? "pl050.type_invoice" : "pl050.type_cr_note")), 14)
            let inet = ih.int("ih-net"), ivat = ih.int("ih-vat"), icar = ih.int("ih-carriage"), icvat = ih.int("ih-c-vat")
            if (1...3).contains(a) {
                add(&cvat[a][1], icvat)
                add(&gds[a], inet)
                add(&ded[a], wsDeduct)
                add(&car[a], icar)
                add(&vat[a], ivat + icvat)
                add(&net[a], inet + icar)
                add(&grs[a], ivat + icvat + inet + icar)
            }
            let line5 = Pic.edit("z(7)9", value: ih.int("ih-invoice"), scale: 0) + " " + l5Date + Cobol.x(ih.str("ih-supplier"), 9) + l5Name
                + "    " + l5Type + cr("z(6)9.99cr", inet, int: 7) + Cobol.x("", 12)
                + cr("z(6)9.99cr", inet + icar, int: 7) + cr("z(6)9.99cr", ivat + icvat, int: 7) + cr("z(6)9.99cr", ivat + icvat + inet + icar, int: 7)
            if lineCnt > pageLines { headings() }
            p.write(line5, after: 2)
            lineCnt += 2
            printOut = "Y"
            var firstTime = true
            // analysis-print
            let n = Int(ih.int("ih-lines"))
            if n > 0 {
                for _ in 0..<n {
                    if let lr = invoice.readNext() { invArea = lr.bytes }
                    var il = Record(PLA.wsLineLayout, bytes: Array(invArea[0..<75]) + [UInt8](repeating: 0x20, count: 54))
                    if il.str("il-product").hasPrefix("/") { continue }
                    if type == 3 {
                        il.setInt("il-vat", -il.int("il-vat"))
                        il.setInt("il-net", -il.int("il-net"))
                    }
                    let k = Int(il.int("il-vat-code"))
                    if k > 0 && (1...3).contains(a) && k <= 3 { add(&cvat[a][k], il.int("il-vat")) }
                    let lineA = Cobol.x("", 46) + (firstTime ? Cobol.x(s.l10n.raw("pl050.la_analysis"), 12) : Cobol.x("", 12))
                        + Cobol.x(il.str("il-pa"), 6) + (firstTime ? Cobol.x(s.l10n.raw("pl050.la_value"), 8) : Cobol.x("", 8))
                        + cr("z(6)9.99cr", il.int("il-net"), int: 7) + "  "
                        + (firstTime ? Cobol.x(s.l10n.raw("pl050.la_vat_code"), 9) : Cobol.x("", 9)) + String(k % 10)
                    firstTime = false
                    p.write(lineA, after: 1)
                    lineCnt += 1
                    if lineCnt > pageLines { headings() }
                }
            }
            // extra-analysis
            if lineCnt > pageLines - 2 { headings() }
            if lbA != Cobol.x("", 12) {
                p.write(Cobol.x("", 46) + lbA + Cobol.x("", 6) + Cobol.x("", 8) + lbAmount, after: 1)
                lineCnt += 1
            }
            if ldA != Cobol.x("", 12) {
                p.write(Cobol.x("", 46) + ldA + Cobol.x("", 6) + Cobol.x("", 8) + ldAmount + "  " + Cobol.x("", 9) + ldVat, after: 1)
                lineCnt += 1
            }
        }
        // main-end
        purchase.close(); invoice.close()
        main12()
        p.write(Cobol.x("", 36) + s.t("pl050.rep_line7"), after: 2)
        p.write("", after: 1)
        for a in 1...3 {
            let lit = s.l10n.raw(a == 1 ? "pl050.lit_receipts" : (a == 2 ? "pl050.lit_invoices" : "pl050.lit_credit_notes"))
            let line6 = "   " + Cobol.x(s.t("pl050.rep_total"), 10) + Cobol.x(Cobol.x(lit, 17), 18)
                + cr("z(6)9.99cr", gds[a], int: 7) + cr("z(6)9.99cr", car[a], int: 7) + cr("z(6)9.99cr", net[a], int: 7)
                + cr("z(6)9.99cr", vat[a], int: 7) + cr("z(6)9.99cr", grs[a], int: 7) + cr("z(6)9.99cr", ded[a], int: 7)
            lineCnt += 1
            p.write(line6, after: 1)
        }
        if wsError == 1 {
            p.write(s.t("pl050.rep_warning"), after: 2)
            printOut = "Y"
        }
        p.write(s.t("pl050.rep_line9"), after: 5)
        p.write("", after: 1)
        for i in 1...3 {
            let line8 = Cobol.x(s.t("pl050.rep_vat_code"), 9) + String(i) + "   "
                + Pic.edit("z9.99", value: s.sys.int("vat-rate-\(i)"), scale: 2) + Cobol.x("%", 5)
                + cr("z(7)9.99cr", cvat[1][i], int: 8) + cr("z(9)9.99cr", cvat[2][i], int: 8) + cr("z(9)9.99cr", cvat[3][i], int: 8)
            p.write(line8, after: 1)
            lineCnt += 1
        }
        p.close()
        if printOut == "Y" { p.spool() }
    }
}
