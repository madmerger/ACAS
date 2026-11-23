import Foundation

/// pl910.cbl: 支払予定の生成 (Cheque Due Reporting / Payments Due Report)
enum PLB910 {
    static let progName = "PL910 (3.01.07)"

    final class State {
        let s: Session
        let prt: PLBPrint
        let pf: IndexedFile, oiFile: IndexedFile, payFile: IndexedFile
        var pay = Record(PLB.pay)
        var toBePaid: Int64 = 0, uBin: Int64 = 0
        var a = 1, p = 0, lineCnt = 0
        var bal0: Int64 = 0, bal30: Int64 = 0, bal60: Int64 = 0, bal90: Int64 = 0, balT: Int64 = 0
        var tot0: Int64 = 0, tot30: Int64 = 0, tot60: Int64 = 0, tot90: Int64 = 0
        var l1Date = "", l1PriorDate = ""
        var l5Key = "", l5Supplier = "", l5Method = " "
        init(_ s: Session) {
            self.s = s; prt = PLBPrint(s)
            pf = PLB.purchFile(s); oiFile = PLB.oi5File(s); payFile = PLB.payFile(s)
        }
    }

    /// 符号無し 9(7)v99 への格納 (符号は落ち、上位桁は切り捨て)
    static func u9(_ v: Int64) -> Int64 { abs(v) % 1_000_000_000 }

    static func run(_ s: Session) throws {
        let st = State(s), c = s.console
        st.l1Date = PLB.wsDate(s)
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("pl910.title"), at: 132, color: 2)
        c.display(st.l1Date, at: 171, color: 2)
        c.display(s.t("pl910.age_to_pay"), at: 501, color: 2)
        var age = Cobol.truncate(s.sys.int("age-to-pay"), digits: 2, signed: false)
        c.display(Cobol.z(age, 2), at: 529, color: 3)
        c.display(s.t("pl910.correct"), at: 701, color: 2)
        let reply = try c.accept(at: 729, size: 1, color: 6).uppercased()
        if reply == "N" {
            age = try PLB.acceptNum(s, at: 529, digits: 2, color: 3)
            s.sys.setInt("age-to-pay", age)
        }
        st.toBePaid = PLB.wrap32(s.sys.int("run-date") - s.sys.int("age-to-pay"))
        st.uBin = st.toBePaid
        st.l1PriorDate = PLB.binDate(s, st.toBePaid)
        try chequeGen(st)
    }

    static func chequeGen(_ st: State) throws {
        let s = st.s, c = s.console
        let purchOpen = st.pf.open() == "00"
        let oiOpen = st.oiFile.open() == "00"
        st.prt.openOutput()
        st.payFile.openOutput()
        headings(st)
        // 開けていないファイルの READ NEXT は AT END にならず、処理が戻らない
        if !purchOpen { try PLB.hang(s) }
        let runDate = s.sys.int("run-date")
        let pageLines = Int(s.sys.int("page-lines"))
        readPurchase: while let purch = st.pf.readNext() {
            if purch.int("purch-current") <= 0 { continue }
            st.pay = Record(PLB.pay)
            let key = purch.str("purch-key")
            st.l5Key = key
            st.pay.set("pay-supl-key", key)
            st.pay.setInt("pay-nos", 1)
            // u-bin には直前の日付変換 (支払基準日または直前の明細日付) の値が残っている
            st.pay.setInt("pay-date", st.uBin)
            st.l5Supplier = purch.str("purch-name")
            if purch.int("purch-sortcode") != 0 {
                st.pay.setInt("pay-sortcode", purch.int("purch-sortcode"))
                st.pay.setInt("pay-account", purch.int("purch-accountno"))
                st.l5Method = "B"
            } else {
                st.l5Method = "C"
            }
            st.a = 1
            if !oiOpen { try PLB.hang(s) }
            st.oiFile.start(notLessThan: purch.raw("purch-key") + [0, 0, 0, 0])
            while true {
                guard let oi = st.oiFile.readNext() else {
                    // AT END: end-statement を実行して帳票を締める (残りの仕入先は処理されない)
                    endStatement(st)
                    break readPurchase
                }
                let status = oi.int("oi-status")
                if status == 1 || oi.str("oi-hold-flag") == "H" || oi.int("oi-b-nos") != 0 { continue }
                if oi.raw("oi-supplier") != purch.raw("purch-key") {
                    endStatement(st)
                    continue readPurchase
                }
                if oi.int("oi-type") != 2 { continue }
                if oi.int("oi-date") > st.toBePaid { continue }
                let a = st.a
                st.pay.setInt("pay-folio-\(a)", oi.int("oi-invoice"))
                st.uBin = oi.int("oi-date")
                let l5Date = PLB.binDate(s, oi.int("oi-date"))
                st.pay.set("pay-invoice-\(a)", oi.str("oi-ref"))
                let invAmount = Cobol.truncate(oi.int("oi-net") + oi.int("oi-carriage") + oi.int("oi-vat") + oi.int("oi-c-vat"), digits: 9)
                var amountOut = Cobol.truncate(invAmount - oi.int("oi-paid"), digits: 9)
                if amountOut == 0 { continue }
                let work1 = Cobol.truncate(runDate - oi.int("oi-date"), digits: 6)
                if oi.int("oi-deduct-days") >= work1 {
                    amountOut = Cobol.truncate(amountOut - oi.int("oi-deduct-amt"), digits: 9)
                    st.pay.setInt("pay-deduct-\(a)", oi.int("oi-deduct-amt"))
                    if amountOut == 0 { continue }
                    if amountOut < 0 {
                        c.display(s.t("pl910.pl901"), at: 2301, color: 4)
                        _ = try c.accept(at: 2338, size: 1)
                        continue
                    }
                }
                st.pay.setInt("pay-value-\(a)", amountOut)
                if work1 < 30 {
                    st.bal0 = u9(st.bal0 + amountOut); st.pay.setInt("pay-period-\(a)", 0)
                } else if work1 < 60 {
                    st.bal30 = u9(st.bal30 + amountOut); st.pay.setInt("pay-period-\(a)", 30)
                } else if work1 < 90 {
                    st.pay.setInt("pay-period-\(a)", 60); st.bal60 = u9(st.bal60 + amountOut)
                } else {
                    st.pay.setInt("pay-period-\(a)", 90); st.bal90 = u9(st.bal90 + amountOut)
                }
                st.balT = u9(st.balT + amountOut)
                st.pay.setInt("pay-gross", st.balT)
                st.tot0 = u9(st.tot0 + st.bal0); st.tot30 = u9(st.tot30 + st.bal30)
                st.tot60 = u9(st.tot60 + st.bal60); st.tot90 = u9(st.tot90 + st.bal90)
                func cr(_ v: Int64) -> String { PLB.bwz("z(6)9.99cr", v, scale: 2) }
                let line5 = Cobol.x(st.l5Key, 10) + Cobol.x(st.l5Supplier, 25)
                    + Pic.edit("z(7)9b", value: oi.int("oi-invoice"), scale: 0) + st.l5Method + " "
                    + Cobol.x(l5Date, 12) + Cobol.x(oi.str("oi-ref"), 11)
                    + cr(st.bal0) + cr(st.bal30) + cr(st.bal60) + cr(st.bal90) + "    "
                    + PLB.bwz("z(6)9.99", st.balT, scale: 2)
                st.prt.after(line5, 1)
                st.lineCnt = PLB.addChar(st.lineCnt, 1)
                if st.lineCnt > pageLines { headings(st) }
                st.bal0 = 0; st.bal30 = 0; st.bal60 = 0; st.bal90 = 0
                st.l5Key = ""; st.l5Supplier = ""
                st.a += 1
                if st.a > 9 {
                    st.a = 1
                    st.pay.set("pay-cont", "C")
                    st.payFile.write(st.pay)
                    st.pay.setInt("pay-gross", 0)
                    st.pay.setInt("pay-nos", st.pay.int("pay-nos") + 1)
                }
            }
        }
        // main-end
        func cr(_ v: Int64) -> String { PLB.bwz("z(6)9.99cr", v, scale: 2) }
        let dash = Cobol.x("  --------  ", 12)
        st.prt.after(Cobol.x("", 69) + dash + dash + dash + dash + "    " + Cobol.x("  ========", 12), 1)
        st.prt.after(Cobol.x(s.l10n.raw("report.pl910.total"), 69) + cr(st.tot0) + cr(st.tot30) + cr(st.tot60) + cr(st.tot90)
                     + "    " + PLB.bwz("z(6)9.99", (st.tot0 + st.tot30 + st.tot60 + st.tot90) % 1_000_000_000, scale: 2), 1)
        st.prt.close()
        st.oiFile.close(); st.pf.close(); st.payFile.close()
        st.prt.spool()
    }

    static func endStatement(_ st: State) {
        if st.a != 1 {
            st.payFile.write(st.pay)
            st.a = 1
        }
        if st.lineCnt > Int(st.s.sys.int("page-lines")) { headings(st) }
        st.balT = 0
    }

    static func headings(_ st: State) {
        let s = st.s
        st.p = (st.p + 1) % 100
        let line1 = Cobol.x(progName, 56) + Cobol.x(s.l10n.raw("report.pl910.title"), 24)
            + Cobol.x(s.l10n.raw("report.pl910.prior_to"), 9) + Cobol.x(st.l1PriorDate, 10) + Cobol.x("", 25)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.p), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 56) + Cobol.x("", 66) + Cobol.x(st.l1Date, 10)
        if st.p != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line2, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line2, 1)
        }
        st.prt.after(Cobol.x(s.l10n.raw("report.pl910.line4a"), 38) + Cobol.x(s.l10n.raw("report.pl910.line4b"), 94), 1)
        st.prt.after("", 1)
        st.lineCnt = 5
    }
}
