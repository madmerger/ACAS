import SwiftUI

func systemSetting(_ name: String) -> String {
    String(localized: String.LocalizationValue("system.settings." + name), table: "System")
}

struct SystemSettingField: Identifiable {
    enum Kind { case text, number, rate, flag, letterFlag, date }
    let id: String
    let kind: Kind
}

enum SystemSettingGroup: String, Identifiable {
    case modules, company, operations, general, sales, purchases, stock
    var id: String { rawValue }
    static let detailGroups: [Self] = [.company, .operations, .general, .sales, .purchases, .stock]

    var module: String? {
        switch self {
        case .general: "level-1"
        case .purchases: "level-2"
        case .sales: "level-3"
        case .stock: "level-4"
        default: nil
        }
    }

    var fields: [SystemSettingField] {
        let groups: [(SystemSettingField.Kind, [String])]
        switch self {
        case .modules:
            groups = [(.flag, ["level-1", "level-2", "level-3", "full-invoicing", "level-4", "level-5"])]
        case .company:
            groups = [
                (.text, ["address-1", "address-2", "address-3", "address-4", "post-code", "country"]),
                (.date, ["start-date", "end-date"]),
                (.number, ["page-lines"]),
                (.rate, ["vat-rate-1", "vat-rate-4", "vat-rate-2", "vat-rate-5", "vat-rate-3"]),
                (.number, ["current-quarter"]),
                (.text, ["vat-reg-number"]),
                (.letterFlag, ["sl-vat-printed"]),
                (.number, ["scycle", "period"]),
            ]
        case .operations:
            groups = [
                (.flag, ["host"]),
                (.number, ["op-system", "data-capture-used"]),
                (.text, ["print-spool-name", "print-spool-name2", "print-spool-name3"]),
            ]
        case .general:
            groups = [
                (.text, ["p-c", "p-c-level"]),
                (.letterFlag, ["p-c-grouped", "comps", "ledger-2nd-index", "m-v", "arch"]),
                (.number, ["header-level", "sales-range", "purchase-range"]),
                (.letterFlag, ["vat"]),
                (.number, ["next-batch"]),
                (.letterFlag, ["irs-instead"]),
            ]
        case .sales:
            groups = [
                (.flag, ["sl-dunning", "sl-charges"]),
                (.number, ["sl-credit"]),
                (.rate, ["sl-late-per"]),
                (.number, ["sl-min", "sl-max", "sl-limit"]),
                (.text, ["sl-delim"]),
                (.letterFlag, ["sl-own-nos"]),
                (.rate, ["sl-disc"]),
                (.number, ["first-sl-batch"]),
                (.letterFlag, ["sl-stock-link"]),
                (.number, ["sl-pay-ac", "sl-sales-ac", "s-debtors"]),
                (.letterFlag, ["sl-comp-head-inv", "sl-comp-head-stat", "sl-comp-head-lets", "sl-comp-head-pick"]),
            ]
        case .purchases:
            groups = [
                (.text, ["pl-delim"]),
                (.letterFlag, ["pl-stock-link"]),
                (.number, ["bl-next-batch", "bl-pay-ac", "bl-purch-ac", "p-creditors"]),
            ]
        case .stock:
            groups = [
                (.flag, ["stk-debug", "stk-manu-used", "stk-oe-used", "stk-audit-used", "stk-mov-audit"]),
                (.text, ["stk-period-cur", "stk-period-dat"]),
                (.flag, ["stk-averaging", "stk-activity-rep-run"]),
                (.number, ["stk-audit-no"]),
            ]
        }
        return groups.flatMap { kind, keys in keys.map { SystemSettingField(id: $0, kind: kind) } }
    }
}
