import Foundation

/// sales/sl140.cbl: Day Book (売上日記帳)
enum SLB140 {
    static let progName = "SL140 (3.01.09)"

    static func run(_ s: Session) throws {
        let c = s.console
        let wsDate = SLB.wsDate(s)
        let l1Date = wsDate
        // group-totals (1..4): gds car ded net vat grs dis
        var gds = [Int64](repeating: 0, count: 5), car = gds, ded = gds, net = gds, vat = gds, grs = gds, dis = gds
        func add(_ a: inout [Int64], _ z: Int, _ v: Int64) {
            a[z] = Cobol.truncate(a[z] + v, digits: 10)
            a[4] = Cobol.truncate(a[4] + v, digits: 10)
        }

        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("sl140.title"), at: 136, color: 2)
        c.display(wsDate, at: 171, color: 2)

        let inv = SLB.invoiceFile(s)
        if inv.open() != "00" { inv.close(); return }
        let salesFile = SLB.salesFile(s)
        if salesFile.open() != "00" { inv.close(); salesFile.close(); return }
        let prt = SLB.Printer(s)
        prt.openOutput()
        c.display(s.t("sl140.printing"), at: 1212, color: 2)

        var j = 0, lineCnt = 0, headType = 0
        let pageLines = Int(s.sys.int("page-lines"))
        func headings() {
            j = (j + 1) % 1000
            let line1 = Cobol.x(progName, 62) + Cobol.x(s.t("report.sl140.title"), 62) + Cobol.x(s.t("report.sl140.page"), 5) + SLB.zz(Int64(j), 3)
            let line2 = Cobol.x(s.sys.str("usera"), 62) + Cobol.x("", 60) + l1Date
            if j != 1 {
                prt.afterPage(line1)
                prt.after(line2, 1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
                prt.before(line2, 1)
            }
            lineCnt = 2
            if headType == 0 {
                lineCnt += 3
                prt.after(Cobol.x(s.t("report.sl140.head4_a"), 66) + Cobol.x("", 8) + Cobol.x(s.t("report.sl140.head4_b"), 58), 2)
                prt.after("", 1)
            }
        }
        headings()
        var sales = Record(SLB.salesLayout)
        while let rec = inv.readNext() {
            if rec.int("item-nos") != 0 { continue }
            if rec.int("invoice-type") > 3 { continue }
            let h = SLB.sih(from: rec)
            let status = h.str("sih-status")
            if h.str("sih-day-book-flag") == "B" || !(status == "z" || status == "Z") { continue }
            if lineCnt > pageLines { headings() }
            if let r = salesFile.read(key: h.raw("sih-customer")) { sales = r }
            else { sales.setRaw("sales-key", h.raw("sih-customer")) }
            let type = Int(h.int("sih-type"))
            let l5Type = Cobol.x(s.t(type == 1 ? "report.sl140.receipt" : (type == 2 ? "report.sl140.invoice" : "report.sl140.cr_note")), 11)
            let sign: Int64 = type == 3 ? -1 : 1
            let hVat = sign * h.int("sih-vat"), hCVat = sign * h.int("sih-c-vat"), hEVat = sign * h.int("sih-e-vat")
            let hNet = sign * h.int("sih-net"), hExtra = sign * h.int("sih-extra"), hCarr = sign * h.int("sih-carriage")
            let hDisc = sign * h.int("sih-discount")
            let dedAmt = Cobol.truncate(sign * Cobol.truncate(h.int("sih-deduct-amt"), digits: 6), digits: 6)
            let vats = hVat + hCVat + hEVat
            let nets = hNet + hExtra + hCarr + hDisc + dedAmt
            let line5 = SLB.zz(h.int("sih-invoice"), 8) + "  " + Cobol.x(SLB.convBin(s, h.int("sih-date")).wsDate, 10) + " "
                + Cobol.x(h.str("sih-customer"), 8) + Cobol.x(sales.str("sales-name"), 25) + "   " + l5Type + Cobol.x("", 6)
                + SLB.z99cr(nets, 7) + SLB.z99cr(vats, 7) + SLB.z99cr(vats + nets, 7)
            if type >= 1 {
                add(&gds, type, hNet)
                add(&dis, type, Cobol.truncate(hDisc + hExtra, digits: 10))
                add(&ded, type, dedAmt)
                add(&car, type, hCarr)
                add(&vat, type, Cobol.truncate(vats, digits: 10))
                add(&net, type, Cobol.truncate(nets, digits: 10))
                add(&grs, type, Cobol.truncate(vats + nets, digits: 10))
            }
            prt.after(line5, 1)
            lineCnt = (lineCnt + 1) % 100
        }
        salesFile.close(); inv.close()
        headType = 1
        headings()
        prt.after(Cobol.x("", 23) + Cobol.x(s.t("report.sl140.head7"), 83), 2)
        prt.after("", 1)
        let lits = ["report.sl140.receipts", "report.sl140.invoices", "report.sl140.credit_notes", "report.sl140.totals"]
        for z in 1...4 {
            prt.after(Cobol.x(s.t(lits[z - 1]), 17) + SLB.z99cr(gds[z], 8) + SLB.z99cr(dis[z], 8) + SLB.z99cr(ded[z], 8)
                      + SLB.z99cr(car[z], 8) + SLB.z99cr(net[z], 8) + SLB.z99cr(vat[z], 8) + SLB.z99cr(grs[z], 8), 2)
        }
        prt.spool()
    }
}
