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
    @State private var nextFolio = ""
    @State private var vatAccount: String?
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField(plString("purchase.invoice.settings.nextFolio"), text: $nextFolio)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("pl.invoice.settings.nextFolio")
            } footer: {
                Text(plString("purchase.invoice.settings.nextFolio.help"))
            }
            if let account = Binding($vatAccount) {
                TextField(plString("purchase.invoice.settings.vatAccount"), text: account)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("pl.invoice.settings.vatAccount")
            }
            Button(plString("purchase.action.save"), action: save)
                .accessibilityIdentifier("pl.invoice.settings.save")
        }
        .navigationTitle(plString("purchase.invoice.settings"))
        .purchaseAlert($error)
        .onAppear {
            let settings = PurchaseLedger(workspace.context).invoiceSettings()
            nextFolio = String(settings.nextFolio)
            vatAccount = settings.vatAccount.map { String($0) }
            workspace.completed("pl.invoice.settings.screen")
        }
    }

    private func save() {
        do {
            let ledger = PurchaseLedger(workspace.context)
            guard let folio = Int64(nextFolio) else { throw PurchaseLedger.Error.invalidInvoiceSettings }
            var settings = ledger.invoiceSettings()
            settings.nextFolio = folio
            settings.vatAccount = vatAccount.flatMap { Int64($0) }
            try ledger.saveInvoiceSettings(settings)
            workspace.completed("pl.invoice.settings.save")
            dismiss()
        } catch { self.error = PurchaseNotice(error) }
    }
}
