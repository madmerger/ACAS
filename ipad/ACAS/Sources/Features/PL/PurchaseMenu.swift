import ACASCore
import SwiftUI

func plString(_ key: String) -> String {
    NSLocalizedString(key, tableName: "PL", comment: "")
}

struct PurchaseMenu: View {
    let workspace: Workspace
    @State private var opening = true

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        List {
            NavigationLink(plString("pl.date")) { PurchaseDateForm(workspace: workspace) }
                .accessibilityIdentifier("pl.date")
            NavigationLink(plString("pl.supplier.menu")) { PurchaseSupplierMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.suppliers")
            NavigationLink(plString("pl.enquiry")) { PurchaseSupplierLookup(workspace: workspace, mode: .enquiry) }
                .accessibilityIdentifier("pl.enquiry")
            NavigationLink(plString("pl.invoice.add")) {
                PurchaseTransactionForm(workspace: workspace, transaction: .init(date: ledger.processingDate))
            }
            .accessibilityIdentifier("pl.transaction.add")
            NavigationLink(plString("pl.invoice.edit")) { PurchaseTransactionsView(workspace: workspace, mode: .edit) }
                .accessibilityIdentifier("pl.transaction.edit")
            NavigationLink(plString("pl.invoice.delete")) { PurchaseTransactionsView(workspace: workspace, mode: .delete) }
                .accessibilityIdentifier("pl.transaction.delete")
            NavigationLink(plString("pl.invoice.proof")) { PurchaseTransactionsView(workspace: workspace, mode: .proof) }
                .accessibilityIdentifier("pl.transaction.proof")
            NavigationLink(plString("pl.invoice.post")) { PurchaseTransactionsView(workspace: workspace, mode: .post) }
                .accessibilityIdentifier("pl.transaction.post")
            NavigationLink(plString("pl.analysis.menu")) { PurchaseAnalysisMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.analysis")
            NavigationLink(plString("pl.supplier.alphabetical")) { PurchaseSuppliersView(workspace: workspace, byName: true) }
                .accessibilityIdentifier("pl.suppliers.alphabetical")
            NavigationLink(plString("pl.settings")) { SystemMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.settings")
        }
        .sheet(isPresented: $opening) {
            NavigationStack { PurchaseDateForm(workspace: workspace) }
        }
        .onAppear { if !opening { workspace.completed("pl.menu") } }
    }
}

private struct PurchaseDateForm: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var error: PurchaseNotice?

    var body: some View {
        Form {
            DatePicker(plString("pl.date.value"), selection: $date, displayedComponents: .date)
                .accessibilityIdentifier("pl.date.value")
            Button(plString("pl.action.confirm")) {
                do {
                    try PurchaseLedger(workspace.context).setProcessingDate(date)
                    workspace.completed("pl.date")
                    workspace.completed("pl.menu")
                    dismiss()
                } catch { self.error = PurchaseNotice(error) }
            }
            .accessibilityIdentifier("pl.date.confirm")
        }
        .navigationTitle(plString("pl.date"))
        .onAppear { date = PurchaseLedger(workspace.context).processingDate }
        .purchaseAlert($error)
    }
}

struct PurchaseNotice: Identifiable {
    let message: String
    var id: String { message }

    init(_ error: Error) {
        switch error as? PurchaseLedger.Error {
        case .invalidDate: message = plString("pl.error.date")
        case .invalidCode: message = plString("pl.error.code")
        case .invalidAddress: message = plString("pl.error.address")
        case .duplicateSupplier: message = plString("pl.error.supplier.duplicate")
        case .supplierNotFound: message = plString("pl.error.supplier.missing")
        case .supplierHasBalance: message = plString("pl.error.supplier.balance")
        case .invalidTransaction: message = plString("pl.error.invoice")
        case .transactionNotFound: message = plString("pl.error.invoice.missing")
        case .alreadyPosted: message = plString("pl.error.invoice.posted")
        case .duplicateTransaction: message = plString("pl.error.invoice.duplicate")
        case .analysisCodeNotFound: message = plString("pl.error.analysis.missing")
        case .analysisFileIncompatible: message = plString("pl.error.analysis.format")
        case nil: message = plString("pl.error.generic")
        }
    }
}

extension View {
    func purchaseAlert(_ notice: Binding<PurchaseNotice?>) -> some View {
        alert(item: notice) {
            Alert(title: Text($0.message), dismissButton: .default(Text(plString("pl.action.close"))))
        }
    }
}

func purchaseAmount(_ value: Int64) -> String {
    (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
}
