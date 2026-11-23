import Foundation

/// incomplete_records_system/irs040.cbl: 試算表 (要約 / 明細、画面表示 / 印刷)
enum IRS040 {
    static let progName = "irs040 (3.01.12)"

    final class State {
        var wsLines = 24
        var acceptLines: Int { wsLines - 1 }
        var l22: Int { wsLines - 2 }
        var showLines: Int { wsLines - 3 }
        var outputReply = " "
        var wsReply = " "
        var tipe = "D"
        var empty = " "
        var counter = 0
        var pPage = 0
        var totalDr: Int64 = 0, totalCr: Int64 = 0
        var mainCr: Int64 = 0, mainDr: Int64 = 0, mainAc: Int64 = 0
        var mainName = Cobol.x("", 24)
        var wsSubNot = 0
        var lineCnt = 99
        var lin = 0
        var weError = 0
        var pReport = Cobol.x("", 8)
        var nl = IRS.newNL()
        // line-5
        var pAccount: Int64 = 0, pName = "", pLegend = "", pDebit: Int64 = 0, pCredit: Int64 = 0
        var summary: Bool { tipe == "S" }
        var doPrint: Bool { empty == "Y" }
    }

    static func s9(_ v: Int64) -> Int64 { IRS030.s9(v) }

    static func line1(_ s: Session, _ st: State) -> String {
        let sys = IRS.context(s).sys
        return Cobol.x(sys.str("suser"), 24) + Cobol.x("", 5) + Cobol.x(st.pReport, 8) + Cobol.x(s.t("report.irs040.trial_balance"), 13)
            + Cobol.x("", 6) + sys.str("run-date") + Cobol.x("", 7) + Cobol.x(s.t("report.irs040.page"), 5)
            + Pic.edit("zz9", value: Int64(st.pPage % 1000), scale: 0)
    }
    static func line3(_ s: Session) -> String {
        let sys = IRS.context(s).sys
        return Cobol.x(sys.str("client"), 24) + Cobol.x(s.t("report.irs040.start_date"), 17) + sys.str("start-date")
            + Cobol.x(s.t("report.irs040.end_date"), 22) + sys.str("end-date")
    }
    static func line4(_ s: Session) -> String {
        Cobol.x(s.t("report.irs040.account_name"), 37) + Cobol.x(s.t("report.irs040.type"), 19) + Cobol.x(s.t("report.irs040.debit_credit"), 24)
    }
    static func amount(_ v: Int64, bwz: Bool) -> String {
        bwz && v == 0 ? Cobol.x("", 12) : Pic.edit("z(8)9.99", value: v, scale: 2)
    }
    static func line5(_ st: State) -> String {
        (st.pAccount == 0 ? Cobol.x("", 6) : " " + Pic.edit("zzzz9", value: st.pAccount, scale: 0)) + Cobol.x("", 6)
            + Cobol.x(st.pName, 24) + Cobol.x("", 4) + Cobol.x(st.pLegend, 16) + amount(st.pDebit, bwz: true) + amount(st.pCredit, bwz: true)
    }
    static func line6() -> String { Cobol.x("", 57) + "=========== ===========" }
    static func line7(_ s: Session, _ st: State, errcnt: Int) -> String {
        (errcnt == 0 ? "    " : Pic.edit("zzzz", value: Int64(errcnt), scale: 0)) + Cobol.x("", 37)
            + Cobol.x(s.t("report.irs040.total"), 15) + amount(st.totalDr, bwz: false) + amount(st.totalCr, bwz: false)
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let ctx = IRS.context(s)
        let st = State()
        ctx.fileNames = ctx.sys.str("system-files")
        runLoop: while true {
            st.totalDr = 0; st.totalCr = 0; st.wsSubNot = 0
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("irs040.title"), at: 131, color: 1, reverse: true)
            c.display(ctx.sys.str("run-date"), at: 173, color: 2)
            c.display(s.t("irs040.summary_or_detail"), at: 501, color: 2)
            c.display(s.t("irs040.zero_balances"), at: 701, color: 2)
            c.display(s.t("irs040.return_to_exit"), at: 741, color: 2)
            c.display(s.t("irs040.display_or_print"), at: 901, color: 2)
            st.tipe = try c.accept(at: 536, size: 1, options: [.auto]).uppercased()
            if st.tipe == " " { return }
            if !st.summary && st.tipe != "D" { continue runLoop }
            st.pReport = Cobol.x(s.t(st.summary ? "report.irs040.summary" : "report.irs040.detail"), 8)
            repeat {
                st.empty = try c.accept(at: 736, size: 1, options: [.auto]).uppercased()
                if st.empty == " " { return }
            } while st.empty != "Y" && st.empty != "N"
            repeat {
                st.outputReply = try c.accept(at: 936, size: 1, options: [.auto]).uppercased()
            } while st.outputReply != "D" && st.outputReply != "P"
            st.mainCr = 0; st.mainDr = 0; st.mainAc = 0; st.wsSubNot = 0
            st.mainName = Cobol.x("", 24)
            if st.outputReply == "D" { try displayTB(s, st) } else {
                c.display(" ", at: 101, eraseEOS: true)
                try printTB(s, st)
            }
        }
    }

    /// 1 レコード分の集計。true = line-5 を出力する (main-display-1 / main-print-1 へ)
    static func process(_ s: Session, _ st: State, zeroCheck: Bool) -> Bool {
        if st.summary {
            if st.nl.int("sub-nominal") == 0 {
                if st.mainAc != 0 && !(st.mainDr == st.mainCr && !st.doPrint) {
                    setAmounts(st, st.mainDr, st.mainCr)
                    st.pLegend = s.t("report.irs040.main")
                    st.pAccount = st.mainAc
                    st.pName = st.mainName
                    st.mainAc = st.nl.int("owning")
                    st.mainName = st.nl.str("name")
                    st.mainDr = s9(st.nl.int("dr"))
                    st.mainCr = s9(st.nl.int("cr"))
                    return true
                }
                st.mainAc = st.nl.int("owning")
                st.mainDr = s9(st.nl.int("dr"))
                st.mainCr = s9(st.nl.int("cr"))
                st.mainName = st.nl.str("name")
                return false
            }
            st.mainDr = s9(st.mainDr + st.nl.int("dr"))
            st.mainCr = s9(st.mainCr + st.nl.int("cr"))
            if st.nl.int("owning") != st.mainAc { st.wsSubNot = (st.wsSubNot + 1) % 10000 }
            return false
        }
        let dr = st.nl.int("dr"), cr = st.nl.int("cr")
        if zeroCheck && dr == cr && !st.doPrint { return false }
        setAmounts(st, dr, cr)
        if st.nl.int("sub-nominal") == 0 {
            st.pLegend = s.t("report.irs040.main"); st.pAccount = st.nl.int("owning")
        } else {
            st.pLegend = s.t("report.irs040.sub"); st.pAccount = st.nl.int("sub-nominal")
        }
        st.pName = st.nl.str("name")
        return true
    }

    static func setAmounts(_ st: State, _ dr: Int64, _ cr: Int64) {
        if dr > cr {
            let w = s9(dr - cr)
            st.pDebit = w; st.pCredit = 0
            st.totalDr = s9(st.totalDr + w)
        } else {
            let w = s9(cr - dr)
            st.pCredit = w; st.pDebit = 0
            st.totalCr = s9(st.totalCr + w)
        }
    }

    static func clearLine5(_ st: State) {
        st.pAccount = 0; st.pName = ""; st.pLegend = ""; st.pDebit = 0; st.pCredit = 0
    }

    // MARK: display-tb

    static func displayTB(_ s: Session, _ st: State) throws {
        let c = s.console
        st.weError = try IRSub1.open(s, .input)
        st.totalCr = 0; st.totalDr = 0; st.counter = 0
        st.pPage = 1
        func dispHead1() {
            c.display(line1(s, st), at: 101, color: 2, eraseEOS: true)
            c.display(st.pReport, at: 130, color: 1, reverse: true)
            c.display(Cobol.x(s.t("report.irs040.trial_balance"), 13), at: 138, color: 1, reverse: true)
            c.display(line3(s), at: 301, color: 3)
            c.display(s.t("irs040.start_date"), at: 329, color: 2)
            c.display(s.t("irs040.end_date"), at: 361, color: 2)
            c.display(line4(s), at: 501, color: 2)
            c.display(s.t("irs040.next_or_exit"), at: st.wsLines, 1, color: 2)
        }
        dispHead1()
        st.lin = 6
        st.counter += 1
        while true {
            if st.weError == 3 { break }
            st.weError = IRSub1.readNext(s, &st.nl)
            clearLine5(st)
            if st.weError == 3 {
                st.nl.setInt("owning", 0); st.nl.setInt("cr", 0); st.nl.setInt("dr", 0)
                if !st.summary { break }
            }
            if !process(s, st, zeroCheck: true) { continue }
            c.display(line5(st), at: st.lin, 1, color: 3)
            st.nl.setInt("dr", 0); st.nl.setInt("cr", 0)
            if st.weError == 3 { break }
            st.lin += 1
            if st.lin < st.showLines { continue }
            st.lin = 6
            st.wsReply = try c.accept(at: st.wsLines, 43, size: 1, options: [.auto]).uppercased()
            if st.wsReply == "X" {
                IRSub1.close(s)
                return
            }
            st.wsReply = " "
            st.counter = (st.counter + 1) % 100
            st.pPage = st.counter
            dispHead1()
        }
        // total-display
        c.display(line6(), at: st.showLines, 1, color: 2)
        c.display(line7(s, st, errcnt: 0), at: st.l22, 1, color: 3)
        c.display(line6(), at: st.acceptLines, 1, color: 2)
        c.display(" ", at: st.wsLines, 1, eraseEOL: true)
        c.display(s.t("irs040.return_for_menu"), at: st.wsLines, 1, color: 2)
        if st.wsSubNot != 0 { c.display(Cobol.z(st.wsSubNot, 4), at: st.wsLines, 26, color: 3, highlight: true) }
        st.wsReply = try c.accept(at: st.wsLines, 23, size: 1)
        IRSub1.close(s)
    }

    // MARK: print-tb

    static func printTB(_ s: Session, _ st: State) throws {
        st.totalCr = 0; st.totalDr = 0
        let p = IRS.Printer(s, "prt-1")
        st.counter = 0
        func headings() {
            st.counter = (st.counter + 1) % 100
            st.pPage = st.counter
            if st.counter == 1 { p.write(line1(s, st), after: 1) } else { p.writePage(line1(s, st)) }
            p.write(line3(s), after: 2)
            p.write(line4(s), after: 2)
            p.write("", after: 1)
            st.lineCnt = 6
        }
        headings()
        st.weError = try IRSub1.open(s, .input)
        while true {
            if st.weError == 3 { break }
            st.weError = IRSub1.readNext(s, &st.nl)
            clearLine5(st)
            if st.weError == 3 {
                st.nl.setInt("owning", 0); st.nl.setInt("cr", 0); st.nl.setInt("dr", 0)
                if !st.summary { break }
            }
            // 印刷の明細ではゼロ残高の抑止を行わない (レガシーのまま)
            if !process(s, st, zeroCheck: false) { continue }
            p.write(line5(st), after: 1)
            st.lineCnt += 1
            if st.lineCnt > 75 { headings() }
            st.nl.setInt("dr", 0); st.nl.setInt("cr", 0)
            if st.weError == 3 { break }
        }
        p.write(line6(), after: 3)
        p.write(line7(s, st, errcnt: st.wsSubNot), after: 1)
        p.write(line6(), after: 1)
        p.spool()
        IRSub1.close(s)
    }
}
