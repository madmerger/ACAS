import Foundation

enum SystemSettingsReport {
    struct Fld {
        var bytes: [UInt8]
        init(_ width: Int) { bytes = [UInt8](repeating: 32, count: width) }
        mutating func move(_ text: String) { bytes = SJIS.encode(text, size: bytes.count) }
        mutating func clear() { bytes = [UInt8](repeating: 32, count: bytes.count) }
        mutating func string(_ pointer: inout Int, _ text: String) {
            guard pointer > 0, pointer <= bytes.count else { return }
            let encoded = text.reduce(into: [UInt8]()) { result, character in
                if let byte = character.asciiValue { result.append(byte) }
                else { result += String(character).data(using: .shiftJIS).map { Array($0) } ?? [63] }
            }.prefix(bytes.count - pointer + 1)
            bytes.replaceSubrange(pointer - 1..<pointer - 1 + encoded.count, with: encoded)
            pointer += encoded.count
        }
        mutating func move(_ text: String, at position: Int, len: Int) {
            var p = position
            string(&p, Cobol.x(text, len))
        }
        var text: String { SJIS.decode(bytes[...]) }
        var isSpaces: Bool { bytes.allSatisfy { $0 == 32 } }
    }

    final class Ctx {
        let sys: Record
        var name = Fld(17), d1 = Fld(43), d2 = Fld(50)
        var output: [UInt8] = []
        private var pending = false
        init(_ sys: Record) { self.sys = sys }
        func t(_ key: String) -> String { SystemSettingsReport.labels[key]! }
        private func bytes(_ line: String) -> [UInt8] { SJIS.encode(line, size: 132) }
        func after(_ n: Int, _ line: String) {
            output += [UInt8](repeating: 10, count: n) + bytes(line)
            pending = true
        }
        func afterPage(_ line: String) {
            output += [12] + bytes(line)
            pending = true
        }
        func before(_ n: Int, _ line: String) {
            output += bytes(line) + [UInt8](repeating: 10, count: n)
            pending = false
        }
        func close() { if pending { output.append(10); pending = false } }
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

    static func render(_ sys: Record, paths: SystemReportPaths) -> [UInt8] {
        let p = Ctx(sys)
        let dateForm = Int(sys.int("date-form"))
        func reportDate(_ key: String) -> String {
            let raw = Int(sys.int(key))
            return raw > 0 ? Maps04.format(Maps04.toDate(raw), dateForm: dateForm) : ""
        }
        let sp = { (n: Int) in String(repeating: " ", count: n) }
        func line1(_ page: Int) -> String {
            Cobol.x("SYS002 (3.01.39)", 16) + sp(34) + p.t("title") + sp(27) + Cobol.x(reportDate("run-date"), 10) + sp(6) + p.t("page") + z(Int64(page), 2)
        }
        func line3(_ lead: Int, _ a: String, _ b: String) -> String { sp(lead) + p.t(a) + sp(40) + p.t(b) }
        let stars16 = String(repeating: "*", count: 16)
        var l4part1 = sp(24) + stars16
        var l4part2 = sp(40) + stars16
        func line4() -> String { l4part1 + l4part2 }

        let pc = sys.str("p-c") == "P", br = sys.str("p-c") == "B"
        p.before(1, line1(1))
        p.after(1, line3(24, "h_user", "h_gl"))
        p.after(1, line4())
        p.name.move(p.t("name"))
        p.d1.move(sys.str("usera"))
        p.d2.move(p.t(pc ? "pc_sel" : (br ? "br_sel" : "neither")))
        p.write5(2)
        p.name.move(p.t("address"))
        p.d1.move(sys.str("address-1"))
        if !pc && !br { p.d2.clear() } else { p.d2.move(p.t(sys.str("p-c-level") == "R" ? "rev_only" : "all_acs")) }
        p.write5()
        p.name.clear(); p.d2.clear()
        p.d1.move(sys.str("address-2"))
        if !pc && !br { p.d2.clear() } else { p.d2.move(p.t(p.isY("p-c-grouped") ? "grouped" : "not_grouped")) }
        p.write5()
        p.d1.move(sys.str("address-3"))
        p.d2.move(p.t(p.isY("comps") ? "comp_req" : "comp_not"))
        p.write5()
        var ptr = 1
        p.d1.string(&ptr, upTo(Cobol.x(sys.str("address-4"), 24), "  "))
        p.d1.string(&ptr, ",")
        p.d1.string(&ptr, upTo(Cobol.x(sys.str("post-code"), 12), "  "))
        p.d1.string(&ptr, ",")
        p.d1.string(&ptr, upTo(Cobol.x(sys.str("country"), 24), "  "))
        p.d2.move(p.t(p.isY("ledger-2nd-index") ? "idx_sel" : "idx_not"))
        p.write5()
        p.name.move(p.t("dateform"))
        let df = sys.int("date-form")
        if df == 0 || df == 1 {
            p.d1.move(p.t("df_uk"))
        } else {
            p.d1.move(p.t(df == 2 ? "df_usa" : "df_intl"))
        }
        p.d2.clear()
        p.write5()
        p.d1.move(reportDate("start-date"))
        p.name.move(p.t("period_start"))
        p.d2.move(p.t(p.isY("m-v") ? "min_val" : "full_val"))
        p.write5()
        p.d1.move(reportDate("end-date"))
        p.name.move(p.t("period_end"))
        p.d2.move(p.t(p.isY("arch") ? "arch_sel" : "arch_not"))
        p.write5()
        p.clear5()
        ptr = 1
        p.d1.string(&ptr, rate(sys.int("vat-rate-1")) + " / " + rate(sys.int("vat-rate-4")))
        p.d1.string(&ptr, p.t("vat_reg"))
        p.d1.string(&ptr, Cobol.x(sys.str("vat-reg-number"), 11))
        p.name.move(p.t("vat14"))
        if sys.int("sales-range") == 0 {
            p.d2.move(p.t("no_sales_range"))
        } else {
            p.d2.move(p.t("sales_range"))
            p.d2.move(n9(sys.int("sales-range"), 1), at: 41, len: 1)
        }
        p.write5()
        p.d1.clear()
        ptr = 1
        p.d1.string(&ptr, rate(sys.int("vat-rate-2")) + " / " + rate(sys.int("vat-rate-5")))
        p.name.move(p.t("vat25"))
        if sys.int("purchase-range") == 0 {
            p.d2.move(p.t("no_purch_range"))
        } else {
            p.d2.move(p.t("purch_range"))
            p.d2.move(n9(sys.int("purchase-range"), 1), at: 41, len: 1)
        }
        p.write5()
        p.d1.move(rate(sys.int("vat-rate-3")))
        p.name.move(p.t("vat3"))
        p.d2.move(p.t(p.isY("vat") ? "autovat" : "manvat"))
        p.write5()
        p.clear5()
        p.d2Labelled("cycles_q", skip: 0, z(sys.int("period"), 5))
        p.name.move(p.t("cur_quarter"))
        ptr = 1
        p.d1.string(&ptr, z(sys.int("current-quarter"), 2))
        p.write5()
        p.d2.clear(); p.d1.clear()
        p.d2Labelled("next_batch_dash", skip: 0, z(sys.int("next-batch"), 5))
        p.name.move(p.t("cur_cycle"))
        ptr = 1
        p.d1.string(&ptr, z(sys.int("scycle"), 2))
        p.write5()
        p.clear5()
        p.d2Labelled("irs_instead", skip: 0, p.yesNo(p.isY("irs-instead")))
        p.name.move(p.t("print_lines"))
        p.d1.move(z(sys.int("page-lines"), 3))
        p.write5()
        p.d2.clear()

        // ACAS / P-L
        p.after(2, line3(24, "h_acas", "h_pl"))
        p.after(1, line4())
        p.d2.move(p.t("addr_delim"))
        p.d2.move(sys.str("pl-delim"), at: 29, len: 1)
        p.name.move(p.t("environment"))
        p.d1.move(p.t(sys.int("host") == 1 ? "multi" : "single"))
        p.write5(2)
        p.name.move(p.t("opsys"))
        var temp = ""
        switch sys.int("op-system") {
        case 2: temp = "Windows"
        case 1: temp = "Dos"
        case 4: temp = "OS/2"
        case 5: temp = "Unix"
        case 6: temp = "Linux"
        default: break
        }
        var temp2 = ""
        switch sys.int("data-capture-used") {
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
        p.d2.string(&ptr, n9(sys.int("bl-next-batch"), 5))
        p.write5()
        p.name.move(p.t("sysver"))
        p.d1.move(p.t(sys.str("maps-ser-xx") == "mp" && sys.int("maps-ser-nn") == 9999 ? "free" : "commercial"))
        p.d2Labelled("next_folio", skip: 3, n9(sys.int("next-folio"), 8))
        p.write5()
        p.clear5()
        let fsu = sys.int("file-system-used")
        temp = fsu != 1 ? p.t("cobol_files") : p.t("rdbms_used")
        let dup = sys.int("file-duplicates-in-use")
        ptr = 1
        p.d1.string(&ptr, upTo(Cobol.x(temp, 43), " "))
        p.d1.string(&ptr, p.t(dup == 1 ? "dup_used" : "dup_not"))
        p.d2Labelled("pay_ac", skip: 6, n9(sys.int("bl-pay-ac"), 6))
        p.write5()
        p.clear5()
        p.name.move(p.t("path_irs"))
        p.d1.move(paths.incompleteRecords)
        if p.d1.isSpaces { p.d1.move(p.t("unset_env")) }
        p.d2Labelled("ledger_ac", skip: 6, n9(sys.int("bl-purch-ac"), 6))
        p.write5()
        p.clear5()
        p.name.move(p.t("path_ledgers"))
        p.d1.move(paths.ledgers)
        if p.d1.isSpaces { p.d1.move(p.t("unset_env")) }
        p.d2Labelled("creditor_ac", skip: 6, n9(sys.int("p-creditors"), 6))
        p.write5()
        let os = sys.int("op-system")
        let osSingle = os == 1 || os == 2 || os == 4
        let stock = sys.int("level-4") == 1
        p.clear5()
        p.name.move(p.t("spool1"))
        p.d1.move(osSingle ? p.t("not_used") : sys.str("print-spool-name"))
        p.d2Labelled("stock_link", skip: 7, p.yesNo(p.isY("pl-stock-link") && stock))
        p.write5()
        p.clear5()
        p.name.move(p.t("spool2"))
        p.d1.move(osSingle ? p.t("not_used") : sys.str("print-spool-name2"))
        p.write5()
        p.clear5()
        p.name.move(p.t("spool3"))
        p.d1.move(osSingle ? p.t("not_used") : sys.str("print-spool-name3"))
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
        p.d1.string(&ptr, p.t("on_pick") + Cobol.x(sys.str("sl-comp-head-pick"), 1))
        p.d2Labelled("stock_link", skip: 7, p.yesNo(p.isY("sl-stock-link") && stock))
        p.write5()
        for (key, fld, lab, ac) in [("on_inv", "sl-comp-head-inv", "pay_ac", "sl-pay-ac"),
                                    ("on_stat", "sl-comp-head-stat", "ledger_ac", "sl-sales-ac"),
                                    ("on_lets", "sl-comp-head-lets", "debtors_ac", "s-debtors")] {
            ptr = 1
            p.d1.string(&ptr, p.t(key) + Cobol.x(sys.str(fld), 1))
            p.d2.clear()
            p.d2Labelled(lab, skip: 6, n9(sys.int(ac), 6))
            p.write5()
        }

        // 2 ページ目: Stock / O-E
        p.afterPage(line1(2))
        p.after(2, line3(24, "h_stock", "h_oe"))
        p.after(1, line4())
        p.clear5()
        p.name.move(p.t("debug"))
        p.d1.move(p.yesNo(sys.int("stk-debug") == 1))
        p.d2Labelled("oe_used", skip: 7, p.yesNo(sys.int("stk-oe-used") == 1))
        p.write5(2)
        p.clear5()
        p.name.move(p.t("manu"))
        p.d1.move(p.yesNo(sys.int("stk-manu-used") == 1))
        p.write5()
        p.name.move(p.t("audit"))
        p.d1.move(p.yesNo(sys.int("stk-audit-used") == 1))
        p.write5()
        p.name.move(p.t("mov_audit"))
        p.d1.move(p.yesNo(sys.int("stk-mov-audit") == 1))
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
        p.d1.move(period(sys.str("stk-period-cur")))
        p.write5()
        p.name.move(p.t("dat_period"))
        p.d1.move(period(sys.str("stk-period-dat")))
        p.write5()
        p.name.move(p.t("averaging"))
        p.d1.move(p.yesNo(sys.int("stk-averaging") == 1))
        p.write5()
        p.name.move(p.t("audit_no"))
        p.d1.move(n9(sys.int("stk-audit-no"), 8))
        p.write5()

        // Payroll / RDBMS
        p.after(2, sp(22) + p.t("h_payroll") + sp(40) + p.t("h_rdbms"))
        l4part1 = sp(22) + String(repeating: "*", count: 18)
        p.after(1, line4())
        p.clear5()
        p.name.move(p.t("payroll_used"))
        p.d1.move(p.t("no"))
        let rdbms = sys.int("file-system-used") == 1
        if rdbms {
            p.d2.move(p.t("db_schema"))
            p.d2.move(sys.str("rdbms-db-name"), at: 21, len: 12)
        }
        p.write5(2)
        if rdbms {
            p.d1.clear(); p.name.clear()
            p.d2.move(p.t("db_user"))
            p.d2.move(sys.str("rdbms-user"), at: 21, len: 12)
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
        p.d1.move(sys.str("file-statuses"))
        p.write5(2)
        p.after(2, sp(51) + p.t("end"))
        p.after(1, sp(51) + String(repeating: "=", count: 30))
        p.close()
        return p.output
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

    private static let labels: [String: String] = [
        "title": "S Y S T E M   P A R A M E T E R S",
        "page": "Page",
        "h_user": "User  Parameters",
        "h_gl": "G/L   Parameters",
        "h_acas": "ACAS  Parameters",
        "h_pl": "P/L   Parameters",
        "h_inv": "Inv.  Parameters",
        "h_sl": "S/L   Parameters",
        "h_stock": "Stock Parameters",
        "h_oe": "O/E   Parameters",
        "h_payroll": "Payroll Parameters",
        "h_rdbms": "RDMBS Parameters",
        "h_system": "System Paramters",
        "end": "End of System Parameter Report",
        "name": "Name",
        "pc_sel": "Profit-Centres Selected",
        "br_sel": "Branches Selected",
        "neither": "Neither P/C or Branches Selected",
        "address": "Address",
        "rev_only": "Only for Revenue Accounts",
        "all_acs": "For all Accounts",
        "grouped": "P-C / Branches Grouped on 1st Digit",
        "not_grouped": "P-C / Branches not Grouped",
        "comp_req": "Comparative Figures Required",
        "comp_not": "Comparative Figures not Required",
        "idx_sel": "Alphabetic Ledger Index Selected",
        "idx_not": "Alphabetic Ledger Index not Selected",
        "dateform": "Date Format",
        "df_uk": "UK Format",
        "df_usa": "USA Format",
        "df_intl": "Intl Format",
        "period_start": "Period Start",
        "min_val": "Min. Validation During Data Entry",
        "full_val": "Full Validation During Data Entry",
        "period_end": "       End",
        "arch_sel": "Transaction Archiving Selected",
        "arch_not": "Transactions Deleted at End of Cycle",
        "vat_reg": "  VAT Reg: ",
        "vat14": "VAT    Rate 1/4.",
        "no_sales_range": "No Reserved Sales Range",
        "sales_range": "Sales Range most Significant Digit is - ",
        "vat25": "       Rate 2/5.",
        "no_purch_range": "No Reserved Purchase Range",
        "purch_range": "Purchase Range Most Signif.  Digit is - ",
        "vat3": "       Rate 3.",
        "autovat": "Auto VAT Posting Selected",
        "manvat": "Manual VAT Posting Selected",
        "cycles_q": "Cycles per Quarter - ",
        "cur_quarter": "Current Quarter ",
        "next_batch_dash": "Next Batch Number  - ",
        "cur_cycle": "Current Cycle",
        "irs_instead": "Using IRS instead of GL - ",
        "yes": "Yes",
        "no": "No",
        "no3": "No ",
        "print_lines": "Print Lines",
        "addr_delim": "Address Delimiter",
        "environment": "Environment",
        "multi": "Multi-User",
        "single": "Single User",
        "opsys": "Op. System",
        "and_std": " & Cobol Standard",
        "and_gui": " & Gui Display",
        "and_widget": " & Widget Display",
        "next_batch": "Next Batch Number",
        "sysver": "System version",
        "free": "Using (Free) Open Source Version of ACAS",
        "commercial": "Using Commercial Version of ACAS",
        "next_folio": "Next Folio Number ",
        "cobol_files": "Cobol Data Files Used",
        "rdbms_used": "Rdbms is used  ",
        "dup_used": "/Dup Mode Used",
        "dup_not": "/Dup Mode Not Used",
        "pay_ac": "Pay      Account ",
        "path_irs": "Path to IRS",
        "unset_env": "UNSET Environment Variable",
        "ledger_ac": "Ledger   Account ",
        "path_ledgers": "Path to Ledgers",
        "creditor_ac": "Creditor Account ",
        "spool1": "Prt Spool Name 1",
        "spool2": "Prt Spool Name 2",
        "spool3": "Prt Spool Name 3",
        "not_used": "Not Used",
        "stock_link": "Stock Control Link ",
        "heads": "Company Heads Pri",
        "on_pick": "nt on Delivery notes: ",
        "on_inv": "nt on Invoices      : ",
        "on_stat": "nt on Statements    : ",
        "on_lets": "nt on Late Letters  : ",
        "debtors_ac": "Debtors  Account ",
        "debug": "Debug Mode",
        "oe_used": "O/Entry in Use   ",
        "manu": "Manufacturing",
        "audit": "Audit in Use",
        "mov_audit": "Movement Audits",
        "cur_period": "Current Period",
        "monthly": "Monthly",
        "quarterly": "Quarterly",
        "yearly": "Yearly",
        "not_set": "NOT SET",
        "dat_period": "To Date Period",
        "averaging": "Stock Averaging",
        "audit_no": "Current Audit No",
        "payroll_used": "Payroll in Use   ",
        "db_schema": "RDBMS DB Schema ",
        "db_user": "RDB User Name   ",
        "db_pass": "RDB User Passwd ",
        "secret": "It's SECRET",
        "file_statuses": "File Statuses",
        "dun_not": "Dunning Letters not Selected",
        "dun_sel": "Dunning Letters Selected",
        "ext_chg_desc": "Ext. Charge Desc",
        "ext_disc_desc": "Extra Disc. Desc",
        "chg_not": "Late Charges not Selected",
        "chg_sel": "Late Charges Selected",
        "ext_chg_rate": "Ext. Charge Rate",
        "ext_disc_rate": "Ext. Disc. Rate",
        "inv_auto": "Computer Generated Invoice Numbers Selected",
        "inv_manual": "Manually Entered Invoice Numbers Selected",
        "next_inv": "Next Inv. Number",
        "credit_period": "Credit Period nn Days",
        "inv_level": "Inv. Data Level",
        "std_limit": "Standard Credit Limit",
        "ext_chg_ac": "Extra Charge A/C",
        "ext_disc_ac": "Extra Disc. A/C",
        "std_disc": "Standard Discount is   nn.nn%",
        "vat_ac": "VAT Account",
        "min_late": "Min. Late Balance",
        "print_vat": "Print VAT Nunber",
        "max_late": "Max. Late Charge",
        "late_rate": "Late Charge Rate       nn.nn%",
        "pf_ret": "Proforma Retent.",
    ]
}
