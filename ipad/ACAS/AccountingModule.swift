enum AccountingModule: String, CaseIterable, Identifiable {
    case salesLedger = "Sales Ledger"
    case purchaseLedger = "Purchase Ledger"
    case stockControl = "Stock Control"
    case generalLedger = "General Ledger"
    case irs = "IRS"

    var id: String { rawValue }
    var title: String { rawValue }
}
