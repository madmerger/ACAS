import Foundation

/// sales/sl120.cbl: Aged Debtors Report (売掛金年齢表)
enum SLB120 {
    static let progName = "SL120 (3.01.07)"

    static func run(_ s: Session) throws { try Prog(s).run() }

    /// COMPUTE ... ROUNDED (四捨五入、0 から遠い方へ)
    static func divRounded(_ n: Int64, _ d: Int64) -> Int64 {
        let q = n / d, r = n % d
        if abs(r) * 2 >= abs(d) { return q + ((n < 0) != (d < 0) ? -1 : 1) }
        return q
    }

    /// 固定幅の印字行 (group 項目)。位置は 0 始まり。
    struct Line {
        var c: [Character]
        init(_ n: Int) { c = [Character](repeating: " ", count: n) }
        mutating func put(_ pos: Int, _ len: Int, _ text: String) {
            let t = Array(Cobol.x(text, len))
            for i in 0..<len { c[pos + i] = i < t.count ? t[i] : " " }
        }
        func get(_ pos: Int, _ len: Int) -> String { String(c[pos..<(pos + len)]) }
        mutating func clear() { c = [Character](repeating: " ", count: c.count) }
        var text: String { String(c) }
    }

    final class Prog {
        let s: Session
        let c: Console
        let prt: SLB.Printer
        let salesFile: IndexedFile
        var sales = Record(SLB.salesLayout)
        var oi = Record(SLB.oiLayout)
        var raw: [UInt8] = []
        var oiPos = 0

        var fsReply = 0, fsReply2 = 0
        var truth = 1
        var work1: Int64 = 0, work2: Int64 = 0
        var a: Int64 = 0, b: Int64 = 0
        var customerIn = Cobol.x("", 7)
        var payDate: Int64 = 0, payValue: Int64 = 0
        var lastRead = Cobol.x("", 7)
        var pageNos = 0, lineCnt = 66
        var invAmount: Int64 = 0, amountOut: Int64 = 0
        var enteredDate: Int64 = 0
        var wsDate = ""

        var inv0: Int64 = 0, inv30: Int64 = 0, inv60: Int64 = 0, inv90: Int64 = 0
        var totBal0: Int64 = 0, totBal30: Int64 = 0, totBal60: Int64 = 0, totBal90: Int64 = 0, totOsBal: Int64 = 0
        var totNoPay: Int64 = 0, totNoCrBal: Int64 = 0, totAcctActive: Int64 = 0, totAcctLive: Int64 = 0
        var totNoLate: Int64 = 0, totNoUnappPay: Int64 = 0
        var totAmtLate: Int64 = 0, totAmtPay: Int64 = 0, totAmtCrBal: Int64 = 0, totAmtUnappPay: Int64 = 0
        var totUnapplCredits: Int64 = 0, totSalesBal: Int64 = 0
        var bal0: Int64 = 0, bal30: Int64 = 0, bal60: Int64 = 0, bal90: Int64 = 0, balT: Int64 = 0, balPay: Int64 = 0

        // line-3
        var l3User = Cobol.x("", 56), l3List = "", l3Date = Cobol.x("", 10)
        var line4 = ""
        // line-5: account 0(9) name 9(32) telephone 41(13) | title 54: invoice 54(8) hold 62 late 63 date 64(10)
        //         | less 74 bal-0 75(12) greater 87 bal-30 88(11) bal-60 99(11) bal-90 110(10) less-1 120 payments 121(10) greater-1 131
        var line5 = Line(132)
        // line-6: lover 0(5) over 5(12) "Terms:" 17(7) credit 24(4) "Credit Limit:" 28(13) limit 41(8) sp 49(6)
        //         lbalance 55(8) balance 63(11) bal-0 74(13) bal-30 87(11) bal-60 98(11) bal-90 109(11) payments 120(11)
        var line6 = Line(131)
        // line-8 / line-10 (redefines): head 0(25) + 5 x 13
        var line8 = Line(90)
        var l11f1 = String(repeating: "-", count: 13), l11f2 = String(repeating: "-", count: 13)

        init(_ s: Session) {
            self.s = s; c = s.console
            prt = SLB.Printer(s, "prt-1", size: 132)
            salesFile = SLB.salesFile(s)
        }

        func e(_ pic: String, _ v: Int64, _ scale: Int = 2) -> String { Pic.edit(pic, value: v, scale: scale) }
        func sp(_ n: Int) -> String { String(repeating: " ", count: n) }
        var pageLines: Int { Int(s.sys.int("page-lines")) }
        static let m11 = "zzzz,zz9.99", m13 = "zzzz,zz9.99cr", n13 = "zzzz,zz9bbbbb"

        func run() throws {
            c.display(" ", at: 101, eraseEOS: true)
            if s.sys.int("s-flag-p") == 1 {
                try SLB.maps99(s, 24)
                try SLB.maps99(s, 15)
                return
            }
            if SLB.fileStatus(s, 19) != 1 {
                try SLB.maps99(s, 19)
                try SLB.maps99(s, 15)
                return
            }
            c.display(SLB120.progName, at: 202, color: 2, eraseEOS: true)
            c.display(s.t("sl120.title"), at: 231, color: 2)
            wsDate = SLB.wsDate(s)
            c.display(wsDate, at: 271, color: 2)
            l3List = Cobol.x(s.t("sl120.current_period"), 18) + sp(2)
            line4 = Cobol.x(s.t("sl120.line4"), 132)
            line6.put(17, 7, s.t("sl120.terms"))
            line6.put(28, 13, s.t("sl120.credit_limit"))
            line6.put(55, 8, s.t("sl120.balance"))

            try trailBalance()
            reportAnalysis()
            prt.close()
            prt.spool()
        }

        // MARK: trail-balance

        func trailBalance() throws {
            let stars = String(repeating: "*", count: 40)
            c.display(stars, at: 441, color: 2)
            c.display(s.t("sl120.box_date"), at: 541, color: 2)
            c.display(s.t("sl120.box_ac"), at: 641, color: 2)
            c.display(s.t("sl120.box_value"), at: 741, color: 2)
            c.display(stars, at: 841, color: 2)
            c.display(s.t("sl120.notes"), at: 1201, color: 2)
            c.display("*****", at: 1301, color: 2)
            c.display(s.t("sl120.note1"), at: 1501, color: 2)
            c.display(s.t("sl120.note2"), at: 1601, color: 2)
            c.display(s.t("sl120.note3"), at: 1701, color: 2)
            // date-input
            while true {
                c.display(wsDate, at: 551, color: 3)
                wsDate = Cobol.x(try c.accept(at: 551, size: 10, initial: wsDate, options: [.update], color: 3), 10)
                let test = wsDate
                let v = SLB.validateDate(s, test)
                wsDate = v.uDate
                if v.bin == 0 { continue }
                l3Date = test
                enteredDate = v.bin
                break
            }
            // customer-input
            customerIn = Cobol.x(try c.accept(at: 651, size: 7, color: 3), 7).uppercased()
            // value-input
            c.display("000000.00", at: 750)
            let m = Array(Cobol.x(try c.accept(at: 750, size: 9), 9))
            func dg(_ x: ArraySlice<Character>) -> Int64 { x.reduce(Int64(0)) { $0 * 10 + Int64($1.wholeNumberValue ?? 0) } }
            payValue = dg(m[0..<6]) * 100 + dg(m[7...])

            prt.openOutput()
            pageNos = 0
            headings1()
            salesFile.open()
            let path = s.ledgers + "oisort.wrk"
            if let r = s.store.readRaw(path) {
                raw = r
            } else {
                s.store.writeRaw(path, [])
                raw = []
                c.display(s.t("sl120.no_open"), at: 2450)
            }
            if customerIn != Cobol.x("", 7) {
                _ = salesFile.start(notLessThan: SJIS.encode(customerIn, size: 7))
                customerIn = customerIn.replacingOccurrences(of: " ", with: "Z")
            }

            enum L { case readPerform, readOpenItem, roi1, endStatement }
            var label = L.readPerform
            loop: while true {
                switch label {
                case .readPerform:
                    readSales()
                    if fsReply == 99 { break loop }
                    label = lastRead == sales.str("sales-key") ? .roi1 : .readOpenItem
                case .readOpenItem:
                    let salesKey = sales.str("sales-key")
                    if lastRead > salesKey { label = .readPerform; continue }
                    if fsReply2 == 99 { label = .endStatement; continue }
                    let size = SLB.oiLayout.size
                    if oiPos + size > raw.count {
                        fsReply2 = 99
                        label = .endStatement
                        continue
                    }
                    oi = Record(SLB.oiLayout, bytes: Array(raw[oiPos..<(oiPos + size)]))
                    oiPos += size
                    lastRead = oi.str("oi-customer")
                    if lastRead > salesKey { label = .endStatement; continue }
                    if lastRead != salesKey { bypassAgeing(); continue }
                    label = .roi1
                case .roi1:
                    label = .readOpenItem
                    let type = oi.int("oi-type")
                    if type == 1 || type == 4 { continue }
                    if lineCnt > pageLines { headings1() }
                    if type == 5 || type == 6 { oi.setInt("oi-invoice", 0) }
                    line5.put(54, 8, oi.int("oi-invoice") == 0 ? "" : e("z(7)9", oi.int("oi-invoice"), 0))
                    line5.put(62, 1, oi.str("oi-hold-flag"))
                    line5.put(64, 10, SLB.convBin(s, oi.int("oi-date")).wsDate)
                    invAmount = oi.int("oi-net") + oi.int("oi-extra") + oi.int("oi-carriage") + oi.int("oi-vat")
                        + oi.int("oi-discount") + oi.int("oi-e-vat") + oi.int("oi-deduct-amt") + oi.int("oi-deduct-vat")
                        + oi.int("oi-c-vat")
                    if type == 2 { amountOut = invAmount - oi.int("oi-paid") }
                    if type == 3 {
                        invAmount += oi.int("oi-paid")
                        line5.put(75, 12, e("zzzzzz9.99cr", invAmount))
                        checkZero()
                    } else if type == 5 || type == 6 {
                        balPay += oi.int("oi-paid")
                        checkZero()
                    } else {
                        work1 = (enteredDate - oi.int("oi-date")) * 100
                        b = amountOut == 0 ? 0 : 1
                        if amountOut < 0 { work1 = 100 }
                        if work1 < 3000 {
                            bal0 += amountOut
                            line5.put(75, 12, e("zzzzzz9.99cr", amountOut))
                            checkZero()
                            totBal0 += amountOut
                            inv0 += b
                        } else if work1 < 6000 {
                            bal30 += amountOut
                            line5.put(88, 11, e("zzzzzzz9.99", amountOut))
                            totBal30 += amountOut
                            inv30 += b
                        } else if work1 < 9000 {
                            bal60 += amountOut
                            line5.put(99, 11, e("zzzzzzz9.99", amountOut))
                            totBal60 += amountOut
                            inv60 += b
                        } else {
                            line5.put(110, 10, e("zzzzzz9.99", amountOut))
                            totBal90 += amountOut
                            inv90 += b
                            bal90 += amountOut
                        }
                        balT += amountOut
                    }
                    bypassAgeing()
                    // bypass-age-go
                    if type == 3 && invAmount != 0 { totUnapplCredits += invAmount }
                    line5.put(63, 1, type == 2 && amountOut == oi.int("oi-deduct-amt") && amountOut != 0 ? "L" : " ")
                    amountOut = 0
                    if line5.get(0, 9) != sp(9) {
                        prt.after("", 1)
                        lineCnt = (lineCnt + 1) % 100
                    }
                    prt.after(line5.text, 1)
                    lineCnt = (lineCnt + 1) % 100
                    line5.clear()
                case .endStatement:
                    endStatement()
                    label = .readPerform
                }
            }
            // main-end
            salesFile.close()
        }

        /// bypass-ageing 段落 (得意先が一致しない Open Item に対しても実行される)
        func bypassAgeing() {
            let type = oi.int("oi-type")
            if type == 5 || type == 6 {
                if oi.int("oi-deduct-amt") != 0 {
                    totAmtLate += oi.int("oi-deduct-amt")
                    totNoLate += 1
                }
                totAmtPay += oi.int("oi-paid")
                totNoPay += 1
            }
        }

        func endStatement() {
            line6.put(74, 13, e(Prog.m13, bal0))
            line6.put(87, 11, e(Prog.m11, bal30))
            line6.put(98, 11, e(Prog.m11, bal60))
            line6.put(109, 11, e(Prog.m11, bal90))
            line6.put(120, 11, e(Prog.m11, balPay))
            if line6.get(55, 8) != sp(8) {
                prt.after(line6.text, 1)
                prt.after("", 1)
                line6.put(55, 8, "")
                lineCnt = (lineCnt + 2) % 100
            }
            bal0 = 0; bal30 = 0; bal60 = 0; bal90 = 0; balPay = 0; balT = 0
        }

        // MARK: headings-1

        func headings1() {
            if lineCnt < pageLines { return }
            pageNos = (pageNos + 1) % 100
            l3User = Cobol.x(s.sys.str("usera"), 56)
            if lineCnt != 99 {
                let p = s.sys.int("scycle")
                l3List = String(l3List.prefix(18)) + (p == 0 ? sp(2) : e("z9", p, 0))
            }
            let line1 = Cobol.x(SLB120.progName, 56) + Cobol.x(s.t("sl120.title"), 68) + Cobol.x(s.t("sl120.page"), 5)
                + e("zz9", Int64(pageNos), 0)
            if pageNos != 1 {
                prt.afterPage(line1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
            }
            prt.after(l3User + l3List + sp(46) + l3Date, 1)
            prt.after(line4, 2)
            lineCnt = 0
        }

        // MARK: report-analysis

        func reportAnalysis() {
            func head(_ key: String) { line8.put(0, 25, s.t(key)) }
            func l8(_ i: Int, _ v: Int64) { line8.put(25 + 13 * i, 13, e(Prog.m13, v)) }
            func l10(_ i: Int, _ v: Int64) {
                if i == 4 { line8.put(77, 8, e("zzzz,zz9", v, 0)) } else { line8.put(25 + 13 * i, 13, e(Prog.n13, v, 0)) }
            }
            func line11() -> String { sp(25) + l11f1 + l11f2 }

            l3List = Cobol.x(s.t("sl120.account_stats"), 20)
            line4 = sp(132)
            lineCnt = 99
            headings1()
            prt.after(sp(29) + Cobol.x(s.t("sl120.line7"), 103), 1)
            prt.after("", 1)
            head("sl120.no_invoices")
            l10(1, inv0); l10(2, inv30); l10(3, inv60); l10(4, inv90)
            a = inv0 + inv30 + inv60 + inv90
            l10(0, a)
            prt.after(line8.text, 1)
            head("sl120.amount")
            l8(1, totBal0); l8(2, totBal30); l8(3, totBal60); l8(4, totBal90)
            totOsBal = totBal0 + totBal30 + totBal60 + totBal90
            l8(0, totOsBal); work2 = totOsBal
            prt.after(line8.text, 1)
            head("sl120.pct_os")
            l8(0, 10000)
            for (i, t) in [totBal0, totBal30, totBal60, totBal90].enumerated() {
                // compute work-1 rounded = (tot * 100) / work-2 (ゼロ除算時は work-1 不変)
                if work2 != 0 { work1 = SLB120.divRounded(t * 100 * 100, work2) }
                l8(i + 1, work1)
            }
            prt.after(line8.text, 1)
            head("sl120.avg_os")
            for i in 1...4 { l8(i, 0) }
            if inv0 != 0 { l8(1, totBal0 / inv0) }
            if inv30 != 0 { l8(2, totBal30 / inv30) }
            if inv60 != 0 { l8(3, totBal60 / inv60) }
            if inv90 != 0 { l8(4, totBal90 / inv90) }
            if a != 0 { l8(0, work2 / a) }
            prt.after(line8.text, 1)
            prt.after(sp(29) + Cobol.x(s.t("sl120.line9"), 19), 3)
            line8.clear()
            let sys4 = SLB.sys4(s)
            head("sl120.unapplied_cash")
            l8(1, totAmtUnappPay); l10(0, totNoUnappPay)
            prt.after(line8.text, 2)
            head("sl120.payments")
            l8(1, sys4.int("sl-payments")); l10(0, totNoPay)
            prt.after(line8.text, 1)
            head("sl120.credit_balances")
            l10(0, totNoCrBal); l8(1, totAmtCrBal)
            prt.after(line8.text, 1)
            head("sl120.late_charges")
            l8(1, totAmtLate); l10(0, totNoLate)
            prt.after(line8.text, 1)
            line8.clear()
            head("sl120.live_accounts")
            l10(0, totAcctLive)
            prt.after(line8.text, 1)
            head("sl120.active_accounts")
            l10(0, totAcctActive)
            prt.after(line8.text, 1)
            head("sl120.pct_active")
            if totAcctLive != 0 { work1 = (totAcctActive * 100 * 100) / totAcctLive }
            l8(0, work1)
            prt.after(line8.text, 1)

            if customerIn != Cobol.x("", 7) { return }

            var r4 = sys4
            line8.clear()
            head("sl120.recon")
            prt.after(line8.text, 3)
            line8.put(0, 25, "")
            prt.after(line8.text, 1)
            l8(0, r4.int("sl-os-bal-last-month"))
            head("sl120.bfwd")
            prt.after(line8.text, 1)
            l8(0, r4.int("sl-invoices-this-month"))
            head("sl120.plus_invoices")
            prt.after(line8.text, 1)
            totBal0 = r4.int("sl-os-bal-last-month") + r4.int("sl-invoices-this-month")
            prt.after(line11(), 1)
            line8.clear()
            l8(1, totBal0)
            prt.after(line8.text, 1)
            line8.clear()
            l8(0, r4.int("sl-credit-notes-this-month"))
            head("sl120.less_cn")
            prt.after(line8.text, 2)
            l8(0, r4.int("sl-payments"))
            head("sl120.payments_posted")
            prt.after(line8.text, 1)
            l8(0, totAmtLate)
            head("sl120.pay_late")
            prt.after(line8.text, 1)
            head("sl120.cn_late")
            l8(0, r4.int("sl-credit-deductions"))
            prt.after(line8.text, 1)
            prt.after(line11(), 1)
            totBal30 = totAmtLate + r4.int("sl-payments") + r4.int("sl-credit-notes-this-month") + r4.int("sl-credit-deductions")
            line8.clear()
            l8(1, totBal30)
            prt.after(line8.text, 1)
            l11f1 = sp(13)
            prt.after(line11(), 2)
            totBal0 -= totBal30
            head("sl120.cfwd")
            l8(1, totBal0)
            r4.setInt("sl-os-bal-this-month", totBal0)
            prt.after(line8.text, 1)
            l11f2 = String(repeating: "=", count: 13)
            prt.after(line11(), 1)
            line8.clear()
            let variance = totSalesBal - totBal0
            r4.setInt("sl-variance", variance)
            l8(0, variance)
            if variance != 0 {
                line8.put(1, 24, s.t("sl120.out_of_balance"))
                r4.setInt("sl-os-bal-this-month", r4.int("sl-os-bal-this-month") + variance)
                prt.after(line8.text, 2)
            }
            SLB.setSys4(s, r4)
        }

        // MARK: read-sales

        func readSales() {
            while true {
                guard let rec = salesFile.readNext() else { fsReply = 99; return }
                sales = rec
                let salesKey = sales.str("sales-key")
                if customerIn != Cobol.x("", 7) && salesKey > customerIn { fsReply = 99; return }
                totAcctLive += 1
                totSalesBal += sales.int("sales-current")
                let unapplied = sales.int("sales-unapplied")
                if unapplied != 0 && sales.int("sales-current") != 0 {
                    totAmtUnappPay += unapplied
                    totNoUnappPay += 1
                }
                if unapplied != 0 {
                    totSalesBal -= unapplied
                    sales.setInt("sales-current", sales.int("sales-current") - unapplied)
                }
                let current = sales.int("sales-current")
                if current < 0 {
                    totNoCrBal += 1
                    totAmtCrBal += current
                }
                readSalesTest()
                if truth == 0 { continue }
                totAcctActive += 1
                line5.put(9, 32, sales.str("sales-name"))
                line5.put(0, 9, salesKey)
                line5.put(41, 13, sales.str("sales-phone"))
                line6.put(63, 11, e(Prog.m11, current))
                line6.put(55, 8, s.t("sl120.balance"))
                line6.put(0, 5, "")
                line6.put(24, 4, e("z9bb", sales.int("sales-credit"), 0))
                line6.put(41, 8, e("zzzz,zz9", sales.int("sales-limit"), 0))
                let limit = sales.int("sales-limit") * 100
                if current > limit {
                    line6.put(5, 12, e("zzz,zz9.99bb", current - limit))
                    line6.put(0, 5, s.t("sl120.over"))
                } else {
                    line6.put(5, 12, "")
                }
                if current < 0 { line6.put(55, 8, s.t("sl120.cr_bal")) }
                headings1()
                if unapplied == 0 { return }
                line5.put(121, 10, e("zzzzzz9.99", unapplied))
                line5.put(54, 20, s.t("sl120.unapplied_cash"))
                balPay += unapplied
                prt.after(line5.text, 2)
                line5.clear()
                lineCnt = (lineCnt + 2) % 100
                if lastRead != salesKey { endStatement() }
                return
            }
        }

        func readSalesTest() {
            truth = 1
            let current = sales.int("sales-current")
            if current == 0 { truth = 0 }
            let lastPay = sales.int("sales-last-pay"), lastInv = sales.int("sales-last-inv")
            payDate = lastPay > lastInv ? lastPay : lastInv
            if current == 0 && payDate > s.sys.int("s-end-cycle-date") { truth = 1 }
            if current == 0 && lastPay != 0 && lastPay == lastInv {
                truth = 0
                // test-for-inv
                if lastRead == sales.str("sales-key") && oi.int("oi-type") != 1 { truth = 1 }
            }
            if payValue != 0 && current < payValue { truth = 0 }
        }

        // MARK: check-zero

        func checkZero() {
            let type = oi.int("oi-type")
            if type == 3 {
                if invAmount == 0 {
                    line5.put(74, 1, "<"); line5.put(87, 1, ">")
                    line5.put(75, 12, e("zzzzzz9.99cr", -oi.int("oi-paid")))
                }
            } else if type == 5 || type == 6 {
                if oi.int("oi-paid") == oi.int("oi-approp") {
                    line5.put(120, 1, "<"); line5.put(131, 1, ">")
                    line5.put(121, 10, e("zzzzzz9.99", oi.int("oi-paid")))
                } else {
                    line5.put(121, 10, e("zzzzzz9.99", oi.int("oi-paid") - oi.int("oi-approp")))
                }
            } else if amountOut == 0 {
                line5.put(74, 1, "<"); line5.put(87, 1, ">")
                line5.put(75, 12, e("zzzzzz9.99cr", oi.int("oi-paid")))
            }
        }
    }
}
