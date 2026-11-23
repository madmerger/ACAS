import Foundation

/// sales/sl170.cbl: Sales Ledger Dump (得意先台帳ダンプ)
enum SLB170 {
    static let progName = "SL170 (3.01.07)"

    static func run(_ s: Session) throws {
        let wsDate = SLB.wsDate(s)
        let l3Date = wsDate
        let salesFile = SLB.salesFile(s)

        // report-selection
        salesFile.open()
        let sel = SLB.CustSelection(withDate: false)
        var customerIn = Cobol.x("", 7)
        sel.display(s, progName: progName, wsDate: wsDate)
        while true {
            try sel.accept(s)
            sel.custIn = sel.custIn.uppercased()
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
            break
        }

        // report-heading-setup
        let all = sel.statusIn == " " && sel.creditOp == " " && sel.invoiceOp == " " && sel.averageOp == " "
            && sel.overdueOp == " " && customerIn == Cobol.x("", 7)
        var (l3, y) = sel.heading(s, size: 70, all: all)
        if customerIn != Cobol.x("", 7) {
            SLB.stringInto(&l3, &y, s.t("report.sl170.keys_matching"))
            SLB.stringInto(&l3, &y, sel.custIn)
        }
        let l3Report = String(l3)

        // produce-report
        let prt = SLB.Printer(s)
        prt.openOutput()
        var a = 0, z = 0
        var recCnt: Int8 = 0
        func headings1() {
            a = (a + 1) % 1000
            let line1 = Cobol.x(progName, 57) + Cobol.x(s.t("report.sl170.title"), 67) + Cobol.x(s.t("report.sl170.page"), 5) + SLB.zz(Int64(a), 3)
            if a != 1 {
                prt.afterPage(line1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
            }
            prt.after(Cobol.x(s.sys.str("usera"), 40) + Cobol.x(s.t("report.sl170.report_on"), 12) + l3Report + l3Date, 2)
        }
        headings1()
        if customerIn != Cobol.x("", 7) {
            if salesFile.read(key: Array(Cobol.x(sel.custIn, 7).utf8)) == nil { a = 1 }
            customerIn = customerIn.replacingOccurrences(of: " ", with: "Z")
        }
        let custZ = Array(customerIn.utf8)

        // line-4: name-1 x(14) value-1 x(56) name-2 x(16) value-2 x(14) name-3 x(18) value-3 x(13)
        var line4 = [Character](repeating: " ", count: 131)
        func put(_ off: Int, _ n: Int, _ text: String) { line4.replaceSubrange(off..<off + n, with: Array(Cobol.x(text, n))) }
        func name1(_ k: String) { put(0, 14, s.t(k)) }
        func value1(_ v: String) { put(14, 56, v) }
        func name2(_ k: String) { put(70, 16, s.t(k)) }
        func value2(_ v: Int64) { put(86, 14, SLB.z99(v, 8) + "   ") }   // v は小数 2 桁
        func date(_ bin: Int64) {
            put(86, 3, "")
            put(89, 11, bin == 0 ? "" : SLB.convBin(s, bin).wsDate)
        }
        func name3(_ k: String) { put(100, 18, s.t(k)) }
        func value3(_ v: Int64) { put(118, 13, SLB.z99cr(v, 8)) }
        func write(_ n: Int) { prt.after(String(line4), n) }

        while let sales = salesFile.readNext() {
            let live = sales.int("sales-status") == 1, dead = sales.int("sales-status") == 0
            if sel.statusIn == "L" && dead { continue }
            if sel.statusIn == "D" && live { continue }
            let key = sales.raw("sales-key")
            if customerIn != Cobol.x("", 7) && custZ.lexicographicallyPrecedes(key) { break }
            if customerIn != Cobol.x("", 7) {
                var truth = true
                for i in 0..<6 where truth && custZ[i] != 0x20 && custZ[i] != key[i] { truth = false }
                if !truth { continue }
            }
            if sel.creditOp != " " && !SLB.CustSelection.testNum(sel.creditOp, sel.creditIn, sales.int("sales-credit")) { continue }
            if sel.invoiceOp != " " && !SLB.CustSelection.testNum(sel.invoiceOp, sel.invoiceIn, sales.int("sales-activety")) { continue }
            if sel.averageOp != " " && !SLB.CustSelection.testNum(sel.averageOp, sel.averageIn, sales.int("sales-average")) { continue }
            if sel.overdueOp != " " && sales.int("sales-current") > 0
                && !SLB.CustSelection.testNum(sel.overdueOp, sel.overdueIn, s.sys.int("run-date") - sales.int("sales-last-inv")) { continue }

            // listing
            name1("report.sl170.key"); value1(sales.str("sales-key"))
            name2("report.sl170.credit"); value2(sales.int("sales-credit") * 100)
            name3("report.sl170.current")
            value3(Cobol.truncate(sales.int("sales-current") - sales.int("sales-unapplied"), digits: 10))
            write(2)
            name1("report.sl170.name"); value1(sales.str("sales-name"))
            name2("report.sl170.discount"); value2(sales.int("sales-discount"))
            name3("report.sl170.last"); value3(sales.int("sales-last"))
            write(1)
            name1("report.sl170.addr1"); value1(sales.str("sales-addr1"))
            name2("report.sl170.late_min"); value2(abs(sales.int("sales-late-min")) * 100)
            name3("report.sl170.q1"); value3(sales.int("turnover-q1"))
            write(1)
            name1("report.sl170.addr2"); value1(sales.str("sales-addr2"))
            name2("report.sl170.late_max"); value2(abs(sales.int("sales-late-max")) * 100)
            name3("report.sl170.q2"); value3(sales.int("turnover-q2"))
            write(1)
            name1("report.sl170.phone"); value1(sales.str("sales-phone"))
            name2("report.sl170.limit"); value2(abs(sales.int("sales-limit")) * 100)
            name3("report.sl170.q3"); value3(sales.int("turnover-q3"))
            write(1)
            name1("report.sl170.delivery_tag"); value1(String(sales.int("delivery-tag")))
            name2("report.sl170.activety"); value2(abs(sales.int("sales-activety")) * 100)
            name3("report.sl170.q4"); value3(sales.int("turnover-q4"))
            write(1)
            name1("report.sl170.notes_tag"); value1(String(sales.int("notes-tag")))
            put(86, 14, ""); put(70, 16, "")
            write(1)
            name1("report.sl170.status"); value1(s.t(sales.int("sales-status") == 1 ? "report.sl170.live" : "report.sl170.dead"))
            name2("report.sl170.last_inv"); date(sales.int("sales-last-inv"))
            put(100, 18, ""); put(118, 13, "")
            write(1)
            name1("report.sl170.late"); value1(s.t(sales.int("sales-late") == 1 ? "report.sl170.yes" : "report.sl170.no"))
            name2("report.sl170.last_pay")
            put(89, 11, sales.int("sales-last-pay") == 0 ? "" : SLB.convBin(s, sales.int("sales-last-pay")).wsDate)
            write(1)
            name1("report.sl170.dunning"); value1(s.t(sales.int("sales-dunning") == 1 ? "report.sl170.yes" : "report.sl170.no"))
            name2("report.sl170.average"); value2(abs(sales.int("sales-average")) * 100)
            write(1)
            let email = sales.str("sales-email")
            if email != Cobol.x("", 30) {
                line4 = [Character](repeating: " ", count: 131)
                var p = 1
                SLB.stringInto(&line4, &p, Cobol.x(s.t("report.sl170.email"), 14))
                SLB.stringInto(&line4, &p, String(email.prefix { $0 != " " }))
                let inv = sales.int("email-invoice") == 1, stm = sales.int("email-statement") == 1, dun = sales.int("email-letters") == 1
                if inv || stm || dun {
                    SLB.stringInto(&line4, &p, s.t("report.sl170.used_by"))
                    if inv { SLB.stringInto(&line4, &p, s.t("report.sl170.invoicing")) }
                    if stm {
                        if inv { p -= 2; SLB.stringInto(&line4, &p, s.t("report.sl170.c_statements")) }
                        else { SLB.stringInto(&line4, &p, s.t("report.sl170.statements")) }
                    }
                    if dun {
                        if inv || stm { p -= 2; SLB.stringInto(&line4, &p, s.t("report.sl170.c_dunning")) }
                        else { SLB.stringInto(&line4, &p, s.t("report.sl170.dunning_dot")) }
                    }
                }
                write(1)
            }
            z = (z + 1) % 10
            recCnt = recCnt &+ 1
            if z > 3 {
                headings1()
                z = 0
            } else {
                prt.after(Cobol.x("", 40) + "<" + String(repeating: "-", count: 50) + ">", 1)
            }
        }
        salesFile.close()
        prt.close()
        if recCnt != 0 { prt.spool() }
    }
}
