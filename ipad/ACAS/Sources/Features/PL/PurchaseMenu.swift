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
            NavigationLink(plString("purchase.date")) { PurchaseDateForm(workspace: workspace) }
                .accessibilityIdentifier("pl.date")
            NavigationLink(plString("purchase.supplier.menu")) { PurchaseSupplierMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.suppliers")
            NavigationLink(plString("purchase.enquiry")) { PurchaseSupplierLookup(workspace: workspace, mode: .enquiry) }
                .accessibilityIdentifier("pl.enquiry")
            NavigationLink(plString("purchase.invoice.add")) {
                PurchaseTransactionForm(workspace: workspace, transaction: .init(date: ledger.processingDate))
            }
            .accessibilityIdentifier("pl.transaction.add")
            NavigationLink(plString("purchase.invoice.edit")) { PurchaseTransactionsView(workspace: workspace, mode: .edit) }
                .accessibilityIdentifier("pl.transaction.edit")
            NavigationLink(plString("purchase.invoice.delete")) { PurchaseTransactionsView(workspace: workspace, mode: .delete) }
                .accessibilityIdentifier("pl.transaction.delete")
            NavigationLink(plString("purchase.invoice.proof")) { PurchaseTransactionsView(workspace: workspace, mode: .proof) }
                .accessibilityIdentifier("pl.transaction.proof")
            NavigationLink(plString("purchase.invoice.post")) { PurchaseTransactionsView(workspace: workspace, mode: .post) }
                .accessibilityIdentifier("pl.transaction.post")
            NavigationLink(plString("purchase.payment.add")) { PurchasePaymentForm(workspace: workspace) }
                .accessibilityIdentifier("pl.payment.add")
            NavigationLink(plString("purchase.payment.edit")) { PurchasePaymentsView(workspace: workspace, mode: .edit) }
                .accessibilityIdentifier("pl.payment.edit")
            NavigationLink(plString("purchase.payment.proof")) { PurchasePaymentsView(workspace: workspace, mode: .proof) }
                .accessibilityIdentifier("pl.payment.proof")
            NavigationLink(plString("purchase.payment.post")) { PurchasePaymentsView(workspace: workspace, mode: .post) }
                .accessibilityIdentifier("pl.payment.post")
            NavigationLink(plString("purchase.analysis.menu")) { PurchaseAnalysisMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.analysis")
            NavigationLink(plString("purchase.supplier.alphabetical")) { PurchaseSuppliersView(workspace: workspace, byName: true) }
                .accessibilityIdentifier("pl.suppliers.alphabetical")
            NavigationLink(plString("purchase.settings")) { SystemMenu(workspace: workspace) }
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
            DatePicker(plString("purchase.date.value"), selection: $date, displayedComponents: .date)
                .accessibilityIdentifier("pl.date.value")
            Button(plString("purchase.action.confirm")) {
                do {
                    try PurchaseLedger(workspace.context).setProcessingDate(date)
                    workspace.completed("pl.date")
                    workspace.completed("pl.menu")
                    dismiss()
                } catch { self.error = PurchaseNotice(error) }
            }
            .accessibilityIdentifier("pl.date.confirm")
        }
        .navigationTitle(plString("purchase.date"))
        .onAppear { date = PurchaseLedger(workspace.context).processingDate }
        .purchaseAlert($error)
    }
}

struct PurchaseNotice: Identifiable {
    let message: String
    var id: String { message }

    init(_ error: Error) {
        if let error = error as? PurchaseLedger.PaymentError {
            switch error {
            case .invalidAmount: message = plString("purchase.error.payment.amount")
            case .paymentNotFound: message = plString("purchase.error.payment.missing")
            case .notProofed: message = plString("purchase.error.payment.proof")
            case .unavailableInvoice, .alreadyAllocated: message = plString("purchase.error.payment.invoice")
            case .issuedSchedule: message = plString("purchase.error.generic")
            }
            return
        }
        switch error as? PurchaseLedger.Error {
        case .invalidDate: message = plString("purchase.error.date")
        case .invalidCode: message = plString("purchase.error.code")
        case .invalidAddress: message = plString("purchase.error.address")
        case .missingAddress: message = plString("purchase.error.address.missing")
        case .addressTooLong: message = plString("purchase.error.address.tooLong")
        case .duplicateSupplier: message = plString("purchase.error.supplier.duplicate")
        case .supplierNotFound: message = plString("purchase.error.supplier.missing")
        case .supplierHasBalance: message = plString("purchase.error.supplier.balance")
        case .invalidTransaction: message = plString("purchase.error.invoice")
        case .transactionNotFound: message = plString("purchase.error.invoice.missing")
        case .alreadyPosted: message = plString("purchase.error.invoice.posted")
        case .duplicateTransaction: message = plString("purchase.error.invoice.duplicate")
        case .analysisCodeNotFound: message = plString("purchase.error.analysis.missing")
        case .analysisFileIncompatible: message = plString("purchase.error.analysis.format")
        case nil: message = plString("purchase.error.generic")
        }
    }
}

extension View {
    func purchaseAlert(_ notice: Binding<PurchaseNotice?>) -> some View {
        alert(item: notice) {
            Alert(title: Text($0.message), dismissButton: .default(Text(plString("purchase.action.close"))))
        }
    }
}

func purchaseAmount(_ value: Int64) -> String {
    (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
}
