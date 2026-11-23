import Foundation

/// copybooks/wssystem.cob の System-Record (1024 バイト) と同一配置。
public enum SystemLayout {
    private static let bc = FieldType.native(bytes: 1, signed: true)
    private static let bcu = FieldType.native(bytes: 1, signed: false)
    private static let bs = FieldType.native(bytes: 2, signed: true)
    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static let rate = FieldType.comp(digits: 4, scale: 2, signed: false)
    private static func d1(_ n: String) -> (String, FieldType) { (n, .n9(digits: 1, scale: 0, signed: false)) }
    private static func x(_ n: String, _ l: Int) -> (String, FieldType) { (n, .x(l)) }

    public static let layout: Layout = {
        var f: [(String, FieldType)] = [
            ("system-record-version-prime", bc), ("system-record-version-secondary", bc),
            ("vat-rate-1", rate), ("vat-rate-2", rate), ("vat-rate-3", rate), ("vat-rate-4", rate), ("vat-rate-5", rate),
            ("scycle", bc), ("period", bc), ("page-lines", bcu),
            ("next-invoice", bl), ("run-date", bl), ("start-date", bl), ("end-date", bl),
            x("usera", 32), x("user-code", 32), x("address-1", 24), x("address-2", 24), x("address-3", 24),
            x("address-4", 24), x("post-code", 12), x("country", 24), x("print-spool-name", 48),
            x("file-statuses", 32), d1("pass-value"),
            d1("level-1"), d1("level-2"), d1("level-3"), d1("level-4"), d1("level-5"), d1("level-6"),
            x("pass-word", 4), d1("host"), d1("op-system"), d1("current-quarter"),
            d1("file-system-used"), d1("file-duplicates-in-use"),
            x("maps-ser-xx", 2), ("maps-ser-nn", bs), d1("date-form"), d1("data-capture-used"),
            x("rdbms-db-name", 12), x("rdbms-user", 12), x("rdbms-passwd", 12), x("vat-reg-number", 11), ("", .filler(8)),
            // General-Ledger-Block
            x("p-c", 1), x("p-c-grouped", 1), x("p-c-level", 1), x("comps", 1), x("comps-active", 1), x("m-v", 1),
            x("arch", 1), x("trans-print", 1), x("trans-printed", 1), d1("header-level"), d1("sales-range"),
            d1("purchase-range"), x("vat", 1), x("batch-id", 1), x("ledger-2nd-index", 1), x("irs-instead", 1),
            ("ledger-sec", bs), ("updates", bs), ("postings", bs), ("next-batch", bs),
            ("extra-charge-ac", bl), ("vat-ac", bl), x("print-spool-name2", 48),
            // Purchase-Ledger-Block
            ("next-folio", bl), ("bl-pay-ac", bl), ("p-creditors", bl), ("bl-purch-ac", bl), ("bl-end-cycle-date", bl),
            ("bl-next-batch", bs), ("age-to-pay", bc), x("purchase-ledger", 1), x("pl-delim", 1), d1("entry-level"),
            d1("p-flag-a"), d1("p-flag-i"), d1("p-flag-p"), x("pl-stock-link", 1), x("print-spool-name3", 48), ("", .filler(10)),
            // Sales-Ledger-Block
            x("sales-ledger", 1), x("sl-delim", 1), x("oi-3-flag", 1), x("cust-flag", 1), x("oi-5-flag", 1),
            x("s-flag-oi-3", 1), d1("full-invoicing"), d1("s-flag-a"), d1("s-flag-i"), d1("s-flag-p"),
            d1("sl-dunning"), d1("sl-charges"), x("sl-own-nos", 1), d1("sl-stats-run"), d1("sl-day-book"),
            d1("invoicer"), x("extra-desc", 14), x("extra-type", 1), x("extra-print", 1), x("sl-stock-link", 1),
            x("sl-stock-audit", 1), ("sl-late-per", rate), ("sl-disc", rate), ("extra-rate", rate),
            ("sl-days-1", bc), ("sl-days-2", bc), ("sl-days-3", bc), ("sl-credit", bc), ("", .filler(2)),
            ("sl-min", bs), ("sl-max", bs), ("pf-retention", bs), ("first-sl-batch", bs),
            ("first-sl-inv", bl), ("sl-limit", bl), ("sl-pay-ac", bl), ("s-debtors", bl), ("sl-sales-ac", bl),
            ("s-end-cycle-date", bl), x("sl-comp-head-pick", 1), x("sl-comp-head-inv", 1), x("sl-comp-head-stat", 1),
            x("sl-comp-head-lets", 1), x("sl-vat-printed", 1), ("", .filler(45)),
            // Stock-Control-Block
            x("stk-abrev-ref", 6), d1("stk-debug"), d1("stk-manu-used"), d1("stk-oe-used"), d1("stk-audit-used"),
            d1("stk-mov-audit"), x("stk-period-cur", 1), x("stk-period-dat", 1), ("", .filler(1)), x("stock-control", 1),
            d1("stk-averaging"), d1("stk-activity-rep-run"), ("", .filler(1)), ("stk-page-lines", bcu), ("stk-audit-no", bcu),
            ("", .filler(68)),
            // Order-Entry-Block
            ("", .filler(128)),
            // IRS-Entry-Block
            x("client", 24), x("fn-1", 9), x("fn-2", 10), x("fn-3", 8), x("fn-4", 8), x("fn-5", 12), x("system-ops", 1),
            ("next-post", .n9(digits: 5, scale: 0, signed: false)),
            ("vat1", .n9(digits: 4, scale: 2, signed: false)), ("vat2", .n9(digits: 4, scale: 2, signed: false)),
            ("vat3", .n9(digits: 4, scale: 2, signed: false)),
            d1("irs-pass-value"), d1("save-sequ"), x("system-work-group", 18), x("pl-app-created", 1),
            ("pl-approp-ac", .n9(digits: 5, scale: 0, signed: false)), d1("1st-time-flag"), ("", .filler(12)),
        ]
        let l = Layout("system-record", f)
        f.removeAll()
        return l
    }()

    public static let path = "system.dat"
}
