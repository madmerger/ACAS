import Foundation

/// incomplete_records_system/irs050.cbl: 転記帳票 (監査証跡 / 元帳 / 消費税日計表、画面表示 / 印刷)
enum IRS050 {
    static let progName = "irs050 (3.01.13)"

    static func s9(_ v: Int64) -> Int64 { IRS030.s9(v) }
    static func bwz(_ pic: String, _ v: Int64) -> String {
        let n = Pic.size(pic)
        let m = Cobol.pow10(pic.hasPrefix("-(6)") ? 8 : pic.hasPrefix("-(8)") ? 10 : 9)
        let t = v < 0 ? -((-v) % m) : v % m
        return t == 0 ? Cobol.x("", n) : Pic.edit(pic, value: t, scale: 2)
    }
    static func z5(_ v: Int64) -> String { Pic.edit("zzzz9", value: v % 100000, scale: 0) }

    final class Run {
        let s: Session
        let c: Console
        let ctx: IRS.Context
        var sortSequ = 0
        var useCode = "  ", saveCode = "  "
        var acMarker = 0, vatCheck = 0, lineCnt = 99, wsAccountUsed = 0
        var wsLines = 24
        var acceptLines: Int { wsLines - 1 }
        var l22: Int { wsLines - 2 }
        var l21: Int { wsLines - 3 }
        var l17: Int { wsLines - 7 }
        var wsReply = " ", empty = " "
        var counter = 0, pPage = 0
        var totalInNet: Int64 = 0, totalInVat: Int64 = 0, totalOutNet: Int64 = 0, totalOutVat: Int64 = 0
        var totalDr: Int64 = 0, totalCr: Int64 = 0
        var targetAccount: Int64 = 0, checkAccount: Int64 = 0, holdOwning: Int64 = 0
        var wsbStart = 0, wscEnd = 0
        var lin = 0
        var tipe = " ", outputReply = " "
        var periodStart = Cobol.x("", 8), periodEnd = Cobol.x("", 8)
        var post = IRS.newPost()
        var nl = IRS.newNL()
        var weError = 0
        var printer: IRS.Printer?
        // 印字行の項目
        var pReport = Cobol.x("", 36)
        var line6a = "", line6v = ""
        var pCodeA = "  "
        var pCodeL = "  ", pSpacerL = "/", pTranL: Int64 = 0, pDateL = Cobol.x("", 8), pLegendL = Cobol.x("", 32)
        var pContraL: Int64 = 0, pDebitL: Int64 = 0, pCreditL: Int64 = 0
        var ledgAccount: Int64 = 0, ledgName = Cobol.x("", 24)
        var audit: Bool { tipe == "A" }
        var ledgers: Bool { tipe == "L" }
        var vatReport: Bool { tipe == "D" }
        var doPrint: Bool { empty == "Y" }
        var postAmount: Int64 {
            get { IRS.getSigned(post, "amount") }
            set { IRS.setSigned(&post, "amount", newValue) }
        }
        var vatAmount: Int64 { IRS.getSigned(post, "vat-amount") }
        var vatAcDef: Int64 { IRS.isNumeric(post.raw("vat-ac-def")) ? post.int("vat-ac-def") : 0 }
        var def31: Int64 { Int64(IRS.defAc(ctx.dflt, 31)) }
        var def32: Int64 { Int64(IRS.defAc(ctx.dflt, 32)) }

        init(_ s: Session) { self.s = s; c = s.console; ctx = IRS.context(s) }

        // MARK: 印字行

        var line1: String {
            Cobol.x(ctx.sys.str("suser"), 24) + Cobol.x("", 5) + Cobol.x(pReport, 36) + Cobol.x("", 6) + ctx.sys.str("run-date")
        }
        var line3: String {
            Cobol.x(ctx.sys.str("client"), 24) + Cobol.x(s.t("report.irs050.end_date"), 15) + ctx.sys.str("end-date")
                + Cobol.x("", 24) + Cobol.x(s.t("report.irs050.page"), 5) + Pic.edit("zz9", value: Int64(pPage % 1000), scale: 0)
        }
        var line4a: String { Cobol.x(s.t("report.irs050.l4_a"), 43) + Cobol.x(s.t("report.irs050.l4_b"), 35) }
        var line5a: String { Cobol.x(s.t("report.irs050.l5_a"), 43) + Cobol.x(s.t("report.irs050.l5_b"), 35) }
        var line4v: String { Cobol.x(s.t("report.irs050.l4_c"), 37) + Cobol.x(s.t("report.irs050.l4_d"), 42) }
        var line5v: String { Cobol.x(s.t("report.irs050.l5_c"), 37) + Cobol.x(s.t("report.irs050.l5_d"), 42) }
        var line4l: String { Cobol.x(s.t("report.irs050.l4_e"), 79) }
        var line6l: String {
            pCodeL + pSpacerL + z5(pTranL) + "  " + Cobol.x(pDateL, 8) + "  " + Cobol.x(pLegendL, 32) + z5(pContraL)
                + bwz("-(7)9.99", pDebitL) + bwz("-(7)9.99", pCreditL)
        }
        let line7 = Cobol.x("", 36) + "---------- ---------- " + "---------- ----------"
        let line7a = Cobol.x("", 44) + "===========   ==========="
        let line7m = Cobol.x("", 58) + "---------- ----------"
        var line8: String {
            "   " + Cobol.x(s.t("report.irs050.total"), 5) + Cobol.x("", 27) + bwz("-(7)9.99", totalInNet) + bwz("-(7)9.99", totalInVat)
                + bwz("-(8)9.99", totalOutNet) + bwz("-(7)9.99", totalOutVat)
        }
        var lineLedger: String {
            Cobol.x(s.t("report.irs050.account"), 10) + z5(ledgAccount) + "    " + Cobol.x(ledgName, 24)
        }
        func setReport() {
            if vatReport {
                pReport = Cobol.x(Cobol.x(s.t("report.irs050.day_book"), 28) + periodEnd, 36)
            } else {
                pReport = Cobol.x(s.t("report.irs050.audit_trail"), 36)
            }
        }
        func pw(_ line: String, after n: Int) { printer?.write(Cobol.x(line, 79), after: n) }

        // MARK: main-flow section

        func main() throws {
            ctx.fileNames = ctx.sys.str("system-files")
            try IRSub3.read(s)
            var skipScreen = false
            runLoop: while true {
                if !skipScreen {
                    totalInNet = 0; totalInVat = 0; totalOutNet = 0; totalOutVat = 0; totalDr = 0; totalCr = 0
                    c.display(" ", at: 101, eraseEOS: true)
                    c.display(progName, at: 101, color: 2)
                    c.display(s.t("irs050.title"), at: 128, color: 1, reverse: true)
                    c.display(ctx.sys.str("run-date"), at: 173, color: 2)
                    c.display(s.t("irs050.report_required"), at: 501, color: 2)
                    c.display(s.t("irs050.return_to_exit"), at: 541, color: 2)
                    c.display(s.t("irs050.opt_audit"), at: 701, color: 2)
                    c.display(s.t("irs050.opt_ledgers"), at: 801, color: 2)
                    c.display(s.t("irs050.opt_day_book"), at: 901, color: 2)
                    c.display(s.t("irs050.display_or_print"), at: 1101, color: 2)
                    c.display(s.t("irs050.select_sort"), at: 1301, color: 2)
                    c.display(s.t("irs050.sort_1"), at: 1501, color: 2)
                    c.display(s.t("irs050.sort_2"), at: 1601, color: 2)
                    c.display(s.t("irs050.sort_3"), at: 1701, color: 2)
                    tipe = " "; wsReply = " "
                }
                skipScreen = false
                tipe = try c.accept(at: 536, size: 1, color: 6).uppercased()
                if tipe == " " { return }
                if !audit && !ledgers && !vatReport { continue runLoop }
                if vatReport {
                    while true {
                        c.display(s.t("irs050.period_start"), at: 741, color: 2)
                        c.display(s.t("irs050.period_end"), at: 941, color: 2)
                        periodStart = ctx.sys.str("start-date")
                        periodEnd = ctx.sys.str("end-date")
                        periodStart = try c.accept(at: 768, size: 8, initial: periodStart, options: [.update], color: 3)
                        periodEnd = try c.accept(at: 968, size: 8, initial: periodEnd, options: [.update], color: 3)
                        let a = Array(periodStart.utf8), b = Array(periodEnd.utf8)
                        guard a.count == 8, b.count == 8 else { continue }
                        func ok(_ x: [UInt8]) -> Bool {
                            IRS.isNumeric(Array(x[0..<2])) && IRS.isNumeric(Array(x[3..<5])) && IRS.isNumeric(Array(x[6..<8]))
                        }
                        if !ok(a) || !ok(b) { continue }
                        wsbStart = ymd(periodStart)
                        wscEnd = ymd(periodEnd)
                        break
                    }
                }
                repeat {
                    outputReply = try c.accept(at: 1136, size: 1, color: 6).uppercased()
                } while outputReply != "D" && outputReply != "P"
                repeat {
                    sortSequ = IRS.num(try c.accept(at: 1336, size: 1, kind: .numeric, color: 6))
                } while sortSequ < 1 || sortSequ > 3
                if Int64(sortSequ) != ctx.sys.int("save-sequ") {
                    ctx.sys.setInt("save-sequ", Int64(sortSequ))
                    ctx.sys["system-work-group"] = tipe + outputReply + periodStart + periodEnd
                    try IRS055.run(s)
                }
                if ledgers {
                    try ledgerReport()
                    continue runLoop
                }
                weError = IRSubP.open(s, .input)
                if weError == 99 {
                    c.display(s.t("irs050.no_posting_data"), at: acceptLines, 1, color: 4)
                    skipScreen = true
                    continue runLoop
                }
                if outputReply == "D" { try displayReport() } else { try reportPrint() }
            }
        }

        /// dd/mm/yy → yymmdd (数値でない桁は 0 として扱う)
        func ymd(_ d: String) -> Int {
            let a = Array(Cobol.x(d, 8))
            func n(_ i: Int) -> Int { Int(String(a[i..<(i + 2)])) ?? 0 }
            return n(6) * 10000 + n(3) * 100 + n(0)
        }

        // MARK: 監査証跡 / 消費税日計表の 1 行

        /// vat-area。false = 対象外。display では合計と明細、印刷でも同じ処理。
        func vatArea() -> Bool {
            let d = ymd(post.str("date"))
            if d < wsbStart || d > wscEnd { return false }
            let def = vatAcDef
            if def < 31 || def > 32 { return false }
            var inNet: Int64 = 0, inVat: Int64 = 0, outNet: Int64 = 0, outVat: Int64 = 0
            let side = post.str("vat-side")
            if def == 31 {
                inNet = postAmount; inVat = vatAmount
                if side == "DR" { totalInNet = s9(totalInNet + postAmount); totalInVat = s9(totalInVat + vatAmount) }
                if side == "CR" {
                    totalInNet = s9(totalInNet - postAmount); totalInVat = s9(totalInVat - vatAmount)
                    inNet = -postAmount; inVat = -vatAmount
                }
            } else {
                outNet = postAmount; outVat = vatAmount
                if side == "CR" { totalOutNet = s9(totalOutNet + postAmount); totalOutVat = s9(totalOutVat + vatAmount) }
                if side == "DR" {
                    totalOutNet = s9(totalOutNet - postAmount); totalOutVat = s9(totalOutVat - vatAmount)
                    outNet = -postAmount; outVat = -vatAmount
                }
            }
            line6v = "   " + z5(post.int("key")) + Cobol.x("", 5) + post.str("date") + Cobol.x("", 4) + post.str("code") + Cobol.x("", 8)
                + bwz("-(7)9.99", inNet) + bwz("-(7)9.99", inVat) + bwz("-(7)9.99", outNet) + bwz("-(7)9.99", outVat)
            return true
        }

        func auditLine() {
            pCodeA = post.str("code")
            let def = vatAcDef
            let type = def == 31 ? s.t("report.irs050.input") : def == 32 ? s.t("report.irs050.output") : ""
            line6a = "   " + z5(post.int("key")) + Cobol.x("", 5) + post.str("date") + "   " + post.str("code") + "    "
                + z5(post.int("dr")) + "   " + z5(post.int("cr")) + Pic.edit("-(9)9.99", value: postAmount, scale: 2) + " "
                + Pic.edit("-(9)9.99", value: vatAmount, scale: 2) + "    " + Cobol.x(type, 6)
        }

        func askCode() throws {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(s.t("irs050.input_code"), at: 501, color: 2)
            useCode = try c.accept(at: 542, size: 2, color: 6)
        }

        // MARK: display-report section

        func displayReport() throws {
            counter = 0
            useCode = "  "
            if audit { try askCode() }
            pages: while true {
                counter = (counter + 1) % 1000
                pPage = counter
                c.display(" ", at: 101, eraseEOS: true)
                setReport()
                c.display(line1, at: 101, color: 2)
                c.display(line3, at: 301, color: 3)
                c.display(s.t("irs050.end_date"), at: 329, color: 2)
                c.display(s.t("irs050.page"), at: 372, color: 2)
                if vatReport {
                    c.display(line4v, at: 501, color: 2); c.display(line5v, at: 601, color: 2)
                } else {
                    c.display(line4a, at: 501, color: 2); c.display(line5a, at: 601, color: 2)
                }
                c.display(s.t("irs050.c_exit"), at: wsLines, 1, color: 2)
                lin = 8
                while true {
                    weError = IRSubP.readNext(s, &post)
                    if weError == 3 || weError == 99 { break pages }
                    if vatReport {
                        if !vatArea() { continue }
                    } else {
                        if useCode != "  " && useCode != post.str("code") { continue }
                        auditLine()
                    }
                    c.display(audit ? line6a : line6v, at: lin, 1, color: 3)
                    lin += 1
                    if lin < acceptLines { continue }
                    lin = 8
                    wsReply = try c.accept(at: wsLines, 43, size: 1, color: 6)
                    if wsReply == "X" || wsReply == "x" || c.crtStatus == 2005 {
                        IRSubP.close(s)
                        return
                    }
                    wsReply = " "
                    continue pages
                }
            }
            // end-display1
            if !audit {
                if lin >= l21 {
                    lin = 8
                    wsReply = try c.accept(at: wsLines, 43, size: 1)
                    repeat {
                        c.display(Cobol.x("", 80), at: lin, 1)
                        lin += 1
                    } while lin < acceptLines
                    lin = 8
                    wsReply = " "
                    counter = (counter + 1) % 1000
                    pPage = counter
                    c.display(line3, at: 301, color: 3)
                }
                c.display(line7, at: l21, 1, color: 2)
                c.display(line8, at: l22, 1, color: 3)
                c.display(line7, at: acceptLines, 1, color: 2)
            }
            c.display(s.t("irs050.return_for_menu"), at: wsLines, 1, color: 2, eraseEOL: true)
            wsReply = try c.accept(at: wsLines, 23, size: 1)
            IRSubP.close(s)
        }

        // MARK: report-print section

        func headings() {
            counter = (counter + 1) % 1000
            pPage = counter
            if counter > 1 { printer?.writePage(Cobol.x(line1, 79)) } else { pw(line1, after: 1) }
            pw(line3, after: 1)
            if vatReport {
                pw(line4v, after: 1); pw(line5v, after: 1)
            } else {
                pw(line4a, after: 1); pw(line5a, after: 1)
            }
            lineCnt = 4
        }

        /// tran-total 段落 (use-code 指定時のみ合計を印字する: レガシーのまま)
        func tranTotal() {
            if useCode != "  " {
                let l8a = Cobol.x(s.t("report.irs050.tran_type"), 24) + pCodeA + Cobol.x(s.t("report.irs050.tran_total"), 18)
                    + Pic.edit("-(8)9.99", value: totalInNet, scale: 2) + "  " + Pic.edit("-(8)9.99", value: totalInVat, scale: 2)
                totalInNet = 0
                totalInVat = 0
                pw(line7a, after: 2)
                pw(l8a, after: 1)
                pw(line7a, after: 1)
                lineCnt += 4
            }
        }

        func reportPrint() throws {
            saveCode = "  "; useCode = "  "
            if audit { try askCode() }
            printer = IRS.Printer(s, "prt-1")
            counter = 0
            setReport()
            headings()
            while true {
                weError = IRSubP.readNext(s, &post)
                if weError == 3 || weError == 99 { break }
                if vatReport {
                    if vatAmount == 0 && postAmount == 0 { continue }
                    if !vatArea() { continue }
                } else {
                    if useCode != "  " && useCode != post.str("code") { continue }
                    if sortSequ == 1 && saveCode != post.str("code") && saveCode != "  " {
                        tranTotal()
                        headings()
                    }
                    auditLine()
                    saveCode = post.str("code")
                    totalInNet = s9(totalInNet + postAmount)
                    totalInVat = s9(totalInVat + vatAmount)
                }
                pw(audit ? line6a : line6v, after: 1)
                lineCnt += 1
                if lineCnt > 79 { headings() }
            }
            if lineCnt > 74 { headings() }
            if audit {
                tranTotal()
            } else {
                pw(line7, after: 2)
                pw(line8, after: 1)
                pw(line7, after: 1)
                lineCnt += 4
            }
            printer?.spool()
            printer = nil
            IRSubP.close(s)
        }

        // MARK: ledger-report section

        func printHeadings() {
            counter = (counter + 1) % 1000
            pPage = counter
            if counter > 1 { printer?.writePage(Cobol.x(line1, 79)) } else { pw(line1, after: 1) }
            pw(line3, after: 2)
            pw(line4l, after: 2)
            lineCnt = 5
        }

        func accountHeadings() {
            if lineCnt > 70 { printHeadings() }
            acMarker = 1
            pw(lineLedger, after: 2)
            pw("", after: 1)
            lineCnt += 3
        }

        func ledgerReport() throws {
            counter = 1; pPage = 1
            try IRSub1.open(s, .input)
            pReport = Cobol.x(s.t("report.irs050.ledgers"), 36)
            if outputReply == "P" {
                printer = IRS.Printer(s, "prt-1")
                pw(line1, after: 1)
                pw(line3, after: 2)
                pw(line4l, after: 2)
                lineCnt = 5
            }
            startLedgers: while true {
                c.display(" ", at: 101, eraseEOS: true)
                c.display(s.t("irs050.account_required"), at: 601, color: 2)
                targetAccount = Int64(IRS.num(try c.accept(at: 658, size: 5, kind: .numeric, color: 6)))
                if targetAccount == 0 {
                    while true {
                        if IRSub1.readNext(s, &nl) == 3 { break }
                        try getPostings()
                        if wsReply == "X" || c.crtStatus == 2005 { break }
                    }
                    break
                }
                nl.setInt("owning", targetAccount); nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &nl) == 2 { continue startLedgers }
                try getPostings()
                break
            }
            IRSub1.close(s)
            if outputReply == "P" {
                printer?.spool()
                printer = nil
            }
        }

        func ledgerMainDisplay() {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(line1, at: 101, color: 2)
            c.display(line3, at: 301, color: 3)
            c.display(s.t("irs050.end_date"), at: 329, color: 2)
            c.display(s.t("irs050.page"), at: 372, color: 2)
            c.display(lineLedger, at: 401, color: 3)
            c.display(s.t("irs050.account"), at: 401, color: 2)
            c.display(line4l, at: 501, color: 2)
            lin = 7
            counter = (counter + 1) % 1000
            pPage = counter
        }

        func totalCont() throws {
            c.display(Cobol.x("", 80), at: wsLines, 1)
            c.display(s.t("irs050.c_continue"), at: wsLines, 1, color: 2)
            wsReply = try c.accept(at: wsLines, 43, size: 1)
        }

        func getPostings() throws {
            let sub = nl.int("sub-nominal")
            ledgAccount = sub == 0 ? nl.int("owning") : sub
            checkAccount = ledgAccount
            ledgName = nl.str("name")
            if outputReply != "P" { ledgerMainDisplay() }
            weError = IRSubP.open(s, .input)
            totalDr = 0; totalCr = 0; wsAccountUsed = 0
            empty = "Y"
            defer {
                // total-jump
                acMarker = 0
                IRSubP.close(s)
            }
            while true {
                weError = IRSubP.readNext(s, &post)
                if weError == 3 { break }
                if weError == 99 { return }
                let dr = post.int("dr"), cr = post.int("cr"), side = post.str("vat-side")
                if checkAccount != dr && checkAccount != cr && checkAccount != def31 && checkAccount != def32 { continue }
                if doPrint && outputReply == "P" {
                    accountHeadings()
                    empty = " "
                }
                wsAccountUsed = 1
                pCodeL = post.str("code")
                pTranL = post.int("key")
                pDateL = post.str("date")
                let lg = post.raw("legend")
                pLegendL = Cobol.x(SJIS.decode(lg.prefix { $0 != 0 }), 32)
                if checkAccount == dr {
                    pContraL = cr; pDebitL = postAmount; pCreditL = 0
                    totalDr = s9(totalDr + postAmount)
                    if side == "CR" {
                        postAmount = s9(postAmount + vatAmount)
                        pDebitL = postAmount
                        totalDr = s9(totalDr + vatAmount)
                    }
                }
                if checkAccount == cr {
                    pContraL = dr; pCreditL = postAmount; pDebitL = 0
                    totalCr = s9(totalCr + postAmount)
                    if side == "DR" {
                        postAmount = s9(postAmount + vatAmount)
                        pCreditL = postAmount
                        totalCr = s9(totalCr + vatAmount)
                    }
                }
                if checkAccount == def31 {
                    getVat(31)
                    if vatAmount == 0 { vatCheck = 0; continue }
                }
                if checkAccount == def32 {
                    getVat(32)
                    if vatAmount == 0 { vatCheck = 0; continue }
                }
                if vatCheck == 9 { vatCheck = 0; continue }
                if outputReply == "P" {
                    pw(line6l, after: 1)
                    lineCnt += 1
                    if lineCnt > 74 {
                        printHeadings()
                        accountHeadings()
                    }
                    continue
                }
                c.display(line6l, at: lin, 1, color: 3)
                lin += 1
                if lin < acceptLines { continue }
                c.display(s.t("irs050.c_exit"), at: wsLines, 1, color: 2)
                wsReply = try c.accept(at: wsLines, 43, size: 1)
                if wsReply == "x" || wsReply == "X" || c.crtStatus == 2005 {
                    wsReply = "X"
                    return
                }
                ledgerMainDisplay()
            }
            // totals
            if nl.int("sub-nominal") == 0 { try subNominalSearch() }
            if wsAccountUsed == 0 { return }
            if doPrint && outputReply == "P" { return }
            let line8l = Cobol.x("", 58) + bwz("-(6)9.99", totalDr) + bwz("-(7)9.99", totalCr)
            // string nl-name delimited by "  " + "  Balance"
            let name = nl.str("name")
            var head = name
            if let r = name.range(of: "  ") { head = String(name[..<r.lowerBound]) }
            let balName = Cobol.x(head + s.t("report.irs050.balance"), 40)
            totalDr = s9(totalDr - totalCr)
            var d1 = Cobol.x("", 10), d2 = Cobol.x("", 10)
            var bDr: Int64 = 0, bCr: Int64 = 0
            if totalDr > 0 {
                bDr = totalDr
                d1 = "=========="
            } else {
                d2 = "=========="
                bCr = totalDr
            }
            let line9l = Cobol.x("", 18) + balName + bwz("-(6)9.99", bDr) + bwz("-(7)9.99", bCr)
            let line7l = Cobol.x("", 58) + d1 + " " + d2
            if outputReply == "P" {
                if lineCnt > 78 { printHeadings() }
                pw(line7m, after: 1)
                pw(line8l, after: 1)
                pw(line7m, after: 1)
                pw(line9l, after: 1)
                pw(line7l, after: 1)
                lineCnt += 5
                return
            }
            if lin > l17 {
                try totalCont()
                if c.crtStatus == 2005 {
                    wsReply = "X"
                    return
                }
                ledgerMainDisplay()
            }
            lin += 1
            c.display(line7m, at: lin, 1, color: 2)
            lin += 1
            c.display(line8l, at: lin, 1, color: 3)
            lin += 1
            c.display(line7m, at: lin, 1, color: 2)
            lin += 1
            c.display(line9l, at: lin, 1, color: 3)
            lin += 1
            c.display(line7l, at: lin, 1, color: 2)
            try totalCont()
        }

        /// get-input-vat (31) / get-output-vat (32)
        func getVat(_ n: Int64) {
            if vatAcDef != n {
                vatCheck = 9
                return
            }
            let side = post.str("vat-side")
            if side == "CR" {
                pContraL = post.int("dr"); pCreditL = vatAmount; pDebitL = 0
                totalCr = s9(totalCr + vatAmount)
            }
            if side == "DR" {
                pContraL = post.int("cr"); pDebitL = vatAmount; pCreditL = 0
                totalDr = s9(totalDr + vatAmount)
            }
        }

        // MARK: sub-nominal-search section

        func subNominalSearch() throws {
            pSpacerL = " "
            holdOwning = nl.int("owning")
            while true {
                if IRSub1.readNext(s, &nl) == 3 { break }
                if nl.int("owning") != holdOwning { break }
                let dr = nl.int("dr"), cr = nl.int("cr")
                if dr == cr { continue }
                if acMarker == 0 && outputReply == "P" { accountHeadings() }
                wsAccountUsed = 1
                pCodeL = "  "; pDateL = Cobol.x("", 8)
                pTranL = 0; pContraL = 0
                pLegendL = Cobol.x(Cobol.x(s.t("report.irs050.sub_nominal"), 26) + z5(nl.int("sub-nominal")), 32)
                if dr > cr {
                    totalDr = s9(totalDr + dr); totalDr = s9(totalDr - cr)
                    pDebitL = dr - cr; pCreditL = 0
                }
                if cr > dr {
                    totalCr = s9(totalCr + cr); totalCr = s9(totalCr - dr)
                    pCreditL = cr - dr; pDebitL = 0
                }
                empty = " "
                if outputReply == "P" {
                    pw(line6l, after: 1)
                    lineCnt += 1
                    if lineCnt > 79 {
                        printHeadings()
                        accountHeadings()
                    }
                    continue
                }
                c.display(line6l, at: lin, 1, color: 3)
                lin += 1
                if lin < l22 { continue }
                c.display(s.t("irs050.c_continue"), at: acceptLines, 1, color: 2)
                wsReply = try c.accept(at: acceptLines, 43, size: 1)
                if c.crtStatus == 2005 { break }
                lin = 7
                repeat {
                    c.display(Cobol.x("", 80), at: lin, 1)
                    lin += 1
                } while lin < acceptLines
                lin = 7
            }
            pSpacerL = "/"
            nl.setInt("owning", holdOwning); nl.setInt("sub-nominal", 0)
            _ = IRSub1.start(s, &nl, .equal)
        }
    }

    static func run(_ s: Session) throws { try Run(s).main() }
}
