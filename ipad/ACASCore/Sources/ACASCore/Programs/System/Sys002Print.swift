import Foundation

/// sys002.cbl print-params / sl-print: システム設定一覧 (prt-1, 132 桁)
enum Sys002Print {
    /// 固定長の英数字項目 (セル単位。全角文字は 2 セル目に印を置く)
    struct Fld {
        static let tail: Character = "\u{0}"
        var c: [Character]
        init(_ size: Int) { c = [Character](repeating: " ", count: size) }
        static func cells(_ text: String) -> [Character] {
            var out: [Character] = []
            for ch in text {
                out.append(ch)
                if CellWidth.of(ch) == 2 { out.append(tail) }
            }
            return out
        }
        private mutating func setCell(_ i: Int, _ ch: Character) {
            // 全角文字の片側だけを上書きする場合は残りの半分を空白にする
            if c[i] == Self.tail, i > 0 { c[i - 1] = " " }
            if i + 1 < c.count, c[i + 1] == Self.tail, ch != Self.tail { c[i + 1] = " " }
            c[i] = ch
        }
        /// MOVE (左詰め・空白埋め)
        mutating func move(_ text: String) {
            let src = Self.cells(Cobol.x(text, c.count))
            c = Array(src.prefix(c.count)) + [Character](repeating: " ", count: max(0, c.count - src.count))
        }
        mutating func clear() { c = [Character](repeating: " ", count: c.count) }
        /// STRING ... INTO ... WITH POINTER (受け側は空白埋めしない)
        mutating func string(_ ptr: inout Int, _ text: String) {
            for ch in Self.cells(text) {
                guard ptr >= 1, ptr <= c.count else { return }
                setCell(ptr - 1, ch)
                ptr += 1
            }
        }
        /// 部分参照 (pos:len) への MOVE
        mutating func move(_ text: String, at pos: Int, len: Int) {
            var p = pos
            string(&p, Cobol.x(text, len))
        }
        var text: String { String(c.filter { $0 != Self.tail }) }
        var isSpaces: Bool { c.allSatisfy { $0 == " " } }
    }

    final class Ctx {
        let s: Session
        let st: Sys002.State
        let path: String
        var name = Fld(17), d1 = Fld(43), d2 = Fld(50)
        private var pending = false
        init(_ s: Session, _ st: Sys002.State) {
            self.s = s; self.st = st
            path = s.ledgers + "prt-1"
            s.store.writeRaw(path, [])
        }
        var sys: Record { st.sys }
        func t(_ key: String) -> String { Sys002.t(s, "r." + key) }
        private func bytes(_ line: String) -> [UInt8] { Array(Cobol.x(line, 132).utf8) }
        func after(_ n: Int, _ line: String) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0a, count: n) + bytes(line)); pending = true
        }
        func afterPage(_ line: String) { s.store.appendRaw(path, [0x0c] + bytes(line)); pending = true }
        func before(_ n: Int, _ line: String) {
            s.store.appendRaw(path, bytes(line) + [UInt8](repeating: 0x0a, count: n)); pending = false
        }
        func close() { if pending { s.store.appendRaw(path, [0x0a]); pending = false } }
        var line5: String { String(repeating: " ", count: 10) + name.text + d1.text + d2.text }
        func clear5() { name.clear(); d1.clear(); d2.clear() }
        func write5(_ n: Int = 1) { after(n, line5) }
        func yesNo(_ cond: Bool) -> String { t(cond ? "yes" : "no") }
        func isY(_ f: String) -> Bool { sys.str(f) == "Y" }
        /// "見出し" を先頭に置き、skip 桁あけて値を置く (STRING ... POINTER / ADD n TO pointer)
        func d2Labelled(_ key: String, skip: Int, _ value: String) {
            var p = 1
            d2.string(&p, t(key))
            p += skip
            d2.string(&p, value)
        }
    }

    // 編集項目
    static func z(_ v: Int64, _ width: Int) -> String {       // z(n-1)9
        let d = String(abs(v) % Cobol.pow10(width))
        return String(repeating: " ", count: width - d.count) + d
    }
    static func n9(_ v: Int64, _ width: Int) -> String { Cobol.z(abs(v) % Cobol.pow10(width), width) }
    static func rate(_ v: Int64) -> String {                  // z9.99
        let a = abs(v) % 10000
        return z(a / 100, 2) + "." + Cobol.z(a % 100, 2)
    }
    /// STRING の delimited by (区切りの手前まで)
    static func upTo(_ text: String, _ delim: String) -> String {
        guard let r = text.range(of: delim) else { return text }
        return String(text[..<r.lowerBound])
    }

    static func run(_ s: Session, _ st: Sys002.State) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(Sys002.t(s, "print_q"), at: 1201, color: 2)
        let r = try c.accept(at: 1233, size: 1, initial: "Y", options: [.update], color: 4)
        if r == "N" || r == "n" { return }

        let p = Ctx(s, st)
        let sp = { (n: Int) in String(repeating: " ", count: n) }
        func line1(_ page: Int) -> String {
            Cobol.x(Sys002.progName, 16) + sp(34) + p.t("title") + sp(27) + Cobol.x(st.lineDate, 10) + sp(6) + p.t("page") + z(Int64(page), 2)
        }
        func line3(_ lead: Int, _ a: String, _ b: String) -> String { sp(lead) + p.t(a) + sp(40) + p.t(b) }
        let stars16 = String(repeating: "*", count: 16)
        var l4part1 = sp(24) + stars16
        var l4part2 = sp(40) + stars16
        func line4() -> String { l4part1 + l4part2 }

        let pc = st.sys.str("p-c") == "P", br = st.sys.str("p-c") == "B"
        p.before(1, line1(1))
        p.after(1, line3(24, "h_user", "h_gl"))
        p.after(1, line4())
        p.name.move(p.t("name"))
        p.d1.move(st.sys.str("usera"))
        p.d2.move(p.t(pc ? "pc_sel" : (br ? "br_sel" : "neither")))
        p.write5(2)
        p.name.move(p.t("address"))
        p.d1.move(st.sys.str("address-1"))
        if !pc && !br { p.d2.clear() } else { p.d2.move(p.t(st.sys.str("p-c-level") == "R" ? "rev_only" : "all_acs")) }
        p.write5()
        p.name.clear(); p.d2.clear()
        p.d1.move(st.sys.str("address-2"))
        if !pc && !br { p.d2.clear() } else { p.d2.move(p.t(p.isY("p-c-grouped") ? "grouped" : "not_grouped")) }
        p.write5()
        p.d1.move(st.sys.str("address-3"))
        p.d2.move(p.t(p.isY("comps") ? "comp_req" : "comp_not"))
        p.write5()
        var ptr = 1
        p.d1.string(&ptr, upTo(Cobol.x(st.sys.str("address-4"), 24), "  "))
        p.d1.string(&ptr, ",")
        p.d1.string(&ptr, upTo(Cobol.x(st.sys.str("post-code"), 12), "  "))
        p.d1.string(&ptr, ",")
        p.d1.string(&ptr, upTo(Cobol.x(st.sys.str("country"), 24), "  "))
        p.d2.move(p.t(p.isY("ledger-2nd-index") ? "idx_sel" : "idx_not"))
        p.write5()
        p.name.move(p.t("dateform"))
        let df = st.sys.int("date-form")
        if df == 0 || df == 1 {
            p.d1.move(p.t("df_uk"))
            st.sys.setInt("date-form", 1)
        } else {
            p.d1.move(p.t(df == 2 ? "df_usa" : "df_intl"))
        }
        p.d2.clear()
        p.write5()
        st.uBin = st.sys.int("start-date")
        Sys002.convertDate(st)
        p.d1.move(st.wsDate)
        p.name.move(p.t("period_start"))
        p.d2.move(p.t(p.isY("m-v") ? "min_val" : "full_val"))
        p.write5()
        st.uBin = st.sys.int("end-date")
        Sys002.convertDate(st)
        p.d1.move(st.wsDate)
        p.name.move(p.t("period_end"))
        p.d2.move(p.t(p.isY("arch") ? "arch_sel" : "arch_not"))
        p.write5()
        p.clear5()
        ptr = 1
        p.d1.string(&ptr, rate(st.sys.int("vat-rate-1")) + " / " + rate(st.sys.int("vat-rate-4")))
        p.d1.string(&ptr, p.t("vat_reg"))
        p.d1.string(&ptr, Cobol.x(st.sys.str("vat-reg-number"), 11))
        p.name.move(p.t("vat14"))
        if st.sys.int("sales-range") == 0 {
            p.d2.move(p.t("no_sales_range"))
        } else {
            p.d2.move(p.t("sales_range"))
            p.d2.move(n9(st.sys.int("sales-range"), 1), at: 41, len: 1)
        }
        p.write5()
        p.d1.clear()
        ptr = 1
        p.d1.string(&ptr, rate(st.sys.int("vat-rate-2")) + " / " + rate(st.sys.int("vat-rate-5")))
        p.name.move(p.t("vat25"))
        if st.sys.int("purchase-range") == 0 {
            p.d2.move(p.t("no_purch_range"))
        } else {
            p.d2.move(p.t("purch_range"))
            p.d2.move(n9(st.sys.int("purchase-range"), 1), at: 41, len: 1)
        }
        p.write5()
        p.d1.move(rate(st.sys.int("vat-rate-3")))
        p.name.move(p.t("vat3"))
        p.d2.move(p.t(p.isY("vat") ? "autovat" : "manvat"))
        p.write5()
        p.clear5()
        p.d2Labelled("cycles_q", skip: 0, z(st.sys.int("period"), 5))
        p.name.move(p.t("cur_quarter"))
        ptr = 1
        p.d1.string(&ptr, z(st.sys.int("current-quarter"), 2))
        p.write5()
        p.d2.clear(); p.d1.clear()
        p.d2Labelled("next_batch_dash", skip: 0, z(st.sys.int("next-batch"), 5))
        p.name.move(p.t("cur_cycle"))
        ptr = 1
        p.d1.string(&ptr, z(st.sys.int("scycle"), 2))
        p.write5()
        p.clear5()
        p.d2Labelled("irs_instead", skip: 0, p.yesNo(p.isY("irs-instead")))
        p.name.move(p.t("print_lines"))
        p.d1.move(z(st.sys.int("page-lines"), 3))
        p.write5()
        p.d2.clear()

        // ACAS / P-L
        p.after(2, line3(24, "h_acas", "h_pl"))
        p.after(1, line4())
        p.d2.move(p.t("addr_delim"))
        p.d2.move(st.sys.str("pl-delim"), at: 29, len: 1)
        p.name.move(p.t("environment"))
        p.d1.move(p.t(st.sys.int("host") == 1 ? "multi" : "single"))
        p.write5(2)
        p.name.move(p.t("opsys"))
        var temp = ""
        switch st.sys.int("op-system") {
        case 2: temp = "Windows"
        case 1: temp = "Dos"
        case 4: temp = "OS/2"
        case 5: temp = "Unix"
        case 6: temp = "Linux"
        default: break
        }
        var temp2 = ""
        switch st.sys.int("data-capture-used") {
        case 0: temp2 = p.t("and_std")
        case 1: temp2 = p.t("and_gui")
        case 2: temp2 = p.t("and_widget")
        default: break
        }
        ptr = 1
        p.d1.string(&ptr, upTo(Cobol.x(temp, 43), " "))
        p.d1.string(&ptr, upTo(Cobol.x(temp2, 20), " "))
        p.d2.move(p.t("next_batch"))
        ptr = 25
        p.d2.string(&ptr, n9(st.sys.int("bl-next-batch"), 5))
        p.write5()
        p.name.move(p.t("sysver"))
        p.d1.move(p.t(st.sys.str("maps-ser-xx") == "mp" && st.sys.int("maps-ser-nn") == 9999 ? "free" : "commercial"))
        p.d2Labelled("next_folio", skip: 3, n9(st.sys.int("next-folio"), 8))
        p.write5()
        p.clear5()
        let fsu = st.sys.int("file-system-used")
        if fsu != 0 && fsu != 1 { st.sys.setInt("file-system-used", 0) }
        temp = st.sys.int("file-system-used") == 0 ? p.t("cobol_files") : p.t("rdbms_used")
        let dup = st.sys.int("file-duplicates-in-use")
        if dup != 0 && dup != 1 { st.sys.setInt("file-duplicates-in-use", 0) }
        ptr = 1
        p.d1.string(&ptr, upTo(Cobol.x(temp, 43), " "))
        p.d1.string(&ptr, p.t(st.sys.int("file-duplicates-in-use") == 1 ? "dup_used" : "dup_not"))
        p.d2Labelled("pay_ac", skip: 6, n9(st.sys.int("bl-pay-ac"), 6))
        p.write5()
        p.clear5()
        p.name.move(p.t("path_irs"))
        p.d1.move(s.environment["ACAS_IRS"] ?? "")
        if p.d1.isSpaces { p.d1.move(p.t("unset_env")) }
        p.d2Labelled("ledger_ac", skip: 6, n9(st.sys.int("bl-purch-ac"), 6))
        p.write5()
        p.clear5()
        p.name.move(p.t("path_ledgers"))
        p.d1.move(s.environment["ACAS_LEDGERS"] ?? "")
        if p.d1.isSpaces { p.d1.move(p.t("unset_env")) }
        p.d2Labelled("creditor_ac", skip: 6, n9(st.sys.int("p-creditors"), 6))
        p.write5()
        let os = st.sys.int("op-system")
        let osSingle = os == 1 || os == 2 || os == 4
        let stock = st.sys.int("level-4") == 1
        p.clear5()
        p.name.move(p.t("spool1"))
        p.d1.move(osSingle ? p.t("not_used") : st.sys.str("print-spool-name"))
        p.d2Labelled("stock_link", skip: 7, p.yesNo(p.isY("pl-stock-link") && stock))
        p.write5()
        p.clear5()
        p.name.move(p.t("spool2"))
        p.d1.move(osSingle ? p.t("not_used") : st.sys.str("print-spool-name2"))
        p.write5()
        p.clear5()
        p.name.move(p.t("spool3"))
        p.d1.move(osSingle ? p.t("not_used") : st.sys.str("print-spool-name3"))
        p.write5()

        // Inv. / S-L
        p.after(2, line3(24, "h_inv", "h_sl"))
        p.after(1, line4())
        p.after(1, "")
        for a in [3, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11] {
            slPrint(p, a)
            p.write5()
        }
        p.clear5()
        p.name.move(p.t("heads"))
        ptr = 1
        p.d1.string(&ptr, p.t("on_pick") + Cobol.x(st.sys.str("sl-comp-head-pick"), 1))
        p.d2Labelled("stock_link", skip: 7, p.yesNo(p.isY("sl-stock-link") && stock))
        p.write5()
        for (key, fld, lab, ac) in [("on_inv", "sl-comp-head-inv", "pay_ac", "sl-pay-ac"),
                                    ("on_stat", "sl-comp-head-stat", "ledger_ac", "sl-sales-ac"),
                                    ("on_lets", "sl-comp-head-lets", "debtors_ac", "s-debtors")] {
            ptr = 1
            p.d1.string(&ptr, p.t(key) + Cobol.x(st.sys.str(fld), 1))
            p.d2.clear()
            p.d2Labelled(lab, skip: 6, n9(st.sys.int(ac), 6))
            p.write5()
        }

        // 2 ページ目: Stock / O-E
        p.afterPage(line1(2))
        p.after(2, line3(24, "h_stock", "h_oe"))
        p.after(1, line4())
        p.clear5()
        p.name.move(p.t("debug"))
        p.d1.move(p.yesNo(st.sys.int("stk-debug") == 1))
        p.d2Labelled("oe_used", skip: 7, p.yesNo(st.sys.int("stk-oe-used") == 1))
        p.write5(2)
        p.clear5()
        p.name.move(p.t("manu"))
        p.d1.move(p.yesNo(st.sys.int("stk-manu-used") == 1))
        p.write5()
        p.name.move(p.t("audit"))
        p.d1.move(p.yesNo(st.sys.int("stk-audit-used") == 1))
        p.write5()
        p.name.move(p.t("mov_audit"))
        p.d1.move(p.yesNo(st.sys.int("stk-mov-audit") == 1))
        p.write5()
        func period(_ v: String) -> String {
            switch v {
            case "M": return p.t("monthly")
            case "Q": return p.t("quarterly")
            case "Y": return p.t("yearly")
            default: return p.t("not_set")
            }
        }
        p.name.move(p.t("cur_period"))
        p.d1.move(period(st.sys.str("stk-period-cur")))
        p.write5()
        p.name.move(p.t("dat_period"))
        p.d1.move(period(st.sys.str("stk-period-dat")))
        p.write5()
        p.name.move(p.t("averaging"))
        p.d1.move(p.yesNo(st.sys.int("stk-averaging") == 1))
        p.write5()
        p.name.move(p.t("audit_no"))
        p.d1.move(n9(st.sys.int("stk-audit-no"), 8))
        p.write5()

        // Payroll / RDBMS
        p.after(2, sp(22) + p.t("h_payroll") + sp(40) + p.t("h_rdbms"))
        l4part1 = sp(22) + String(repeating: "*", count: 18)
        p.after(1, line4())
        p.clear5()
        p.name.move(p.t("payroll_used"))
        p.d1.move(p.t("no"))
        let rdbms = st.sys.int("file-system-used") == 1
        if rdbms {
            p.d2.move(p.t("db_schema"))
            p.d2.move(st.sys.str("rdbms-db-name"), at: 21, len: 12)
        }
        p.write5(2)
        if rdbms {
            p.d1.clear(); p.name.clear()
            p.d2.move(p.t("db_user"))
            p.d2.move(st.sys.str("rdbms-user"), at: 21, len: 12)
            p.write5()
            p.d2.move(p.t("db_pass"))
            p.d2.move(p.t("secret"), at: 21, len: 12)
            // move line-3e (1:40) to line-5 (1:40)
            var head = Fld(70)
            head.move(sp(24) + p.t("h_system"), at: 1, len: 40)
            p.after(1, head.text + p.d2.text)
        } else {
            p.after(2, sp(24) + p.t("h_system"))
        }
        l4part1 = sp(24) + stars16
        l4part2 = sp(56)
        p.after(1, line4())
        l4part2 = sp(40) + stars16
        p.clear5()
        p.name.move(p.t("file_statuses"))
        p.d1.move(st.sys.str("file-statuses"))
        p.write5(2)
        p.after(2, sp(51) + p.t("end"))
        p.after(1, sp(51) + String(repeating: "=", count: 30))
        p.close()
        // call "SYSTEM" using Print-Report (lpr): 端末内では帳票の出力を UI へ通知する
        s.onReport?(p.path)
    }

    /// sl-print section
    private static func slPrint(_ p: Ctx, _ a: Int) {
        guard a >= 1 && a <= 11 else { return }
        let sys = p.sys
        p.clear5()
        let type = sys.str("extra-type")
        var ptr = 0
        switch a {
        case 1:
            p.d2.move(p.t(sys.int("sl-dunning") == 0 ? "dun_not" : "dun_sel"))
            if type == "C" { p.name.move(p.t("ext_chg_desc")); p.d1.move(sys.str("extra-desc")) }
            if type == "D" { p.name.move(p.t("ext_disc_desc")); p.d1.move(sys.str("extra-desc")) }
        case 2:
            p.d2.move(p.t(sys.int("sl-charges") == 0 ? "chg_not" : "chg_sel"))
            let r = rate(sys.int("extra-rate"))
            if type == "C" { p.name.move(p.t("ext_chg_rate")); p.d1.move(r) }
            if type == "D" { p.name.move(p.t("ext_disc_rate")); p.d1.move(r) }
        case 3:
            p.d2.move(p.t(sys.str("sl-own-nos") == "N" ? "inv_auto" : "inv_manual"))
            p.name.move(p.t("next_inv"))
            p.d1.move(n9(sys.int("next-invoice"), 8))
        case 4:
            p.d2.move(p.t("credit_period"))
            ptr = 15
            p.d2.string(&ptr, z(sys.int("sl-credit"), 2))
            p.name.move(p.t("inv_level"))
            p.d1.move(n9(sys.int("invoicer"), 1))
        case 5:
            p.d2.move(p.t("std_limit"))
            ptr = 23
            p.d2.string(&ptr, z(sys.int("sl-limit"), 7))
            let ac = n9(sys.int("extra-charge-ac"), 6)
            if type == "C" { p.name.move(p.t("ext_chg_ac")); p.d1.move(ac) }
            if type == "D" { p.name.move(p.t("ext_disc_ac")); p.d1.move(ac) }
        case 6:
            p.d2.move(p.t("std_disc"))
            ptr = 24
            p.d2.string(&ptr, rate(sys.int("sl-disc")))
            p.name.move(p.t("vat_ac"))
            p.d1.move(n9(sys.int("vat-ac"), 6))
        case 7:
            p.d2.move(p.t("min_late"))
            ptr = 25
            p.d2.string(&ptr, z(sys.int("sl-min"), 5))
            p.name.move(p.t("print_vat"))
            p.d1.move(p.t(sys.str("sl-vat-printed") == "Y" ? "yes" : "no3"))
        case 8:
            p.d2.move(p.t("max_late"))
            ptr = 25
            p.d2.string(&ptr, z(sys.int("sl-max"), 5))
        case 9:
            p.d2.move(p.t("late_rate"))
            ptr = 24
            p.d2.string(&ptr, rate(sys.int("sl-late-per")))
        case 10:
            p.d2.move(p.t("addr_delim"))
            p.d2.move(sys.str("sl-delim"), at: 29, len: 1)
        default:
            p.d2.move(p.t("next_batch"))
            ptr = 25
            p.d2.string(&ptr, n9(sys.int("first-sl-batch"), 5))
            p.name.move(p.t("pf_ret"))
            p.d1.move(z(sys.int("pf-retention"), 3))
        }
    }
}
