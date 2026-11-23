import ACASCore
import SwiftUI

struct PurchaseInvoiceMenu: View {
    let workspace: Workspace

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        List {
            NavigationLink(plString("purchase.invoice.settings")) { PurchaseInvoiceSettingsForm(workspace: workspace) }
                .accessibilityIdentifier("pl.invoice.settings.open")
            NavigationLink(plString("purchase.invoice.add")) {
                PurchaseTransactionForm(workspace: workspace, transaction: .init(date: ledger.processingDate))
            }
            .accessibilityIdentifier("pl.invoice.settings.add")
            NavigationLink(plString("purchase.invoice.edit")) { PurchaseTransactionsView(workspace: workspace, mode: .edit) }
                .accessibilityIdentifier("pl.invoice.settings.edit")
            NavigationLink(plString("purchase.invoice.delete")) { PurchaseTransactionsView(workspace: workspace, mode: .delete) }
                .accessibilityIdentifier("pl.invoice.settings.delete")
            NavigationLink(plString("purchase.invoice.proof")) { PurchaseTransactionsView(workspace: workspace, mode: .proof) }
                .accessibilityIdentifier("pl.invoice.settings.proof")
        }
        .navigationTitle(plString("purchase.invoice.settings.menu"))
        .onAppear { workspace.completed("pl.invoice.settings.menu") }
    }
}

private struct PurchaseInvoiceSettingsForm: View {
    let workspace: Workspace
    @State private var settings: PurchaseLedger.InvoiceSettings
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace) {
        self.workspace = workspace
        _settings = State(initialValue: PurchaseLedger(workspace.context).invoiceSettings())
    }

    var body: some View {
        Form {
            TextField(plString("purchase.invoice.settings.nextFolio"), value: $settings.nextFolio, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .accessibilityIdentifier("pl.invoice.settings.nextFolio")
            if let account = Binding($settings.vatAccount) {
                TextField(plString("purchase.invoice.settings.vatAccount"), value: account, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("pl.invoice.settings.vatAccount")
            }
            Button(plString("purchase.action.save"), action: save)
                .accessibilityIdentifier("pl.invoice.settings.save")
        }
        .navigationTitle(plString("purchase.invoice.settings"))
        .purchaseAlert($error)
        .onAppear { workspace.completed("pl.invoice.settings.screen") }
    }

    private func save() {
        do {
            try PurchaseLedger(workspace.context).saveInvoiceSettings(settings)
            workspace.completed("pl.invoice.settings.save")
            dismiss()
        } catch { self.error = PurchaseNotice(error) }
    }
}
