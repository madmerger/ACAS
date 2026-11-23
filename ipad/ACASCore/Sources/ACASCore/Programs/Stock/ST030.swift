import Foundation

/// stock/st030.cbl — Stock Control Reports (在庫帳票)
enum ST030 {
    static let progName = "ST030 (3.01.22)"

    final class State {
        var menuReply = 0
        var reply = 0
        var partial = 0
        var stockFrom = Cobol.x("", 13), stockTo = Cobol.x("", 13)
        var abrevFrom = Cobol.x("", 7), abrevTo = Cobol.x("", 7)
        var lineCnt = 99, pageNos = 0
        var a = 0, b = 0
        var line0 = ""
        var reportName = ""
        var convDate = ""
        var hh = "  ", mm = "  "
        var currentPeriod = "", todatePeriod = "", litPeriod = ""
        // 帳票をまたいで残る作業域 (ca010 で ws-Reply = 1 のときは再計算されない)
        var totalAdd: Int64 = 0, totalDed: Int64 = 0, wipTotalAdd: Int64 = 0, wipTotalDed: Int64 = 0
    }

    private static func error(_ s: Session, _ key: String) {
        s.console.display(s.t(key), at: 23, 1, color: 4, highlight: true)
    }
    private static func blank(_ v: String) -> Bool { v.allSatisfy { $0 == " " } }
    private static func gt(_ a: String, _ b: String, _ size: Int) -> Bool {
        SJIS.encode(b, size: size).lexicographicallyPrecedes(SJIS.encode(a, size: size))
    }
    private static func bump(_ v: Int, _ n: Int) -> Int { (v + n) & 0xff }
    private static func ed(_ pic: String, _ v: Int64, _ scale: Int = 0) -> String { Pic.edit(pic, value: v, scale: scale) }

    // MARK: aa000-Core

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State()
        st.convDate = ST.convDate(s)
        let t = s.time
        if t.hour != 0 || t.minute != 0 || t.second != 0 { st.hh = Cobol.z(t.hour, 2); st.mm = Cobol.z(t.minute, 2) }
        switch s.sys.str("stk-period-cur") {
        case "Q": st.currentPeriod = s.l10n.raw("st030.period.quarter"); st.litPeriod = s.l10n.raw("st030.period.quarter")
        case "W": st.currentPeriod = s.l10n.raw("st030.period.week"); st.litPeriod = s.l10n.raw("st030.period.week_lit")
        default: st.currentPeriod = s.l10n.raw("st030.period.month"); st.litPeriod = s.l10n.raw("st030.period.month_lit")
        }
        switch s.sys.str("stk-period-dat") {
        case "M": st.todatePeriod = s.l10n.raw("st030.todate.month")
        case "Q": st.todatePeriod = s.l10n.raw("st030.todate.quarter")
        default: st.todatePeriod = s.l10n.raw("st030.todate.year")
        }
        st.currentPeriod = Cobol.x(st.currentPeriod, 10)
        st.todatePeriod = Cobol.x(st.todatePeriod, 16)
        if ST.fileStatus(s, 11) != 1 {
            error(s, "st030.st300")
            try ST.maps99(s, 45)
            return
        }
        let probe = ST.stockFile(s)
        if probe.open() != "00" {
            error(s, "st030.st301")
            c.display(probe.status, at: 23, 28, color: 2, highlight: true)
            try ST.maps99(s, 45)
            return
        }
        st.menuReply = 0
        probe.close()

        var skipHeadings = false
        while true {
            if !skipHeadings { displayHeadings(s, st) }
            skipHeadings = false
            // aa020-Display-Heads
            c.display(progName, at: 1, 1, color: 2, eraseEOS: true)
            c.display(Cobol.x(st.reportName, 28), at: 1, st.menuReply == 0 ? 27 : 30, color: 2)
            c.display(st.convDate, at: 1, 71, color: 2)
            // aa030-DH-End
            let month = String(Array(Cobol.x(s.toDay, 10))[3..<5])
            if !month.allSatisfy({ $0.isASCII && $0.isNumber }) || !(1...12).contains(Int(month) ?? 0) {
                error(s, "st030.st313")
                c.display(month, at: 23, 25, color: 2, highlight: true)
                c.display(Cobol.x(s.toDay, 10), at: 23, 28, color: 2, highlight: true)
                try ST.maps99(s, 45)
                return
            }
            // aa100-Main-Menu
            c.display(s.t("st030.menu.select"), at: 4, 1, color: 2, eraseEOS: true)
            c.display(s.t("st030.menu.1"), at: 6, 4, color: 2)
            c.display(s.t("st030.menu.2"), at: 7, 4, color: 2)
            c.display(s.t("st030.menu.3"), at: 8, 4, color: 2)
            c.display(s.t("st030.menu.4"), at: 9, 4, color: 2)
            c.display(s.t("st030.menu.5"), at: 10, 4, color: 2)
            c.display(s.t("st030.menu.9"), at: 12, 4, color: 2)
            // aa110-Accept-Loop
            while true {
                st.menuReply = 0
                st.menuReply = Int(ST.digits(try c.accept(at: 4, 43, size: 1, kind: .numeric, initial: "0", options: [.auto, .update], color: 6)))
                if st.menuReply == 9 { return }
                displayHeadings(s, st)
                try reportSelection(s, st)
                if st.reply == 9 { skipHeadings = true; break }
                if st.menuReply == 0 || st.menuReply > 5 { continue }
                c.display(" ", at: 23, 1, eraseEOL: true)
                let f = ST.stockFile(s)
                _ = f.open()
                let p = ST.Printer(s)
                switch st.menuReply {
                case 1: try valuation(s, st, f, p)
                case 2: try activity(s, st, f, p)
                case 3: try reorder(s, st, f, p)
                case 4: try history(s, st, f, p)
                default: try stockLists(s, st, f, p)
                }
                p.close(); f.close()
                if st.pageNos != 0 { p.spool() }
                st.menuReply = 0
                break
            }
        }
    }

    /// aa010-Display-Headings
    private static func displayHeadings(_ s: Session, _ st: State) {
        st.pageNos = 0
        st.lineCnt = 99
        st.reportName = s.l10n.raw((1...5).contains(st.menuReply) ? "st030.report_name.\(st.menuReply)" : "st030.report_name.menu")
    }

    // MARK: zz050-Report-Selection

    private static func screenHead(_ s: Session, _ st: State) {
        let c = s.console
        c.eraseScreen()
        c.display(progName, at: 1, 1, color: 2)
        c.display(Cobol.x(st.reportName, 28), at: 1, 26, color: 2)
        c.display(st.convDate, at: 1, 71, color: 2)
        c.display(s.t("st030.attr.title"), at: 3, 32, color: 2)
    }

    private static func acceptReply(_ s: Session, _ st: State) throws {
        let c = s.console
        c.display(s.t("st030.attr.select"), at: 5, 1, color: 2)
        c.display("]", at: 5, 36, color: 2)
        let fld = [ScreenField(line: 5, col: 35, size: 1, kind: .numeric, value: String(st.reply), color: 2)]
        try c.acceptScreen(fld)
        st.reply = Int(ST.digits(fld[0].value))
    }

    private static func reportSelection(_ s: Session, _ st: State) throws {
        let c = s.console
        var target = 0   // 0 = 先頭, 1 = display-01, 3 = display-03
        selection: while true {
            if target == 0 {
                st.stockFrom = Cobol.x("", 13); st.stockTo = Cobol.x("", 13)
                st.abrevFrom = Cobol.x("", 7); st.abrevTo = Cobol.x("", 7)
                st.partial = 0; st.reply = 0
                if st.menuReply == 1 || st.menuReply == 4 || st.menuReply == 5 { target = 3; continue }
                if st.menuReply == 3 { target = 1; continue }
                // display-02 (Activity)
                screenHead(s, st)
                c.display(s.t("st030.act.1"), at: 7, 10, color: 2)
                c.display(s.t("st030.act.2"), at: 8, 10, color: 2)
                c.display(s.t("st030.act.3"), at: 9, 10, color: 2)
                c.display(st.currentPeriod, at: 9, 40, color: 2)
                c.display(s.t("st030.act.4"), at: 10, 10, color: 2)
                c.display(st.todatePeriod, at: 10, 32, color: 2)
                c.display(s.t("st030.act.5"), at: 11, 10, color: 2)
                c.display(st.currentPeriod, at: 11, 49, color: 2)
                c.display(s.t("st030.act.6"), at: 12, 10, color: 2)
                c.display(st.todatePeriod, at: 12, 41, color: 2)
                c.display(s.t("st030.act.9"), at: 14, 10, color: 2)
                try acceptReply(s, st)
                if st.reply == 9 { return }
                if st.reply < 1 || st.reply > 6 { continue }
                if st.reply == 2 || st.reply == 5 || st.reply == 6 { target = 3; continue }
                return
            }
            if target == 1 {
                // display-01 (ReOrder)
                screenHead(s, st)
                for (i, line) in [(1, 7), (2, 8), (3, 9), (4, 10), (5, 11), (6, 12), (7, 13), (8, 14), (9, 16)] {
                    c.display(s.t("st030.reord.\(i)"), at: line, 10, color: 2)
                }
                try acceptReply(s, st)
                if st.reply == 9 { return }
                if st.reply < 1 { continue }
                if [2, 4, 6, 8].contains(st.reply) { target = 3; continue }
                return
            }
            // display-03 (範囲)
            screenHead(s, st)
            c.display(s.t("st030.range.leave_blank"), at: 5, 24, color: 2, highlight: true)
            c.display(s.t("st030.range.not_both"), at: 6, 17, color: 2, highlight: true)
            c.display(s.t("st030.range.from_stock"), at: 8, 4, color: 2)
            c.display("]", at: 8, 38, color: 2)
            c.display(s.t("st030.range.to_stock"), at: 9, 4, color: 2)
            c.display("]", at: 9, 38, color: 2)
            c.display(s.t("st030.range.or"), at: 10, 14, color: 2, highlight: true)
            c.display(s.t("st030.range.from_abrev"), at: 11, 4, color: 2)
            c.display("]", at: 11, 32, color: 2)
            c.display(s.t("st030.range.to_abrev"), at: 12, 4, color: 2)
            c.display("]", at: 12, 32, color: 2)
            for l in [8, 9, 11, 12] { c.display(s.t("st030.range.hint"), at: l, 41, color: 2) }
            let flds = [
                ScreenField(line: 8, col: 25, size: 13, value: st.stockFrom, color: 2),
                ScreenField(line: 9, col: 25, size: 13, value: st.stockTo, color: 2),
                ScreenField(line: 11, col: 25, size: 7, value: st.abrevFrom, color: 2),
                ScreenField(line: 12, col: 25, size: 7, value: st.abrevTo, color: 2),
            ]
            try c.acceptScreen(flds)
            st.stockFrom = Cobol.x(Cobol.upper(flds[0].value), 13)
            st.stockTo = Cobol.x(Cobol.upper(flds[1].value), 13)
            st.abrevFrom = Cobol.x(Cobol.upper(flds[2].value), 7)
            st.abrevTo = Cobol.x(Cobol.upper(flds[3].value), 7)
            let sf = !blank(st.stockFrom), stt = !blank(st.stockTo), af = !blank(st.abrevFrom), at = !blank(st.abrevTo)
            if (sf && af) || (stt && at) || (sf && at) || (stt && af) {
                error(s, "st030.st304")
                try ST.maps99(s, 15)
                continue selection
            }
            if sf && stt && gt(st.stockFrom, st.stockTo, 13) {
                error(s, "st030.st307")
                try ST.maps99(s, 15)
                continue selection
            }
            if af && at && gt(st.abrevFrom, st.abrevTo, 7) {
                error(s, "st030.st308")
                try ST.maps99(s, 15)
                continue selection
            }
            st.partial = (sf || stt || af || at) ? 1 : 0
            return
        }
    }

    // MARK: ファイル位置付け (各帳票の先頭に共通の START 群)

    /// 戻り値 nil = START が invalid key (エラー表示済み)。READ NEXT 相当のクロージャを返す。
    private static func position(_ s: Session, _ st: State, _ f: IndexedFile) throws -> (() -> Record?)? {
        if !blank(st.abrevTo) {
            var t = Array(st.abrevTo)
            var a = 7
            while !(a < 2 || t[a - 1] != " ") { t[a - 1] = "z"; a -= 1 }
            st.a = a
            st.abrevTo = String(t)
        }
        var next: () -> Record? = { f.readNext() }
        if !blank(st.stockFrom) {
            if !f.start(notLessThan: ST.key(st.stockFrom)) {
                error(s, "st030.st306")
                try ST.maps99(s, 15)
                return nil
            }
            next = { f.readNext() }
        }
        func startAbrev(_ key: String) -> ST.AltCursor? {
            let k = SJIS.encode(key, size: 7)
            let recs = ST.sorted(f, by: "stock-abrev-key").filter { !$0.raw("stock-abrev-key").lexicographicallyPrecedes(k) }
            return recs.isEmpty ? nil : ST.AltCursor(recs)
        }
        if !blank(st.abrevFrom) {
            var k = Array(st.abrevFrom)
            if k[6] == " " { k[6] = "0" }
            guard let cur = startAbrev(String(k)) else {
                error(s, "st030.st305")
                try ST.maps99(s, 15)
                return nil
            }
            next = { cur.next() }
        }
        if st.partial == 0 {
            let cur = startAbrev("0000000") ?? ST.AltCursor([])
            next = { cur.next() }
        }
        return next
    }

    /// 範囲判定: 0 = 対象, 1 = 読み飛ばし, 2 = 終了
    private static func below(_ st: State, _ r: Record) -> Bool {
        if !blank(st.stockFrom) && gt(st.stockFrom, r.str("stock-key"), 13) { return true }
        if !blank(st.abrevFrom) && gt(st.abrevFrom, r.str("stock-abrev-key"), 7) { return true }
        return false
    }
    private static func above(_ st: State, _ r: Record) -> Bool {
        if !blank(st.stockTo) && gt(r.str("stock-key"), st.stockTo, 13) { return true }
        if !blank(st.abrevTo) && gt(r.str("stock-abrev-key"), st.abrevTo, 7) { return true }
        return false
    }

    /// 各帳票末尾の「範囲内に該当なし」判定。true = エラー表示して終了
    private static func noneInRange(_ s: Session, _ st: State) -> Bool {
        guard st.pageNos == 0 else { return false }
        if !blank(st.stockFrom) || !blank(st.stockTo) { error(s, "st030.st302"); return true }
        if !blank(st.abrevFrom) || !blank(st.abrevTo) { error(s, "st030.st303"); return true }
        return false
    }

    // MARK: 見出し (zz002 / zz004)

    private static func string0(_ st: State, _ text: String) {
        st.line0 += text
        st.b += CellWidth.of(text)
    }

    /// zz004-String-Range
    private static func stringRange(_ s: Session, _ st: State) {
        string0(st, s.l10n.raw("report.st030.range_from"))
        if !blank(st.stockFrom) || !blank(st.stockTo) {
            string0(st, blank(st.stockFrom) ? s.l10n.raw("report.st030.start") : st.stockFrom)
            string0(st, s.l10n.raw("report.st030.through"))
            string0(st, blank(st.stockTo) ? s.l10n.raw("report.st030.end") : st.stockTo)
        } else {
            string0(st, blank(st.abrevFrom) ? s.l10n.raw("report.st030.start") : Cobol.rtrim(st.abrevFrom))
            string0(st, s.l10n.raw("report.st030.through"))
            string0(st, blank(st.abrevTo) ? s.l10n.raw("report.st030.end") : st.abrevTo)
        }
        st.a = ((132 - st.b + 2) / 2) & 0xff
    }

    private static func rangeOr(_ s: Session, _ st: State, _ key: String) {
        if st.partial == 1 {
            stringRange(s, st)
        } else {
            string0(st, s.l10n.raw(key))
            st.a = ((132 - st.b + 2) / 2) & 0xff
        }
    }

    /// zz002-Print-Head-Top
    private static func headTop(_ s: Session, _ st: State, _ p: ST.Printer) {
        st.pageNos = bump(st.pageNos, 1)
        let line11 = Cobol.x(progName, 16) + Cobol.x("", 39) + Cobol.x(st.reportName, 42) + Cobol.x("", 27)
            + Cobol.x(s.l10n.raw("report.st030.page"), 5) + ed("zz9", Int64(st.pageNos))
        var line12 = Cobol.x(s.sys.str("usera"), 40) + Cobol.x("", 76) + Cobol.x(st.convDate, 10) + " " + st.hh + ":" + st.mm
        if st.b > 1 {
            // move Line-0 (1:b) to Print-Record (a:b)
            let seg = Cobol.x(st.line0, min(st.b, 100))
            let start = max(st.a, 1) - 1
            let head = Cobol.x(line12, start)
            let rest = Cobol.x(line12, 132).dropFirst(head.count + seg.count)
            line12 = Cobol.x(head + seg + String(rest), 132)
        }
        if st.pageNos != 1 {
            p.afterPage(line11)
            p.after(1, line12)
            p.after(1, "")
        } else {
            p.before(1, line11)
            p.before(1, line12)
        }
        st.lineCnt = 6
        st.line0 = ""
    }

    private static func heads(_ s: Session, _ st: State, _ p: ST.Printer, prefix: () -> Void, allKey: String, lines: () -> [String]) {
        guard st.lineCnt > Int(s.sys.int("page-lines")) else { return }
        st.b = 1
        st.line0 = ""
        prefix()
        rangeOr(s, st, allKey)
        headTop(s, st, p)
        for l in lines() { p.after(1, l) }
        p.after(1, "")
    }

    // MARK: ba000-Process-Valuations

    private static func valuation(_ s: Session, _ st: State, _ f: IndexedFile, _ p: ST.Printer) throws {
        guard let next = try position(s, st, f) else { return }
        let manu = s.sys.int("stk-manu-used") == 1
        var total: Int64 = 0
        func printHeads() {
            heads(s, st, p, prefix: {}, allKey: "report.st030.all_items") {
                let wip = manu ? s.l10n.raw("report.st030.l13_wip") : "", qty = manu ? s.l10n.raw("report.st030.l14_qty") : ""
                return [Cobol.x(s.l10n.raw("report.st030.line_13a"), 96) + Cobol.x(wip, 3) + Cobol.x(s.l10n.raw("report.st030.line_13b"), 24),
                        Cobol.x(s.l10n.raw("report.st030.line_14a"), 96) + Cobol.x(qty, 3) + Cobol.x(s.l10n.raw("report.st030.line_14b"), 24)]
            }
        }
        while let r = next() {
            if below(st, r) { continue }
            if above(st, r) { break }
            printHeads()
            var ave = Array(ed("zzzzz,zz9.9999", r.int("stock-cost"), 4))
            if String(ave[12...13]) == "00" { ave[12] = " "; ave[13] = " " }
            var line = Cobol.x(r.str("stock-abrev-key"), 9) + Cobol.x(r.str("stock-key"), 15) + Cobol.x(r.str("stock-desc"), 33)
            line += String(ave) + ed("zzzzz,zz9.99", r.int("stock-last-actual-cost"), 2)
            line += ed("z(7)9", abs(r.int("stock-held")))
            line += manu ? ed("z(7)9", abs(r.int("stock-work-in-progress"))) : Cobol.x("", 8)
            line += ed("zzz,zzz,zz9.99", r.int("stock-value"), 2) + ed("zzzzz,zz9.99", r.int("stock-retail"), 2)
            p.after(1, line)
            total = Cobol.truncate(total + r.int("stock-value"), digits: 11)
            st.lineCnt = bump(st.lineCnt, 1)
        }
        if noneInRange(s, st) { return }
        if st.lineCnt > Int(s.sys.int("page-lines")) - 4 {
            st.lineCnt = 99
            printHeads()
        }
        p.after(2, Cobol.x("", 99) + String(repeating: "-", count: 14))
        p.after(1, Cobol.x("", 86) + Cobol.x(s.l10n.raw("report.st030.total_value"), 13) + ed("zzz,zzz,zz9.99", abs(total), 2))
        p.after(1, Cobol.x("", 99) + String(repeating: "=", count: 14))
    }

    // MARK: ca000-Process-Activity

    private static func activity(_ s: Session, _ st: State, _ f: IndexedFile, _ p: ST.Printer) throws {
        guard let next = try position(s, st, f) else { return }
        let manu = s.sys.int("stk-manu-used") == 1
        let averaging = s.sys.int("stk-averaging") == 1
        func printHeads() {
            heads(s, st, p, prefix: {
                if st.reply == 1 || st.reply == 2 { string0(st, s.l10n.raw("report.st030.all")) }
                if st.reply == 3 || st.reply == 5 {
                    // ws-Current-Period delimited by " "
                    let word = st.currentPeriod.split(separator: " ", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    string0(st, s.l10n.raw("report.st030.active_current") + word)
                }
                if st.reply == 4 || st.reply == 6 {
                    // ws-Todate-Period delimited by "  "
                    let word = st.todatePeriod.components(separatedBy: "  ").first ?? ""
                    string0(st, s.l10n.raw("report.st030.active_in") + word + s.l10n.raw("report.st030.to_date"))
                }
                st.b += 1
                st.line0 += " "
            }, allKey: "report.st030.items") {
                let cur = s.sys.str("stk-period-cur"), dat = s.sys.str("stk-period-dat")
                let litCur = s.l10n.raw(cur == "Q" ? "report.st030.cur_quarter" : cur == "W" ? "report.st030.cur_week" : "report.st030.cur_month")
                let litYTD = s.l10n.raw(dat == "Q" ? "report.st030.quarter_to_date" : "report.st030.year_to_date")
                return [Cobol.x(s.l10n.raw("report.st030.line_23"), 72) + Cobol.x(averaging ? s.l10n.raw("report.st030.l23_average") : s.l10n.raw("report.st030.l23_unit"), 13)
                            + Cobol.x(averaging ? s.l10n.raw("report.st030.l23_stock") : "", 9) + Cobol.x(litCur, 19) + Cobol.x(litYTD, 19),
                        Cobol.x(s.l10n.raw("report.st030.line_24a"), 86) + Cobol.x(averaging ? s.l10n.raw("report.st030.l24_value") : "", 11)
                            + Cobol.x(s.l10n.raw("report.st030.line_24b"), 35)]
            }
        }
        while let r = next() {
            if st.reply != 1 {
                if below(st, r) { continue }
                let adds = r.int("stock-adds"), deds = r.int("stock-deducts"), wa = r.int("stock-wip-adds"), wd = r.int("stock-wip-deds")
                if (st.reply == 3 || st.reply == 5) && adds == 0 && deds == 0 && wa == 0 && wd == 0 { continue }
                st.totalAdd = 0; st.totalDed = 0; st.wipTotalAdd = 0; st.wipTotalDed = 0
                for a in 1...12 {
                    st.totalAdd += r.int("stock-td-adds-\(a)")
                    st.totalDed += r.int("stock-td-deds-\(a)")
                    st.wipTotalAdd += r.int("stock-td-wip-adds-\(a)")
                    st.wipTotalDed += r.int("stock-td-wip-deds-\(a)")
                }
                if (st.reply == 4 || st.reply == 6) && st.totalAdd == 0 && st.totalDed == 0 && st.wipTotalAdd == 0 && st.wipTotalDed == 0 { continue }
                if above(st, r) { break }
            }
            printHeads()
            var line = Cobol.x(r.str("stock-abrev-key"), 8) + Cobol.x(r.str("stock-key"), 14) + Cobol.x(r.str("stock-desc"), 33)
            line += ed("zzz,zz9", abs(r.int("stock-held"))) + ed("zzz,zz9.99", r.int("stock-retail"), 2)
            if averaging {
                line += ed("zzz,zz9.99", r.int("stock-cost"), 4) + ed("zzzzz,zz9.99", r.int("stock-value"), 2)
            } else {
                line += ed("zzz,zz9.99", r.int("stock-last-actual-cost"), 2) + Cobol.x("", 12)
            }
            func tail(_ add: Int64, _ ded: Int64, _ tAdd: Int64, _ tDed: Int64) -> String {
                ed("z(5)9", abs(add)) + ed("z(5)9", abs(ded)) + ed("z(5)9-", add - ded)
                    + ed("z(5)9", abs(tAdd)) + ed("z(5)9", abs(tDed)) + ed("z(5)9-", tAdd - tDed)
            }
            line += tail(r.int("stock-adds"), r.int("stock-deducts"), st.totalAdd, st.totalDed)
            p.after(1, line)
            st.lineCnt = bump(st.lineCnt, 1)
            let wip = r.int("stock-work-in-progress"), wa = r.int("stock-wip-adds"), wd = r.int("stock-wip-deds")
            if manu && (wip != 0 || wa != 0 || wd != 0 || st.wipTotalAdd != 0 || st.wipTotalDed != 0) {
                var w = Cobol.x("", 50) + Cobol.x(s.l10n.raw("report.st030.wip_lit"), 5) + ed("zzz,zz9", abs(wip)) + Cobol.x("", 15)
                w += Cobol.x(s.l10n.raw("report.st030.work_in_progress"), 17)
                w += tail(wa, wd, st.wipTotalAdd, st.wipTotalDed)
                p.after(1, w)
                st.lineCnt = bump(st.lineCnt, 1)
            }
        }
        _ = noneInRange(s, st)
    }

    // MARK: da000-Process-ReOrder

    private static func reorder(_ s: Session, _ st: State, _ f: IndexedFile, _ p: ST.Printer) throws {
        guard let next = try position(s, st, f) else { return }
        let manu = s.sys.int("stk-manu-used") == 1
        let averaging = s.sys.int("stk-averaging") == 1
        func printHeads() {
            heads(s, st, p, prefix: {
                if st.reply == 1 || st.reply == 2 { string0(st, s.l10n.raw("report.st030.all_sp")) }
                if st.reply == 3 || st.reply == 4 { string0(st, s.l10n.raw("report.st030.understocked")) }
                if st.reply == 5 || st.reply == 6 { string0(st, s.l10n.raw("report.st030.not_in_stock")) }
                if st.reply == 7 || st.reply == 8 { string0(st, s.l10n.raw("report.st030.on_order")) }
            }, allKey: "report.st030.items") {
                [s.l10n.raw("report.st030.line_33"), s.l10n.raw("report.st030.line_34")]
            }
        }
        while let r = next() {
            let held = r.int("stock-held"), pnt = r.int("stock-reorder-pnt")
            let service = r.str("stock-services-flag") == "Y"
            if st.reply != 1 {
                if service { continue }
                if below(st, r) { continue }
                if st.reply != 2 {
                    if (st.reply == 3 || st.reply == 4) && pnt < held { continue }
                    if (st.reply == 5 || st.reply == 6) && held != 0 { continue }
                    if (st.reply == 7 || st.reply == 8) && r.int("stock-on-order") == 0 && r.int("stock-back-ordered") == 0
                        && r.int("stock-order-date") == 0 && r.int("stock-order-due") == 0 { continue }
                }
                if above(st, r) { break }
            }
            printHeads()
            var flag = held < pnt ? "U" : (held == 0 ? "0" : " ")
            if service { flag = " " }
            var line = Cobol.x(r.str("stock-abrev-key"), 8) + Cobol.x(r.str("stock-key"), 14) + flag + "  " + Cobol.x(r.str("stock-desc"), 33)
            line += Cobol.x(r.str("stock-supplier-p1"), 7)
            line += ed("z(5)9", abs(held)) + ed("z(5)9", abs(pnt)) + ed("z(5)9", abs(r.int("stock-std-reorder")))
            line += averaging ? ed("z(5)9.99", r.int("stock-cost"), 4) : ed("z(5)9.99", r.int("stock-last-actual-cost"), 2)
            line += ed("z(5)9b", abs(r.int("stock-on-order")))
            line += Cobol.x(r.int("stock-order-date") != 0 ? ST.convertDate(s, r.int("stock-order-date")) : "", 11)
            line += Cobol.x(r.int("stock-order-due") != 0 ? ST.convertDate(s, r.int("stock-order-due")) : "", 10)
            line += ed("z(5)9", abs(r.int("stock-back-ordered")))
            line += manu ? ed("z(6)", abs(r.int("stock-work-in-progress"))) : Cobol.x("", 6)
            p.after(1, line)
            st.lineCnt = bump(st.lineCnt, 1)
        }
        _ = noneInRange(s, st)
    }

    // MARK: ea000-Process-Stock-Lists

    private static func stockLists(_ s: Session, _ st: State, _ f: IndexedFile, _ p: ST.Printer) throws {
        guard let next = try position(s, st, f) else { return }
        var recCnt = 0
        func printHeads() {
            heads(s, st, p, prefix: {}, allKey: "report.st030.all_items") {
                [s.l10n.raw("report.st010.line_3"), s.l10n.raw("report.st010.line_4")]
            }
        }
        while let r = next() {
            if below(st, r) { continue }
            if above(st, r) { break }
            printHeads()
            recCnt += 1
            let service = r.str("stock-services-flag") == "Y"
            var cost = Array(ed("z(6)9.9999", r.int("stock-cost"), 4))
            if String(cost[10...11]) == "00" { cost[10] = " "; cost[11] = " " }
            func qty(_ name: String) -> String { service ? Cobol.x("", 7) : ed("z(6)9", abs(r.int(name))) }
            var line45 = Cobol.x(r.str("stock-abrev-key"), 8) + Cobol.x(r.str("stock-key"), 14) + Cobol.x(r.str("stock-supplier-p1"), 8)
            line45 += Cobol.x(r.str("stock-location"), 11) + ed("z(6)9.99", r.int("stock-retail"), 2) + String(cost)
            line45 += service ? Cobol.x("", 12) : ed("zzzzz,zz9.99", r.int("stock-value"), 2)
            line45 += qty("stock-held") + qty("stock-reorder-pnt") + qty("stock-std-reorder") + " "
            line45 += Cobol.x(r.int("stock-order-date") != 0 ? ST.convertDate(s, r.int("stock-order-date")) : "", 11)
            line45 += Cobol.x(r.int("stock-order-due") != 0 ? ST.convertDate(s, r.int("stock-order-due")) : "", 10)
            line45 += qty("stock-on-order") + qty("stock-back-ordered")
            var vars = ""
            let p2 = r.str("stock-supplier-p2"), p3 = r.str("stock-supplier-p3")
            if !blank(p2) || !blank(p3) {
                vars += s.l10n.raw("report.st010.secondary")
                if !blank(p2) { vars += " 1: " + Cobol.x(p2, 7) }
                if !blank(p3) { vars += " 2: " + Cobol.x(p3, 7) }
                vars += "  "
            }
            let sa = Array(Cobol.x(r.str("stock-sa-code"), 3)), pa = Array(Cobol.x(r.str("stock-pa-code"), 3))
            if String(sa) != "   " { vars += s.l10n.raw("report.st010.sa_code") + String(sa[1...2]) + "  " }
            if String(pa) != "   " { vars += s.l10n.raw("report.st010.pa_code") + String(pa[1...2]) }
            if r.int("stock-pre-sales") != 0 {
                vars += s.l10n.raw("report.st010.pre_sales") + ed("z(6)", abs(r.int("stock-pre-sales")))
            }
            let line46 = Cobol.x("", 5) + Cobol.x(s.l10n.raw("report.st010.description"), 13) + Cobol.x(r.str("stock-desc"), 32) + Cobol.x("", 5) + Cobol.x(vars, 77)
            if st.lineCnt > 6 { p.after(1, String(repeating: "-", count: 132)) }
            p.after(1, line45)
            p.after(1, line46)
            st.lineCnt = bump(st.lineCnt, 2)
            if !service && (r.int("stock-construct-bundle") != 0 || r.int("stock-under-construction") != 0
                || r.int("stock-work-in-progress") != 0 || !blank(r.str("stock-construct-item"))) {
                func z6(_ n: String) -> String { ed("z(6)", abs(r.int(n))) }
                p.after(1, s.l10n.raw("report.st010.bundle") + z6("stock-construct-bundle") + s.l10n.raw("report.st010.wip") + z6("stock-work-in-progress")
                    + s.l10n.raw("report.st010.under_construction") + z6("stock-under-construction")
                    + s.l10n.raw("report.st010.for_item") + Cobol.x(r.str("stock-construct-item"), 13))
                st.lineCnt = bump(st.lineCnt, 1)
            }
            if service {
                p.after(1, s.l10n.raw("report.st010.services_only"))
                st.lineCnt = bump(st.lineCnt, 1)
            }
        }
        if noneInRange(s, st) { return }
        if st.lineCnt > Int(s.sys.int("page-lines")) - 3 {
            st.lineCnt = bump(st.lineCnt, 60)
            printHeads()
        }
        let total = ed("zzz,zzz,zz9", Int64(recCnt)).drop(while: { $0 == " " })
        p.after(3, s.l10n.raw("report.st030.total") + total)
    }

    // MARK: fa000-Process-History

    private static func history(_ s: Session, _ st: State, _ f: IndexedFile, _ p: ST.Printer) throws {
        guard let next = try position(s, st, f) else { return }
        let manu = s.sys.int("stk-manu-used") == 1
        var recCnt = 0
        var anyWip = false
        func printHeads() {
            heads(s, st, p, prefix: {}, allKey: "report.st030.all_items") {
                [s.l10n.raw("report.st030.line_53"), Cobol.x(s.l10n.raw("report.st030.line_54"), 41) + Cobol.x(st.litPeriod, 7)]
            }
        }
        func e7(_ v: Int64) -> String { ed("-(6)9", v) }
        while let r = next() {
            if below(st, r) { continue }
            if above(st, r) { break }
            recCnt += 1
            printHeads()
            var line = Cobol.x(r.str("stock-abrev-key"), 8) + Cobol.x(r.str("stock-key"), 14) + Cobol.x(r.str("stock-desc"), 18) + " "
            line += e7(r.int("stock-adds") + r.int("stock-deducts"))
            for a in 1...12 { line += e7(r.int("stock-td-adds-\(a)") + r.int("stock-td-deds-\(a)")) }
            p.after(1, line)
            st.lineCnt = bump(st.lineCnt, 1)
            if manu {
                var b = r.int("stock-wip-adds") != 0 || r.int("stock-wip-deds") != 0
                for a in 1...12 where r.int("stock-td-wip-adds-\(a)") != 0 || r.int("stock-td-wip-deds-\(a)") != 0 { b = true }
                if b {
                    var w = Cobol.x("", 36) + Cobol.x(s.l10n.raw("report.st030.wip_lit"), 4) + " "
                    w += e7(r.int("stock-wip-adds") + r.int("stock-wip-deds"))
                    for a in 1...12 { w += e7(r.int("stock-td-wip-adds-\(a)") + r.int("stock-td-wip-deds-\(a)")) }
                    p.after(1, w)
                    st.lineCnt = bump(st.lineCnt, 1)
                    anyWip = true
                }
            }
        }
        if noneInRange(s, st) { return }
        if st.lineCnt > Int(s.sys.int("page-lines")) - 5 {
            st.lineCnt = bump(st.lineCnt, 60)
            printHeads()
        }
        let total = ed("zzz,zzz,zz9", Int64(recCnt)).drop(while: { $0 == " " })
        p.after(3, s.l10n.raw("report.st030.total") + total)
        if manu && !anyWip { p.after(2, s.l10n.raw("report.st030.no_wip_data")) }
    }
}
