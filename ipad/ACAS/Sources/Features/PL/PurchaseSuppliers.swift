import ACASCore
import SwiftUI

struct PurchaseSupplierMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(plString("purchase.supplier.add")) {
                PurchaseSupplierForm(workspace: workspace, supplier: PurchaseLedger(workspace.context).newSupplier, creating: true)
            }
            .accessibilityIdentifier("pl.supplier.add")
            NavigationLink(plString("purchase.supplier.edit")) { PurchaseSupplierLookup(workspace: workspace, mode: .edit) }
                .accessibilityIdentifier("pl.supplier.edit")
            NavigationLink(plString("purchase.supplier.delete")) { PurchaseSupplierLookup(workspace: workspace, mode: .delete) }
                .accessibilityIdentifier("pl.supplier.delete")
            NavigationLink(plString("purchase.supplier.show")) { PurchaseSupplierLookup(workspace: workspace, mode: .show) }
                .accessibilityIdentifier("pl.supplier.show")
        }
        .navigationTitle(plString("purchase.supplier.menu"))
        .onAppear { workspace.completed("pl.suppliers") }
    }
}

struct PurchaseSupplierLookup: View {
    enum Mode {
        case edit, delete, show, enquiry

        var title: String {
            switch self {
            case .edit: plString("purchase.supplier.edit")
            case .delete: plString("purchase.supplier.delete")
            case .show: plString("purchase.supplier.show")
            case .enquiry: plString("purchase.enquiry")
            }
        }
    }

    let workspace: Workspace
    let mode: Mode
    @State private var code = ""
    @State private var supplier: PurchaseLedger.Supplier?
    @State private var error: PurchaseNotice?
    @State private var confirm = false
    @State private var deactivate = false
    @State private var edit = false

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        Form {
            Section(plString("purchase.supplier.search")) {
                TextField(plString("purchase.supplier.code.full"), text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pl.supplier.search.code")
                    .onSubmit(search)
                Button(plString("purchase.action.search"), action: search)
                    .disabled(code.isEmpty)
                    .accessibilityIdentifier("pl.supplier.search")
            }
            if let supplier {
                Section(plString("purchase.supplier.detail")) {
                    LabeledContent(plString("purchase.supplier.name"), value: supplier.name)
                        .accessibilityIdentifier("pl.supplier.result")
                    let address = ledger.supplierAddressLines(supplier)
                    LabeledContent(plString("purchase.supplier.address"), value: [address.first, address.second].filter { !$0.isEmpty }.joined(separator: " "))
                    LabeledContent(plString("purchase.supplier.telephone"), value: supplier.telephone)
                    LabeledContent(plString("purchase.supplier.balance"), value: purchaseAmount(supplier.currentBalance))
                    LabeledContent(plString("purchase.supplier.unapplied"), value: purchaseAmount(supplier.unapplied))
                    if mode == .edit {
                        Button(plString("purchase.action.change")) { edit = true }
                            .accessibilityIdentifier("pl.supplier.edit.open")
                    }
                    if mode == .delete {
                        Button(plString("purchase.supplier.deactivate")) { deactivate = true; confirm = true }
                        Button(plString("purchase.action.delete"), role: .destructive) { deactivate = false; confirm = true }
                            .accessibilityIdentifier("pl.supplier.delete.open")
                    }
                }
                if mode == .enquiry {
                    Section(plString("purchase.enquiry.items")) {
                        ForEach(ledger.openItems(supplier: supplier.code)) { item in
                            LabeledContent(item.reference.isEmpty ? String(item.id) : item.reference,
                                           value: purchaseAmount(item.balance))
                        }
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationDestination(isPresented: $edit) {
            if let supplier {
                PurchaseSupplierForm(workspace: workspace, supplier: supplier, creating: false)
            }
        }
        .onAppear { if let supplier { self.supplier = try? ledger.supplier(code: supplier.code) } }
        .confirmationDialog(plString("purchase.supplier.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(plString("purchase.action.confirm"), role: deactivate ? nil : .destructive, action: remove)
                .accessibilityIdentifier("pl.supplier.delete.confirm")
            Button(plString("purchase.action.cancel"), role: .cancel) {}
        }
        .purchaseAlert($error)
    }

    private func search() {
        do { supplier = try ledger.supplier(code: code) }
        catch { supplier = nil; self.error = PurchaseNotice(error) }
        workspace.completed("pl.supplier.lookup")
    }

    private func remove() {
        guard let supplier else { return }
        do {
            try ledger.removeSupplier(code: supplier.code, deactivate: deactivate)
            self.supplier = deactivate ? try ledger.supplier(code: supplier.code) : nil
            workspace.completed("pl.supplier.delete")
        } catch { self.error = PurchaseNotice(error) }
    }
}

struct PurchaseSupplierForm: View {
    let workspace: Workspace
    let creating: Bool
    @State var supplier: PurchaseLedger.Supplier
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, supplier: PurchaseLedger.Supplier, creating: Bool) {
        self.workspace = workspace
        self.creating = creating
        var fields = supplier
        let address = PurchaseLedger(workspace.context).supplierAddressLines(supplier)
        fields.address1 = address.first
        fields.address2 = address.second
        self._supplier = State(initialValue: fields)
    }

    var body: some View {
        Form {
            Section(plString("purchase.supplier.base")) {
                if creating {
                    TextField(plString("purchase.supplier.code.short"), text: $supplier.code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pl.supplier.code")
                } else {
                    LabeledContent(plString("purchase.supplier.code"), value: supplier.code)
                }
                TextField(plString("purchase.supplier.name"), text: $supplier.name)
                    .accessibilityIdentifier("pl.supplier.name")
                TextField(plString("purchase.supplier.address.one"), text: $supplier.address1)
                    .accessibilityIdentifier("pl.supplier.address")
                TextField(plString("purchase.supplier.address.two"), text: $supplier.address2)
                TextField(plString("purchase.supplier.telephone"), text: $supplier.telephone)
                TextField(plString("purchase.supplier.extension"), text: $supplier.extensionNumber)
                TextField(plString("purchase.supplier.fax"), text: $supplier.fax)
                TextField(plString("purchase.supplier.email"), text: $supplier.email)
                    .keyboardType(.emailAddress)
            }
            Section(plString("purchase.supplier.payment")) {
                TextField(plString("purchase.supplier.bank"), value: $supplier.sortCode, format: .number.grouping(.never))
                TextField(plString("purchase.supplier.account"), value: $supplier.accountNumber, format: .number.grouping(.never))
                TextField(plString("purchase.supplier.paymentDays"), value: $supplier.paymentDays, format: .number)
                TextField(plString("purchase.supplier.limit"), value: $supplier.creditLimit, format: .number)
                TextField(plString("purchase.supplier.discount"), value: $supplier.discount, format: .number)
            }
            Section(plString("purchase.supplier.notes")) {
                TextField(plString("purchase.supplier.notes.one"), text: $supplier.note1)
                TextField(plString("purchase.supplier.notes.two"), text: $supplier.note2)
            }
            Button(plString("purchase.action.save"), action: save)
                .accessibilityIdentifier("pl.supplier.save")
        }
        .navigationTitle(creating ? plString("purchase.supplier.add") : plString("purchase.supplier.edit"))
        .purchaseAlert($error)
        .onAppear { workspace.completed(creating ? "pl.supplier.add.screen" : "pl.supplier.edit.screen") }
    }

    private func save() {
        do {
            try PurchaseLedger(workspace.context).saveSupplier(supplier, creating: creating, joiningAddressLines: true)
            workspace.completed(creating ? "pl.supplier.add" : "pl.supplier.edit")
            dismiss()
        } catch { self.error = PurchaseNotice(error) }
    }
}

struct PurchaseSuppliersView: View {
    let workspace: Workspace
    let byName: Bool

    var body: some View {
        Table(PurchaseLedger(workspace.context).suppliers(byName: byName)) {
            TableColumn(plString("purchase.supplier.code"), value: \.code)
            TableColumn(plString("purchase.supplier.name"), value: \.name)
            TableColumn(plString("purchase.supplier.balance")) { Text(purchaseAmount($0.currentBalance)) }
            TableColumn(plString("purchase.supplier.unapplied")) { Text(purchaseAmount($0.unapplied)) }
        }
        .navigationTitle(byName ? plString("purchase.supplier.alphabetical") : plString("purchase.supplier.list"))
    }
}
