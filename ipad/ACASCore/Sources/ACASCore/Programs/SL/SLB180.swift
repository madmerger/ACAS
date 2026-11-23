import Foundation

/// sales/sl180.cbl: Sales Ledger Turnover Report (得意先別売上高表)
enum SLB180 {
    static let progName = "SL180 (3.01.08)"

    static func run(_ s: Session) throws {
        let c = s.console
        let wsDate = SLB.wsDate(s)
        let l1Date = wsDate
        let salesFile = SLB.salesFile(s)
        salesFile.open()
        let prt = SLB.Printer(s)
        prt.openOutput()

        // report-selection
        let sel = SLB.CustSelection(withDate: true)
        var customerIn = Cobol.x("", 7)
        var wsEnterDate: Int64 = 0
        sel.display(s, progName: progName, wsDate: wsDate)
        while true {
            try sel.accept(s)
            customerIn = Cobol.x(sel.custIn, 7)
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
                c.display(s.t("sl180.sl005"), at: 2361)
                continue
            }
            c.display(" ", at: 2368, eraseEOL: true)
            wsEnterDate = bin
            break
        }

        // produce-report
        var a = 0, lineCnt = 0
        let pageLines = Int(s.sys.int("page-lines"))
        func headings() {
            a = (a + 1) % 1000
            let line1 = Cobol.x(progName, 51) + Cobol.x(s.t("report.sl180.title"), 73) + Cobol.x(s.t("report.sl180.page"), 5) + SLB.zz(Int64(a), 3)
            let line2 = Cobol.x(s.sys.str("usera"), 51) + Cobol.x("", 71) + l1Date
            if a != 1 {
                prt.afterPage(line1)
                prt.after(line2, 1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
                prt.before(line2, 1)
            }
            prt.after(Cobol.x("", 38) + Cobol.x(s.t("report.sl180.head3"), 94), 2)
            prt.after(Cobol.x(s.t("report.sl180.head4_a"), 38) + Cobol.x(s.t("report.sl180.head4_b"), 94), 1)
            prt.after("", 1)
            lineCnt = 6
        }
        func shorten(_ d: String) -> String {
            var w = Array(Cobol.x(d, 10))
            let form = s.sys.int("date-form")
            if form == 1 || form == 2 {
                w[6] = w[8]; w[7] = w[9]
            } else {
                for i in stride(from: 0, to: 8, by: 2) { w[i] = w[i + 2]; w[i + 1] = w[i + 3] }
            }
            w[8] = " "; w[9] = " "
            return String(w)
        }
        headings()
        var startFailed = false
        if customerIn != Cobol.x("", 7) {
            if !salesFile.start(notLessThan: Array(customerIn.utf8)) { a = 1; startFailed = true }
            customerIn = customerIn.replacingOccurrences(of: " ", with: "Z")
        }
        let custZ = Array(customerIn.utf8)
        while !startFailed, let sales = salesFile.readNext() {
            let live = sales.int("sales-status") == 1, dead = sales.int("sales-status") == 0
            if sel.statusIn == "L" && dead { continue }
            if sel.statusIn == "D" && live { continue }
            if customerIn != Cobol.x("", 7) && custZ.lexicographicallyPrecedes(sales.raw("sales-key")) { break }
            if sel.creditOp != " " && !SLB.CustSelection.testNum(sel.creditOp, sel.creditIn, sales.int("sales-credit")) { continue }
            if sel.invoiceOp != " " && !SLB.CustSelection.testNum(sel.invoiceOp, sel.invoiceIn, sales.int("sales-activety")) { continue }
            if sel.averageOp != " " && !SLB.CustSelection.testNum(sel.averageOp, sel.averageIn, sales.int("sales-average")) { continue }
            if sel.overdueOp != " " && sales.int("sales-current") > 0
                && !SLB.CustSelection.testNum(sel.overdueOp, sel.overdueIn, s.sys.int("run-date") - sales.int("sales-last-inv")) { continue }
            if sel.enterDateOp != " " && !SLB.CustSelection.testNum(sel.enterDateOp, wsEnterDate, sales.int("sales-create-date")) { continue }

            // listing
            let current = Cobol.truncate(sales.int("sales-current") - sales.int("sales-unapplied"), digits: 10)
            func m(_ v: Int64) -> String { SLB.minus(v / 100, 7, negative: v < 0) }
            let lastInv = sales.int("sales-last-inv") == 0 ? Cobol.x("", 10) : shorten(SLB.convBin(s, sales.int("sales-last-inv")).wsDate)
            let lastPay = sales.int("sales-last-pay") == 0 ? Cobol.x("", 8) : Cobol.x(shorten(SLB.convBin(s, sales.int("sales-last-pay")).wsDate), 8)
            let line5 = Cobol.x(sales.str("sales-key"), 8) + Cobol.x(sales.str("sales-name"), 30)
                + SLB.zz(sales.int("sales-credit"), 4) + SLB.zz(sales.int("sales-limit"), 8)
                + SLB.minus(sales.int("sales-activety"), 5) + SLB.minus(sales.int("sales-average"), 7)
                + m(sales.int("turnover-q1")) + m(sales.int("turnover-q2")) + m(sales.int("turnover-q3")) + m(sales.int("turnover-q4"))
                + m(current) + m(sales.int("sales-last")) + "  " + lastInv + lastPay
            prt.after(line5, 1)
            lineCnt = (lineCnt + 1) % 100
            if lineCnt > pageLines { headings() }
        }
        salesFile.close()
        prt.spool()
    }
}
