import Foundation

/// sales/sl160.cbl: Customer Alphabetical Listing (得意先名称順一覧)
enum SLB160 {
    static let progName = "SL160 (3.01.16)"

    static func run(_ s: Session) throws {
        let c = s.console
        let wsDate = SLB.wsDate(s)
        let l1Date = wsDate
        let salesFile = SLB.salesFile(s)
        let delivery = SLB.deliveryFile(s)
        salesFile.open(); delivery.open()

        // report-selection
        let sel = SLB.CustSelection(withDate: true)
        var customerIn = Cobol.x("", 7)
        var wsEnterDate: Int64 = 0
        sel.display(s, progName: progName, wsDate: wsDate)
        while true {
            try sel.accept(s)
            sel.custIn = sel.custIn.uppercased()
            customerIn = Cobol.x(sel.custIn, 7)
            if customerIn != Cobol.x("", 7) { customerIn = customerIn.replacingOccurrences(of: " ", with: "Z") }
            sel.statusIn = sel.statusIn.uppercased()
            if sel.statusIn != "L" && sel.statusIn != "D" && sel.statusIn != " " { continue }
            sel.creditOp = sel.creditOp.uppercased()
            if !SLB.CustSelection.validOp(sel.creditOp) { continue }
            sel.invoiceOp = sel.invoiceOp.uppercased()
            if !SLB.CustSelection.validOp(sel.invoiceOp) { continue }
            sel.averageOp = sel.averageOp.uppercased()
            if !SLB.CustSelection.validOp(sel.averageOp) { continue }
            sel.overdueOp = sel.overdueOp.uppercased()
            if !SLB.CustSelection.validOp(sel.overdueOp) { continue }
            sel.enterDateOp = sel.enterDateOp.uppercased()
            if !SLB.CustSelection.validOp(sel.enterDateOp) { continue }
            if sel.enterDateIn == Cobol.x("", 10) { break }
            let bin = SLB.validateDate(s, sel.enterDateIn).bin
            if bin == 0 {
                c.display(s.t("sl160.sl005"), at: 2361, color: 2)
                continue
            }
            c.display(" ", at: 2368, eraseEOL: true)
            wsEnterDate = bin
            break
        }

        // report-heading-setup
        let all = sel.statusIn == " " && sel.creditOp == " " && sel.invoiceOp == " " && sel.averageOp == " "
            && sel.overdueOp == " " && customerIn == Cobol.x("", 7)
        var (l3, y) = sel.heading(s, size: 70, all: all)
        if sel.enterDateOp != " " {
            let op = sel.enterDateOp == "L" ? "< " : (sel.enterDateOp == "G" ? "> " : "= ")
            SLB.stringInto(&l3, &y, op + Cobol.x(sel.enterDateIn, 8) + Cobol.x(s.t("report.sl160.entry_date"), 11))
        }
        y += 1
        if sel.custIn != Cobol.x("", 6) {
            SLB.stringInto(&l3, &y, s.t("report.sl160.keys_matching"))
            SLB.stringInto(&l3, &y, sel.custIn)
        }
        let l3Report = String(l3)

        // report-produce
        let sortData = s.store.readRaw(s.ledgers + "custsort.tmp") ?? []
        let prt = SLB.Printer(s)
        prt.openOutput()
        var a = 0, lineCnt = 0
        let pageLines = Int(s.sys.int("page-lines"))
        let delim = Cobol.x(s.sys.str("sl-delim"), 1)
        func headings() {
            a = (a + 1) % 100
            let line1 = Cobol.x(progName, 51) + Cobol.x(s.t("report.sl160.title"), 73) + Cobol.x(s.t("report.sl160.page"), 5) + SLB.zz(Int64(a), 3)
            let line3 = Cobol.x(s.sys.str("usera"), 40) + Cobol.x(s.t("report.sl160.report_on"), 12) + l3Report + l1Date
            if a != 1 {
                prt.afterPage(line1)
                prt.after(line3, 1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
                prt.before(line3, 1)
            }
            prt.after(Cobol.x(s.t("report.sl160.head4"), 127) + Cobol.x(s.t("report.sl160.head4_disc"), 5), 2)
            prt.after(" " + Cobol.x(s.t("report.sl160.head5_a"), 103) + Cobol.x(s.t("report.sl160.head5_b"), 28), 1)
            prt.after("", 1)
            lineCnt = 6
        }
        headings()

        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
        var l6Phone = [Character](repeating: " ", count: 18)
        var l6Fax = Cobol.x("", 13)
        func bwz(_ t: String, _ v: Int64) -> String { v == 0 ? String(repeating: " ", count: t.count) : t }
        func line6(_ key: String, _ status: String, _ name: String, _ charges: String, _ letter: String,
                   _ limit: Int64, _ credit: Int64, _ discount: Int64) -> String {
            Cobol.x(key, 10) + Cobol.x(status, 10) + Cobol.x(name, 50) + String(l6Phone) + l6Fax + "    "
                + Cobol.x(charges, 5) + Cobol.x(letter, 3) + bwz(SLB.zz(limit, 7), limit)
                + bwz(SLB.zz(credit, 4) + "   ", credit) + bwz(SLB.z99(discount, 2), discount)
        }
        func line7(_ addr: String) -> String { Cobol.x("", 20) + Cobol.x(addr, 112) }

        let cust6 = Array(Cobol.x(sel.custIn, 7).utf8)
        let custZ = Array(customerIn.utf8)
        var pos = 0
        while pos + 7 <= sortData.count {
            let key = Array(sortData[pos..<pos + 7])
            pos += 7
            sales.setRaw("sales-key", key)
            if customerIn != Cobol.x("", 7) && key.lexicographicallyPrecedes(custZ) { continue }
            if customerIn != Cobol.x("", 7) && cust6.lexicographicallyPrecedes(key) { continue }
            guard let r = salesFile.read(key: key) else {
                c.display(s.t("sl160.sl170"), at: 2301, color: 4)
                c.display(sales.str("sales-key"), at: 2320, color: 4)
                continue
            }
            sales = r
            c.display(" ", at: 2301, eraseEOL: true)
            let live = sales.int("sales-status") == 1, dead = sales.int("sales-status") == 0
            if sel.statusIn == "L" && dead { continue }
            if sel.statusIn == "D" && live { continue }
            if sel.creditOp != " " && !SLB.CustSelection.testNum(sel.creditOp, sel.creditIn, sales.int("sales-credit")) { continue }
            if sel.invoiceOp != " " && !SLB.CustSelection.testNum(sel.invoiceOp, sel.invoiceIn, sales.int("sales-activety")) { continue }
            if sel.averageOp != " " && !SLB.CustSelection.testNum(sel.averageOp, sel.averageIn, sales.int("sales-average")) { continue }
            if sel.overdueOp != " " && sales.int("sales-current") > 0
                && !SLB.CustSelection.testNum(sel.overdueOp, sel.overdueIn, s.sys.int("run-date") - sales.int("sales-last-inv")) { continue }
            if sel.enterDateOp != " " && !SLB.CustSelection.testNum(sel.enterDateOp, wsEnterDate, sales.int("sales-create-date")) { continue }

            // listing
            if lineCnt > pageLines { headings() }
            let address = (sales.str("sales-addr1") + sales.str("sales-addr2")).replacingOccurrences(of: delim, with: ",")
            if sales.str("sales-ext") == Cobol.x("", 4) {
                l6Phone = Array(Cobol.x(sales.str("sales-phone"), 18))
            } else {
                var py = 1
                var phone = sales.str("sales-phone")
                if let r = phone.range(of: "  ") { phone = String(phone[..<r.lowerBound]) }
                SLB.stringInto(&l6Phone, &py, phone)
                py += 1
                SLB.stringInto(&l6Phone, &py, "x")
                SLB.stringInto(&l6Phone, &py, sales.str("sales-ext"))
            }
            l6Fax = Cobol.x(sales.str("sales-fax"), 13)
            if lineCnt > pageLines - 3 { headings() }
            prt.after(line6(sales.str("sales-key"), s.t(live ? "report.sl160.active" : "report.sl160.dormant"), sales.str("sales-name"),
                            sales.int("sales-late") == 1 ? "Y" : " ", sales.int("sales-dunning") == 1 ? "Y" : " ",
                            sales.int("sales-limit"), sales.int("sales-credit"), sales.int("sales-discount")), 1)
            prt.after(line7(address), 1)
            if sales.int("delivery-tag") > 0 {
                // delivery-print
                deliv["deliv-key"] = "D" + sales.str("sales-key")
                if let d = delivery.read(key: deliv.raw("deliv-key")) { deliv = d }
                else { deliv["deliv-name"] = s.t("report.sl160.not_found"); deliv["deliv-address"] = s.t("report.sl160.not_found") }
                l6Phone = [Character](repeating: " ", count: 18)
                prt.after(line6(s.t("report.sl160.deliver_a"), s.t("report.sl160.deliver_b"), deliv.str("deliv-name"), " ", " ", 0, 0, 0), 1)
                prt.after(line7(deliv.str("deliv-address").replacingOccurrences(of: delim, with: ",")), 1)
                lineCnt = (lineCnt + 2) % 100
            }
            if sales.int("notes-tag") > 0 {
                // notes-print
                deliv["deliv-key"] = "N" + sales.str("sales-key")
                if let d = delivery.read(key: deliv.raw("deliv-key")) { deliv = d }
                else { deliv["deliv-name"] = s.t("report.sl160.not_found"); deliv["deliv-address"] = s.t("report.sl160.not_found") }
                prt.after(line7(s.t("report.sl160.notes") + deliv.str("deliv-address")), 1)
                lineCnt = (lineCnt + 1) % 100
            }
            prt.after("", 1)
            lineCnt = (lineCnt + 3) % 100
            if lineCnt > pageLines { headings() }
        }
        salesFile.close(); delivery.close()
        prt.spool()
        s.store.writeRaw(s.ledgers + "custsort.tmp", [])
    }
}
