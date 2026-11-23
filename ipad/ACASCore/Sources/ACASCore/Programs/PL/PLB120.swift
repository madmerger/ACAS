import Foundation

/// pl120.cbl: 買掛金年齢表 (Aged Creditors Report)
enum PLB120 {
    static let progName = "PL120 (3.01.08)"

    final class State {
        let s: Session
        let prt: PLBPrint
        let pf: IndexedFile
        var purch = Record(PLB.purch)
        var purchKey = [UInt8](repeating: 0x20, count: 7)
        var oi = Record(PLB.oi)
        var sorted = false
        var sortKeys: [[UInt8]] = []
        var sortIdx = 0
        var readFailed = false
        var customerIn = [UInt8](repeating: 0x20, count: 7)
        var lastRead = [UInt8](repeating: 0x20, count: 7)
        var payValue: Int64 = 0
        var enteredDate: Int64 = 0
        var pageNos = 0, lineCnt = 66
        var invAmount: Int64 = 0, amountOut: Int64 = 0
        var work1: Int64 = 0            // s9(7)v99
        var a: Int64 = 0
        // analysis
        var inv = [Int64](repeating: 0, count: 4)
        var totBal = [Int64](repeating: 0, count: 4)
        var totNoPay: Int64 = 0, totNoCrBal: Int64 = 0, totAcctActive: Int64 = 0, totAcctLive: Int64 = 0
        var totNoUnappPay: Int64 = 0, totPromptLostNo: Int64 = 0
        var totAmtLate: Int64 = 0, totAmtPay: Int64 = 0, totAmtCrBal: Int64 = 0, totAmtUnappPay: Int64 = 0
        var totUnapplCredits: Int64 = 0, totSalesBal: Int64 = 0, totPromptLostAmt: Int64 = 0
        // balances
        var bal = [Int64](repeating: 0, count: 4)
        var balPay: Int64 = 0, balT: Int64 = 0
        // 帳票行
        var l1Sorted = ""
        var l3List = PLB.Buf(20)
        var l3Date = ""
        var line4: String
        var line5 = PLB.Buf(132)
        var line6 = PLB.Buf(132)
        var line8 = PLB.Buf(90)
        init(_ s: Session) {
            self.s = s
            prt = PLBPrint(s)
            pf = PLB.purchFile(s)
            l3List.put(0, 18, s.l10n.raw("report.pl120.current_period"))
            line4 = s.l10n.raw("report.pl120.line4")
            line6.put(17, 7, s.l10n.raw("report.pl120.terms"))
            line6.put(28, 13, s.l10n.raw("report.pl120.credit_limit"))
        }
        var pageLines: Int { Int(s.sys.int("page-lines")) }
        var customerBlank: Bool { customerIn.allSatisfy { $0 == 0x20 } }
    }

    // line-5 の項目位置
    static let l5Account = (0, 9), l5Name = (9, 32), l5Telephone = (41, 13), l5Title = (54, 20)
    static let l5Invoice = (54, 8), l5Hold = (62, 1), l5Late = (63, 1), l5Date = (64, 10)
    static let l5Less = (74, 1), l5Bal0 = (75, 12), l5Greater = (87, 1), l5Bal30 = (88, 11), l5Bal60 = (99, 11)
    static let l5Bal90 = (110, 10), l5Less1 = (120, 1), l5Payments = (121, 10), l5Greater1 = (131, 1)
    // line-6
    static let l6Lover = (0, 5), l6Over = (5, 12), l6Credit = (24, 4), l6Limit = (41, 8), l6Lbalance = (55, 8)
    static let l6Balance = (63, 11), l6Bal0 = (74, 13), l6Bal30 = (87, 11), l6Bal60 = (98, 11), l6Bal90 = (109, 11)
    static let l6Payments = (120, 11)
    // line-8 / line-10
    static let l8Head = (0, 25), l8Hd2 = (1, 24), l8Tot = (25, 13), l8v0 = (38, 13), l8v30 = (51, 13), l8v60 = (64, 13), l8v90 = (77, 13)
    static let l10Tot = (25, 13), l10v0 = (38, 13), l10v30 = (51, 13), l10v60 = (64, 13), l10v90 = (77, 8)

    static func money(_ pic: String, _ v: Int64) -> String { Pic.edit(pic, value: v, scale: 2) }
    static func count(_ pic: String, _ v: Int64) -> String { Pic.edit(pic, value: v, scale: 0) }

    static func run(_ s: Session) throws {
        let c = s.console
        if s.sys.int("p-flag-p") == 1 {
            try PLB.maps99(s, 24)
            try PLB.maps99(s, 15)
            return
        }
        if PLB.fileStatus(s, 29) != 1 {
            try PLB.maps99(s, 25)
            try PLB.maps99(s, 15)
            return
        }
        let st = State(s)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("pl120.title"), at: 131, color: 2)
        c.display(PLB.wsDate(s), at: 171, color: 2)
        try trailBalance(st)
        reportAnalysis(st)
        st.prt.close()
        st.prt.spool()
    }

    static func trailBalance(_ st: State) throws {
        let s = st.s, c = s.console
        c.display(s.t("pl120.box1"), at: 441, color: 2)
        c.display(s.t("pl120.box2"), at: 541, color: 2)
        c.display(s.t("pl120.box3"), at: 641, color: 2)
        c.display(s.t("pl120.box4"), at: 741, color: 2)
        c.display(s.t("pl120.box1"), at: 841, color: 2)
        c.display(s.t("pl120.notes"), at: 1201, color: 2)
        c.display("*****", at: 1301, color: 2)
        c.display(s.t("pl120.note1"), at: 1501, color: 2)
        c.display(s.t("pl120.note2"), at: 1601, color: 2)
        c.display(s.t("pl120.note3"), at: 1701, color: 2)
        c.display(s.t("pl120.note4"), at: 1801, color: 2)
        // date-input
        var wsDate = PLB.wsDate(s)
        while true {
            c.crtStatus = 0
            c.display(wsDate, at: 549, color: 3)
            wsDate = try c.accept(at: 549, size: 10, initial: wsDate, options: [.update], color: 3)
            let bin = PLB.validateDate(s, wsDate)
            if bin == 0 { continue }
            st.l3Date = wsDate
            st.enteredDate = Int64(bin)
            break
        }
        if c.crtStatus == 1001 { st.sorted = true }
        // customer-input
        st.customerIn = SJIS.encode(try c.accept(at: 572, size: 7, color: 3).uppercased(), size: 7)
        if c.crtStatus == 1001 { st.sorted = true }
        // value-input (accept-money)
        c.display("000000.00", at: 750, color: 3)
        let amt = Array(try c.accept(at: 750, size: 9, initial: "000000.00", options: [.update], color: 3).utf8)
        func digits(_ b: ArraySlice<UInt8>) -> Int64 { b.reduce(0) { $0 * 10 + Int64($1 & 0x0f) % 10 } }
        st.payValue = Cobol.truncate(digits(amt[0..<6]) * 100 + digits(amt[7..<9]), digits: 8)
        if c.crtStatus == 1001 { st.sorted = true }

        st.prt.openOutput()
        st.pageNos = 0
        if st.sorted {
            st.l1Sorted = s.l10n.raw("report.pl120.sorted")
            guard let keys = PLB.readSequential(s, s.ledgers + PLB165.sortName, size: 7) else {
                // open 失敗: READ は AT END にならず、空の索引で "Not Found" を出し続けて戻らない
                headings(st)
                c.display(s.t("pl120.not_found"), at: 2301, color: 4)
                c.display(Cobol.x("", 7), at: 2313, color: 4)
                try PLB.hang(s)
            }
            st.sortKeys = keys
        }
        headings(st)
        if st.pf.open() != "00" { st.readFailed = true }
        guard let ois = PLB.readSequential(s, s.ledgers + "poisort.wrk", size: 109) else {
            st.pf.close()
            return
        }
        var oiIdx = 0
        if !st.customerBlank {
            st.purchKey = st.customerIn
            if !st.pf.start(notLessThan: st.customerIn) { st.readFailed = true }
            st.customerIn = st.customerIn.map { $0 == 0x20 ? 0x5a : $0 }
        }
        func gt(_ a: [UInt8], _ b: [UInt8]) -> Bool { b.lexicographicallyPrecedes(a) }

        readPerform: while true {
            if !readSales(st) { break }
            var atRoi1 = st.lastRead == st.purchKey
            while true {
                if !atRoi1 {
                    // read-open-item
                    if gt(st.lastRead, st.purchKey) { continue readPerform }
                    if oiIdx >= ois.count {
                        endStatement(st)
                        continue readPerform
                    }
                    st.oi = Record(PLB.oi, bytes: ois[oiIdx]); oiIdx += 1
                    st.lastRead = st.oi.raw("oi-supplier")
                    if gt(st.lastRead, st.purchKey) {
                        endStatement(st)
                        continue readPerform
                    }
                    if st.lastRead != st.purchKey {
                        bypassAgeing(st)
                        continue
                    }
                }
                atRoi1 = false
                roi1(st)
            }
        }
        st.pf.close()
    }

    /// roi-1 〜 bypass-age-go
    static func roi1(_ st: State) {
        let s = st.s, oi = st.oi
        let type = oi.int("oi-type")
        if type == 1 { return }
        if st.lineCnt > st.pageLines - 5 { headings(st) }
        if type == 5 || type == 6 { st.oi.setInt("oi-invoice", 0) }
        let invoice = st.oi.int("oi-invoice")
        st.line5.put(l5Invoice.0, l5Invoice.1, invoice % 100_000_000 == 0 ? "" : count("z(7)9", invoice))
        st.line5.put(l5Hold.0, 1, oi.str("oi-hold-flag"))
        st.line5.put(l5Date.0, 10, PLB.binDate(s, oi.int("oi-date")))
        st.invAmount = Cobol.truncate(oi.int("oi-net") + oi.int("oi-carriage") + oi.int("oi-vat") + oi.int("oi-c-vat"), digits: 9)
        let paid = oi.int("oi-paid"), deductAmt = oi.int("oi-deduct-amt"), deductDays = oi.int("oi-deduct-days")
        if type == 2 { st.amountOut = Cobol.truncate(st.invAmount - paid, digits: 9) }
        ageing: do {
            if type == 3 {
                st.invAmount = Cobol.truncate(st.invAmount + paid, digits: 9)
                st.line5.put(l5Bal0.0, l5Bal0.1, money("zzzzzz9.99cr", st.invAmount))
                checkZero(st)
                break ageing
            }
            if type == 5 || type == 6 {
                st.balPay = Cobol.truncate(st.balPay + paid, digits: 9)
                checkZero(st)
                break ageing
            }
            st.work1 = Cobol.truncate((st.enteredDate - oi.int("oi-date")) * 100, digits: 9)
            if st.work1 <= deductDays * 100 && deductAmt != 0 {
                st.invAmount = Cobol.truncate(st.invAmount - deductAmt, digits: 9)
                st.line5.put(l5Late.0, 1, "*")
            }
            if st.work1 > deductDays * 100 && deductAmt > 0 {
                st.totPromptLostNo = Cobol.truncate(st.totPromptLostNo + 1, digits: 5)
                st.totPromptLostAmt = Cobol.truncate(st.totPromptLostAmt + deductAmt, digits: 9)
            }
            let b: Int64 = st.amountOut == 0 ? 0 : 1
            if st.amountOut < 0 { st.work1 = 100 }
            let amt = st.amountOut
            let band = st.work1 < 3000 ? 0 : st.work1 < 6000 ? 1 : st.work1 < 9000 ? 2 : 3
            st.bal[band] = Cobol.truncate(st.bal[band] + amt, digits: 9)
            switch band {
            case 0:
                st.line5.put(l5Bal0.0, l5Bal0.1, money("zzzzzz9.99cr", amt))
                checkZero(st)
            case 1: st.line5.put(l5Bal30.0, l5Bal30.1, money("zzzzzzz9.99", amt))
            case 2: st.line5.put(l5Bal60.0, l5Bal60.1, money("zzzzzzz9.99", amt))
            default: st.line5.put(l5Bal90.0, l5Bal90.1, money("zzzzzz9.99", amt))
            }
            st.totBal[band] = Cobol.truncate(st.totBal[band] + amt, digits: 10)
            st.inv[band] = Cobol.truncate(st.inv[band] + b, digits: 6)
            st.balT = Cobol.truncate(st.balT + amt, digits: 9)
        }
        bypassAgeing(st)
        // bypass-age-go
        if type == 3 && st.invAmount != 0 {
            st.totUnapplCredits = Cobol.truncate(st.totUnapplCredits + st.invAmount, digits: 9)
        }
        st.amountOut = 0
        if !st.line5.str(l5Account.0, l5Account.1).allSatisfy({ $0 == " " }) {
            st.prt.after("", 1)
            st.lineCnt = PLB.addChar(st.lineCnt, 1)
        }
        st.prt.after(st.line5.text, 1)
        st.lineCnt = PLB.addChar(st.lineCnt, 1)
        st.line5.clear()
    }

    static func bypassAgeing(_ st: State) {
        let type = st.oi.int("oi-type")
        if (type == 5 || type == 6) && st.oi.int("oi-deduct-amt") != 0 {
            st.totAmtLate = Cobol.truncate(st.totAmtLate + st.oi.int("oi-deduct-amt"), digits: 9)
        }
        if type == 5 || type == 6 {
            st.totAmtPay = Cobol.truncate(st.totAmtPay + st.oi.int("oi-paid"), digits: 9)
            st.totNoPay = Cobol.truncate(st.totNoPay + 1, digits: 5)
        }
    }

    static func endStatement(_ st: State) {
        st.line6.put(l6Bal0.0, l6Bal0.1, money("zzzz,zz9.99cr", st.bal[0]))
        st.line6.put(l6Bal30.0, l6Bal30.1, money("zzzz,zz9.99", st.bal[1]))
        st.line6.put(l6Bal60.0, l6Bal60.1, money("zzzz,zz9.99", st.bal[2]))
        st.line6.put(l6Bal90.0, l6Bal90.1, money("zzzz,zz9.99", st.bal[3]))
        st.line6.put(l6Payments.0, l6Payments.1, money("zzzz,zz9.99", st.balPay))
        if !st.line6.str(l6Lbalance.0, l6Lbalance.1).allSatisfy({ $0 == " " }) {
            st.prt.after(st.line6.text, 1)
            st.prt.after("", 1)
            st.line6.put(l6Lbalance.0, l6Lbalance.1, "")
            st.lineCnt = PLB.addChar(st.lineCnt, 2)
        }
        st.bal = [0, 0, 0, 0]; st.balPay = 0; st.balT = 0
    }

    static func checkZero(_ st: State) {
        let type = st.oi.int("oi-type"), paid = st.oi.int("oi-paid")
        if type == 3 {
            if st.invAmount == 0 {
                st.line5.put(l5Less.0, 1, "<"); st.line5.put(l5Greater.0, 1, ">")
                st.line5.put(l5Bal0.0, l5Bal0.1, money("zzzzzz9.99cr", -paid))
            }
        } else if type == 5 || type == 6 {
            let approp = st.oi.int("oi-net")
            if paid == approp {
                st.line5.put(l5Less1.0, 1, "<"); st.line5.put(l5Greater1.0, 1, ">")
                st.line5.put(l5Payments.0, l5Payments.1, money("zzzzzz9.99", paid))
            } else {
                st.line5.put(l5Payments.0, l5Payments.1, money("zzzzzz9.99", paid - approp))
            }
        } else if st.amountOut == 0 {
            st.line5.put(l5Less.0, 1, "<"); st.line5.put(l5Greater.0, 1, ">")
            st.line5.put(l5Bal0.0, l5Bal0.1, money("zzzzzz9.99cr", paid))
        }
    }

    static func headings(_ st: State) {
        let s = st.s
        if st.lineCnt < st.pageLines - 5 { return }
        st.pageNos = PLB.addChar(st.pageNos, 1)
        if st.lineCnt != 99 {
            let cyc = s.sys.int("scycle") % 100
            st.l3List.put(18, 2, cyc == 0 ? "" : count("z9", cyc))
        }
        let line1 = Cobol.x(progName, 56) + Cobol.x(s.l10n.raw("report.pl120.title"), 22) + Cobol.x(st.l1Sorted, 8)
            + Cobol.x("", 38) + Cobol.x(s.l10n.raw("report.plb.page"), 5) + count("zz9", Int64(st.pageNos))
        let line3 = Cobol.x(s.sys.str("usera"), 56) + st.l3List.text + Cobol.x("", 46) + Cobol.x(st.l3Date, 10)
        if st.pageNos != 1 {
            st.prt.afterPage(line1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
        }
        st.prt.after(line3, 1)
        st.prt.after(st.line4, 2)
        st.lineCnt = 0
    }

    /// read-sales section: 次に印字対象となる仕入先を読む。false = fs-reply 99 (終了)
    static func readSales(_ st: State) -> Bool {
        let s = st.s, c = s.console
        while true {
            if st.sorted {
                guard st.sortIdx < st.sortKeys.count else { return false }
                st.purchKey = st.sortKeys[st.sortIdx]; st.sortIdx += 1
                guard let r = st.pf.read(key: st.purchKey) else {
                    c.display(s.t("pl120.not_found"), at: 2301, color: 4)
                    c.display(SJIS.decode(st.purchKey[...]), at: 2313, color: 4)
                    continue
                }
                st.purch = r
            } else {
                if st.readFailed { return false }
                guard let r = st.pf.readNext() else { return false }
                st.purch = r
                st.purchKey = r.raw("purch-key")
            }
            if !st.customerBlank && st.customerIn.lexicographicallyPrecedes(st.purchKey) { return false }
            st.totAcctLive = Cobol.truncate(st.totAcctLive + 1, digits: 5)
            var current = st.purch.int("purch-current")
            let unapplied = st.purch.int("purch-unapplied")
            st.totSalesBal = Cobol.truncate(st.totSalesBal + current, digits: 9)
            if unapplied != 0 && current != 0 {
                st.totAmtUnappPay = Cobol.truncate(st.totAmtUnappPay + unapplied, digits: 9)
                st.totNoUnappPay = Cobol.truncate(st.totNoUnappPay + 1, digits: 5)
            }
            if unapplied != 0 {
                st.totSalesBal = Cobol.truncate(st.totSalesBal - unapplied, digits: 9)
                current = Cobol.truncate(current - unapplied, digits: 10)
                st.purch.setInt("purch-current", current)
            }
            if current < 0 {
                st.totNoCrBal = Cobol.truncate(st.totNoCrBal + 1, digits: 5)
                st.totAmtCrBal = Cobol.truncate(st.totAmtCrBal + current, digits: 9)
            }
            if !readSalesTest(st) { continue }
            st.line5.put(l5Name.0, l5Name.1, st.purch.str("purch-name"))
            st.totAcctActive = Cobol.truncate(st.totAcctActive + 1, digits: 5)
            st.line5.put(l5Account.0, l5Account.1, st.purch.str("purch-key"))
            st.line5.put(l5Telephone.0, l5Telephone.1, st.purch.str("purch-phone"))
            st.line6.put(l6Balance.0, l6Balance.1, money("zzzz,zz9.99", current))
            st.line6.put(l6Lbalance.0, l6Lbalance.1, s.l10n.raw("report.pl120.balance"))
            st.line6.put(l6Lover.0, l6Lover.1, "")
            st.line6.put(l6Credit.0, l6Credit.1, count("z9bb", st.purch.int("purch-credit")))
            let limit = st.purch.int("purch-limit")
            st.line6.put(l6Limit.0, l6Limit.1, count("zzzz,zz9", limit))
            if current > limit * 100 {
                let over = current - limit * 100
                st.line6.put(l6Over.0, l6Over.1, over % 100_000_000 == 0 ? "" : money("zzz,zz9.99bb", over))
                st.line6.put(l6Lover.0, l6Lover.1, s.l10n.raw("report.pl120.over"))
            } else {
                st.line6.put(l6Over.0, l6Over.1, "")
            }
            if current < 0 { st.line6.put(l6Lbalance.0, l6Lbalance.1, s.l10n.raw("report.pl120.cr_bal")) }
            headings(st)
            if unapplied == 0 { return true }
            st.line5.put(l5Payments.0, l5Payments.1, money("zzzzzz9.99", unapplied))
            st.line5.put(l5Title.0, l5Title.1, s.l10n.raw("report.pl120.unapplied_cash"))
            st.balPay = Cobol.truncate(st.balPay + unapplied, digits: 9)
            st.prt.after(st.line5.text, 2)
            st.line5.clear()
            st.lineCnt = PLB.addChar(st.lineCnt, 2)
            if st.lastRead != st.purchKey { endStatement(st) }
            return true
        }
    }

    static func readSalesTest(_ st: State) -> Bool {
        let p = st.purch
        let current = p.int("purch-current"), lastPay = p.int("purch-last-pay"), lastInv = p.int("purch-last-inv")
        var truth = current != 0
        let payDate = lastPay > lastInv ? lastPay : lastInv
        if current == 0 && payDate > st.s.sys.int("s-end-cycle-date") { truth = true }
        if current == 0 && lastPay != 0 && lastPay == lastInv {
            truth = false
            if st.lastRead == st.purchKey { truth = true }
        }
        if st.payValue != 0 && current < st.payValue { truth = false }
        return truth
    }

    static func reportAnalysis(_ st: State) {
        let s = st.s, prt = st.prt
        func r(_ k: String) -> String { s.l10n.raw("report.pl120." + k) }
        func put(_ f: (Int, Int), _ t: String) { st.line8.put(f.0, f.1, t) }
        let crPic = "zzzz,zz9.99cr", nPic = "zzzz,zz9bbbbb"
        func line10() -> String { st.line8.prefix(85) }
        st.l3List.put(0, 20, r("account_statistics"))
        st.line4 = ""; st.l1Sorted = ""
        st.lineCnt = 99
        headings(st)
        prt.after(Cobol.x("", 29) + r("line7"), 1)
        prt.after("", 1)
        put(l8Head, r("number_of_invoices"))
        put(l10v0, count(nPic, st.inv[0])); put(l10v30, count(nPic, st.inv[1]))
        put(l10v60, count(nPic, st.inv[2])); put(l10v90, count("zzzz,zz9", st.inv[3]))
        st.a = st.inv[0] + st.inv[1] + st.inv[2] + st.inv[3]
        put(l10Tot, count(nPic, st.a))
        prt.after(line10(), 1)
        put(l8Head, r("amount"))
        put(l8v0, money(crPic, st.totBal[0])); put(l8v30, money(crPic, st.totBal[1]))
        put(l8v60, money(crPic, st.totBal[2])); put(l8v90, money(crPic, st.totBal[3]))
        let totOsBal = Cobol.truncate(st.totBal[0] + st.totBal[1] + st.totBal[2] + st.totBal[3], digits: 10)
        put(l8Tot, money(crPic, totOsBal))
        let work2 = Cobol.truncate(totOsBal, digits: 9)
        prt.after(st.line8.text, 1)
        put(l8Head, r("pct_os_invoices"))
        put(l8Tot, money(crPic, 10000))
        for (i, f) in [l8v0, l8v30, l8v60, l8v90].enumerated() {
            // work-2 が 0 の除算は桁あふれ扱いで work-1 は変わらない
            if work2 != 0 { st.work1 = Cobol.truncate(PLB.divRounded(st.totBal[i] * 100 * 100, work2), digits: 9) }
            put(f, money(crPic, st.work1))
        }
        prt.after(st.line8.text, 1)
        put(l8Head, r("average_os_amount"))
        for (i, f) in [l8v0, l8v30, l8v60, l8v90].enumerated() {
            put(f, money(crPic, st.inv[i] != 0 ? st.totBal[i] / st.inv[i] : 0))
        }
        if st.a != 0 { put(l8Tot, money(crPic, work2 / st.a)) }
        prt.after(st.line8.text, 1)
        prt.after(Cobol.x("", 29) + r("line9"), 3)
        st.line8.clear()
        put(l8Head, r("unapplied_cash"))
        put(l8v0, money(crPic, st.totAmtUnappPay))
        put(l10Tot, count(nPic, st.totNoUnappPay))
        prt.after(st.line8.text, 2)
        put(l8Head, r("payments"))
        put(l8v0, money(crPic, PLB.sys4Int(s, "pl-payments")))
        put(l10Tot, count(nPic, st.totNoPay))
        prt.after(st.line8.text, 1)
        put(l8Head, r("credit_balances"))
        put(l10Tot, count(nPic, st.totNoCrBal))
        put(l8v0, money(crPic, st.totAmtCrBal))
        prt.after(st.line8.text, 1)
        put(l8Head, r("prompt_lost"))
        put(l8v0, money(crPic, st.totPromptLostAmt))
        put(l10Tot, count(nPic, st.totPromptLostNo))
        prt.after(st.line8.text, 1)
        st.line8.clear()
        put(l8Head, r("live_accounts"))
        put(l10Tot, count(nPic, st.totAcctLive))
        prt.after(line10(), 1)
        put(l8Head, r("active_accounts"))
        put(l10Tot, count(nPic, st.totAcctActive))
        prt.after(line10(), 1)
        put(l8Head, r("pct_active"))
        if st.totAcctLive != 0 {
            st.work1 = Cobol.truncate(st.totAcctActive * 100 * 100 / st.totAcctLive, digits: 9)
        }
        put(l8Tot, money(crPic, st.work1))
        prt.after(st.line8.text, 1)
        if !st.customerBlank { return }

        func clear10() { for i in 0..<85 { st.line8.c[i] = " " } }
        var f1 = String(repeating: "-", count: 13), f2 = String(repeating: "-", count: 13)
        func line11() -> String { Cobol.x("", 25) + f1 + f2 }
        clear10()
        put(l8Head, r("reconciliation"))
        prt.after(line10(), 3)
        put(l8Head, "")
        prt.after(line10(), 1)
        let lastMonth = PLB.sys4Int(s, "pl-os-bal-last-month"), invoices = PLB.sys4Int(s, "pl-invoices-this-month")
        let credits = PLB.sys4Int(s, "pl-credit-notes-this-month"), payments = PLB.sys4Int(s, "pl-payments")
        put(l8Tot, money(crPic, lastMonth))
        put(l8Head, r("balance_bf"))
        prt.after(line10(), 1)
        put(l8Tot, money(crPic, invoices))
        put(l8Head, r("plus_invoices"))
        prt.after(line10(), 1)
        st.totBal[0] = Cobol.truncate(lastMonth + invoices, digits: 10)
        prt.after(line11(), 1)
        clear10()
        put(l8v0, money(crPic, st.totBal[0]))
        prt.after(line10(), 1)
        clear10()
        put(l8Tot, money(crPic, credits))
        put(l8Head, r("less_credit_notes"))
        prt.after(line10(), 2)
        put(l8Tot, money(crPic, payments))
        put(l8Head, r("payments_posted"))
        prt.after(line10(), 1)
        put(l8Tot, money(crPic, st.totAmtLate))
        put(l8Head, r("prompt_pay_taken"))
        prt.after(line10(), 1)
        prt.after(line11(), 1)
        st.totBal[1] = Cobol.truncate(st.totAmtLate + payments + credits, digits: 10)
        clear10()
        put(l8v0, money(crPic, st.totBal[1]))
        prt.after(line10(), 1)
        f1 = Cobol.x("", 13)
        prt.after(line11(), 2)
        st.totBal[0] = Cobol.truncate(st.totBal[0] - st.totBal[1], digits: 10)
        put(l8Head, r("balance_cf"))
        put(l8v0, money(crPic, st.totBal[0]))
        PLB.setSys4(s, "pl-os-bal-this-month", st.totBal[0])
        prt.after(line10(), 1)
        f2 = String(repeating: "=", count: 13)
        prt.after(line11(), 1)
        st.line8.clear()
        let variance = Cobol.truncate(st.totSalesBal - st.totBal[0], digits: 10)
        PLB.setSys4(s, "pl-variance", variance)
        put(l8Tot, money(crPic, variance))
        if variance != 0 {
            put(l8Hd2, r("out_of_balance"))
            PLB.addSys4(s, "pl-os-bal-this-month", variance)
            prt.after(line10(), 2)
        }
    }
}
