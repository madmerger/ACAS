import Foundation

/// purchase/pl050.cbl: 仕入取引検証帳票 (Invoice Proof Report)
final class PurchaseProof {
    static let progName = "PL050 (3.01.04)"

    let ledger: PurchaseLedger
    let system: Record
    var j = 0
    var lineCnt = 0
    var wsError = 0
    /// total-group (1..3): ded, gds, car, net, vat, grs, cvat(1..3)
    var ded = [Int64](repeating: 0, count: 4), gds = [Int64](repeating: 0, count: 4), car = [Int64](repeating: 0, count: 4)
    var net = [Int64](repeating: 0, count: 4), vat = [Int64](repeating: 0, count: 4), grs = [Int64](repeating: 0, count: 4)
    var cvat = [[Int64]](repeating: [Int64](repeating: 0, count: 4), count: 4)
    var l1Date = ""

    init(_ ledger: PurchaseLedger) {
        self.ledger = ledger
        self.system = ledger.system
    }

    func cr(_ pic: String, _ v: Int64, int: Int) -> String {
        Pic.edit(pic, value: (v < 0 ? -1 : 1) * (abs(v) % Cobol.pow10(int + 2)), scale: 2)
    }
    func add(_ a: inout Int64, _ v: Int64) { a = Cobol.truncate(a + v, digits: 10) }

    func generate() {
        let p = PurchasePrinter(ledger)
        l1Date = ledger.reportDate(system.int("run-date"))
        j = 0
        let pageLines = max(8, Int(system.int("page-lines")))

        func main12() {
            j += 1
            let line1 = Cobol.x(Self.progName, 49) + Cobol.x("Unapplied Purchase Transaction Report", 75) + "Page " + Pic.edit("zz9", value: Int64(j % 1000), scale: 0)
            let line2 = Cobol.x(system.str("usera"), 49) + Cobol.x("", 73) + Cobol.x(l1Date, 10)
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
            p.write(Cobol.x(" Number  ---Date--- <------------Supplier------------>    --Type--", 66) + "    " + Cobol.x("     Goods                 <---Net-->  <---Vat-->  <--Gross->", 62), after: 1)
            p.write("", after: 1)
            lineCnt = 5
        }
        headings()

        var invArea = [UInt8](repeating: 0, count: 129)
        var records = ledger.store.all(ledger.invoicePath).makeIterator()
        while let rec = records.next() {
            invArea = rec.data
            var ih = Record(PurchaseRecords.invHeaderLayout, bytes: invArea)
            if ih.int("ih-test") != 0 { continue }
            if ih.str("ih-status").uppercased() == "Z" { continue }
            var l5Name: String
            if let supplier = ledger.supplierRecord(ih.str("ih-supplier")) {
                l5Name = Cobol.x(supplier.str("purch-name"), 25)
            } else {
                l5Name = Cobol.x("Supplier Unknown", 25)
                wsError = 1
            }
            let l5Date = Cobol.x(ledger.reportDate(ih.int("ih-date")), 11)
            var wsDeduct = ih.int("ih-deduct-amt")
            let type = ih.int("ih-type")
            if type == 3 {
                for f in ["ih-net", "ih-carriage", "ih-vat", "ih-c-vat"] { ih.setInt(f, -ih.int(f)) }
            }
            if type == 2 { wsDeduct = -wsDeduct }
            // line-b / line-d
            var lbA = Cobol.x("", 12), lbAmount = cr("z(6)9.99cr", 0, int: 7)
            if wsDeduct != 0 {
                lbA = Cobol.x("Prompt Pay  ", 12)
                lbAmount = cr("z(6)9.99cr", wsDeduct, int: 7)
            }
            var ldA = Cobol.x("", 12), ldAmount = cr("z(6)9.99cr", 0, int: 7), ldVat = "0"
            if ih.int("ih-carriage") != 0 {
                ldA = Cobol.x("Carriage    ", 12)
                ldAmount = cr("z(6)9.99cr", ih.int("ih-carriage"), int: 7)
                ldVat = ih.int("ih-c-vat") == 0 ? "0" : "1"
            }
            // a は pic 9。種別 0 や 4 以上は添字範囲外になるため集計しない
            let a = Int(type)
            let l5Type = Cobol.x(type == 1 ? "Receipt" : (type == 2 ? "Invoice" : "Cr. Note"), 14)
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
            var firstTime = true
            // analysis-print
            let n = Int(ih.int("ih-lines"))
            if n > 0 {
                for _ in 0..<n {
                    if let lr = records.next() { invArea = lr.data }
                    var il = Record(PurchaseRecords.invLineLayout, bytes: invArea)
                    if il.str("il-product").hasPrefix("/") { continue }
                    if type == 3 {
                        il.setInt("il-vat", -il.int("il-vat"))
                        il.setInt("il-net", -il.int("il-net"))
                    }
                    let k = Int(il.int("il-vat-code"))
                    if k > 0 && (1...3).contains(a) && k <= 3 { add(&cvat[a][k], il.int("il-vat")) }
                    let lineA = Cobol.x("", 46) + (firstTime ? Cobol.x("Analysis", 12) : Cobol.x("", 12))
                        + Cobol.x(il.str("il-pa"), 6) + (firstTime ? Cobol.x("Value", 8) : Cobol.x("", 8))
                        + cr("z(6)9.99cr", il.int("il-net"), int: 7) + "  "
                        + (firstTime ? Cobol.x("Vat Code", 9) : Cobol.x("", 9)) + String(k % 10)
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
        main12()
        p.write(Cobol.x("", 36) + "Goods    Carriage         Net         Vat       Gross  Prompt Pay", after: 2)
        p.write("", after: 1)
        for a in 1...3 {
            let lit = (a == 1 ? "Receipts" : (a == 2 ? "Invoices" : "Credit Notes"))
            let line6 = "   " + Cobol.x("    Total", 10) + Cobol.x(Cobol.x(lit, 17), 18)
                + cr("z(6)9.99cr", gds[a], int: 7) + cr("z(6)9.99cr", car[a], int: 7) + cr("z(6)9.99cr", net[a], int: 7)
                + cr("z(6)9.99cr", vat[a], int: 7) + cr("z(6)9.99cr", grs[a], int: 7) + cr("z(6)9.99cr", ded[a], int: 7)
            lineCnt += 1
            p.write(line6, after: 1)
        }
        if wsError == 1 {
            p.write("Warning: Record/s missing in Purchase File", after: 2)
        }
        p.write("V.A.T. Reconciliation       Receipts       Invoices   Credit Notes", after: 5)
        p.write("", after: 1)
        for i in 1...3 {
            let line8 = Cobol.x("Vat Code", 9) + String(i) + "   "
                + Pic.edit("z9.99", value: system.int("vat-rate-\(i)"), scale: 2) + Cobol.x("%", 5)
                + cr("z(7)9.99cr", cvat[1][i], int: 8) + cr("z(9)9.99cr", cvat[2][i], int: 8) + cr("z(9)9.99cr", cvat[3][i], int: 8)
            p.write(line8, after: 1)
            lineCnt += 1
        }
        p.close()
    }
}

final class PurchasePrinter {
    private let ledger: PurchaseLedger
    private var bytes: [UInt8] = []

    init(_ ledger: PurchaseLedger) { self.ledger = ledger }

    func write(_ line: String, after: Int) {
        bytes += [UInt8](repeating: 10, count: after) + SJIS.encode(line, size: 132)
    }

    func writeBefore(_ line: String, before: Int) {
        bytes += SJIS.encode(line, size: 132) + [UInt8](repeating: 10, count: before)
    }

    func writePage(_ line: String) {
        bytes += [12] + SJIS.encode(line, size: 132)
    }

    func close() { ledger.store.writeRaw(PurchaseLedger.reportPath, bytes + [10]) }
}

extension PurchaseLedger {
    public static let reportPath = "ledgers/acas/prt-1"

    func reportDate(_ day: Int64) -> String {
        Maps04.format(Maps04.toDate(Int(day)), dateForm: Int(system.int("date-form")))
    }

    @discardableResult
    public func purchaseProof() -> [Transaction] {
        PurchaseProof(self).generate()
        return transactions().filter { !$0.posted }
    }
}
