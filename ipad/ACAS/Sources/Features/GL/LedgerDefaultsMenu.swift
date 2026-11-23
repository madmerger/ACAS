import ACASCore
import SwiftUI

struct LedgerDefaultsMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(ledgerText("defaults-add")) { LedgerDefaultsList(workspace: workspace, edit: true) }
                .accessibilityIdentifier("gl.defaults.add")
            NavigationLink(ledgerText("defaults-edit")) { LedgerDefaultsList(workspace: workspace, edit: true) }
                .accessibilityIdentifier("gl.defaults.edit")
            NavigationLink(ledgerText("defaults-list")) { LedgerDefaultsList(workspace: workspace, edit: false) }
                .accessibilityIdentifier("gl.defaults.list")
        }
        .navigationTitle(ledgerText("defaults"))
        .onAppear { workspace.completed("gl-defaults-menu") }
    }
}

private struct LedgerDefaultsList: View {
    let workspace: Workspace
    let edit: Bool
    @State private var accounts: [LedgerDefault] = []
    @State private var selected: LedgerDefault?

    var body: some View {
        List(accounts.prefix(32)) { entry in
            if edit {
                Button { selected = entry } label: { row(entry) }
                    .accessibilityIdentifier("gl.defaults.entry.\(entry.id)")
            } else {
                row(entry)
            }
        }
        .navigationTitle(ledgerText(edit ? "defaults-edit" : "defaults-list"))
        .onAppear {
            reload()
            if !edit { workspace.completed("gl-defaults-list") }
        }
        .sheet(item: $selected, onDismiss: reload) { entry in
            NavigationStack { LedgerDefaultEditor(workspace: workspace, entry: entry) }
        }
    }

    private func row(_ entry: LedgerDefault) -> some View {
        HStack {
            Text(String(entry.id)).monospacedDigit()
            Text(entry.account == "000000" ? ledgerText("not-set") : entry.account)
            Spacer()
            Text(entry.transactionCode)
        }
    }

    private func reload() { accounts = GeneralLedgerSetup(workspace.context).defaults }
}

private struct LedgerDefaultEditor: View {
    let workspace: Workspace
    let entry: LedgerDefault
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var transactionCode = ""
    @State private var tax = LedgerDefaultTax.noTax
    @State private var error: String?

    var body: some View {
        Form {
            TextField(ledgerText("account-code"), text: $account)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("gl.defaults.account")
            TextField(ledgerText("transaction-code"), text: $transactionCode)
                .accessibilityIdentifier("gl.defaults.code")
            Picker(ledgerText("tax"), selection: $tax) {
                ForEach(LedgerDefaultTax.allCases, id: \.self) { item in
                    Text(ledgerText("tax." + item.rawValue)).tag(item)
                }
            }
            Button(ledgerText("action.save"), action: save)
                .accessibilityIdentifier("gl.defaults.save")
            if let error { Text(error) }
        }
        .navigationTitle(ledgerText("defaults-edit"))
        .toolbar {
            Button("action.close") { dismiss() }
        }
        .onAppear {
            account = entry.account
            transactionCode = entry.transactionCode
            tax = entry.tax ?? .noTax
        }
    }

    private func save() {
        do {
            let exists = try GeneralLedgerSetup(workspace.context).saveDefault(number: entry.id, account: account,
                transactionCode: transactionCode, tax: tax)
            workspace.completed(exists ? "gl-defaults-save" : "gl-defaults-missing-account")
            if exists { dismiss() } else { error = ledgerText("default-account-missing") }
        } catch {
            self.error = ledgerText("default-invalid")
        }
    }
}
