import ACASCore
import SwiftUI

struct PurchaseTransactionsView: View {
    enum Mode {
        case edit, delete, proof, post
        var title: String {
            switch self {
            case .edit: plString("pl.invoice.edit")
            case .delete: plString("pl.invoice.delete")
            case .proof: plString("pl.invoice.proof")
            case .post: plString("pl.invoice.post")
            }
        }
    }

    let workspace: Workspace
    let mode: Mode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var rows: [PurchaseLedger.Transaction] = []
    @State private var selection: PurchaseLedger.Transaction?
    @State private var error: PurchaseNotice?
    @State private var confirm = false
    @State private var edited = false
    @State private var generated = false
    @State private var confirmPosting = false

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .proof || mode == .post {
                HStack {
                    Spacer()
                    if mode == .proof {
                        Button(plString("pl.report.generate"), systemImage: "doc.badge.plus") {
                            do {
                                rows = try ledger.purchaseProof()
                                generated = true
                                workspace.completed("pl.transaction.proof")
                            } catch { self.error = PurchaseNotice(error) }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("pl.proof.generate")
                    } else {
                        Button(plString("pl.invoice.post.start"), systemImage: "checkmark.circle") { confirmPosting = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(rows.isEmpty || generated)
                            .accessibilityIdentifier("pl.post.start")
                    }
                    if let bytes = workspace.context.store.readRaw(PurchaseLedger.reportPath), generated {
                        ShareLink(item: Data(bytes), preview: SharePreview(plString("pl.report.original")))
                    }
                }.padding()
            }
            if mode == .proof && !generated {
                ContentUnavailableView(plString("pl.invoice.proof"), systemImage: "doc.text",
                                       description: Text(plString("pl.invoice.proof.description")))
            } else if horizontalSizeClass == .compact && (mode == .edit || mode == .delete) {
                List(rows) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(String(row.id))
                            Text(row.supplier).foregroundStyle(.secondary)
                        }
                        Spacer()
                        action(for: row)
                    }
                }
                .accessibilityIdentifier("pl.transactions.table")
            } else {
                Table(rows) {
                    TableColumn(plString("pl.invoice.number")) { Text(String($0.id)) }
                    TableColumn(plString("pl.invoice.date")) { Text($0.date.formatted(.dateTime.year().month().day())) }
                    TableColumn(plString("pl.supplier.code"), value: \.supplier)
                    TableColumn(plString("pl.invoice.type")) { Text($0.type.japaneseTitle) }
                    TableColumn(plString("pl.invoice.net")) { row in
                        Text(purchaseAmount(amounts(for: row).net))
                    }
                    TableColumn(plString("pl.invoice.tax")) { row in
                        Text(purchaseAmount(amounts(for: row).tax))
                    }
                    TableColumn(plString("pl.invoice.state")) { row in
                        if mode == .edit || mode == .delete {
                            action(for: row)
                        } else {
                            Text(row.posted ? plString("pl.invoice.posted") : plString("pl.invoice.pending"))
                        }
                    }
                }
                .accessibilityIdentifier("pl.transactions.table")
            }
        }
        .navigationTitle(mode.title)
        .onAppear {
            if mode != .proof { rows = ledger.transactions().filter { !$0.posted } }
        }
        .navigationDestination(isPresented: $edited) {
            if let selection { PurchaseTransactionForm(workspace: workspace, transaction: selection) }
        }
        .confirmationDialog(plString("pl.invoice.delete.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(plString("pl.action.delete"), role: .destructive, action: remove)
            Button(plString("pl.action.cancel"), role: .cancel) {}
        }
        .confirmationDialog(plString("pl.invoice.post.confirm"), isPresented: $confirmPosting, titleVisibility: .visible) {
            Button(plString("pl.action.post")) {
                do {
                    rows = try ledger.postTransactions()
                    generated = true
                    workspace.completed("pl.transaction.post")
                } catch { self.error = PurchaseNotice(error) }
            }
            .accessibilityIdentifier("pl.post.confirm")
            Button(plString("pl.action.cancel"), role: .cancel) {}
        }
        .purchaseAlert($error)
    }

    private func amounts(for row: PurchaseLedger.Transaction) -> (net: Int64, tax: Int64) {
        if mode == .post, let amounts = ledger.postingAmounts(for: row.id) { return amounts }
        let sign: Int64 = mode == .proof && row.type == .creditNote ? -1 : 1
        return (sign * row.lines.reduce(row.carriage) { $0 + $1.net },
                sign * row.lines.reduce(row.carriageTax ?? 0) { $0 + ($1.tax ?? 0) })
    }

    private func action(for row: PurchaseLedger.Transaction) -> some View {
        Button(mode == .edit ? plString("pl.action.edit") : plString("pl.action.delete"),
               role: mode == .delete ? .destructive : nil) {
            selection = row
            if mode == .edit { edited = true } else { confirm = true }
        }
        .buttonStyle(.borderless)
    }

    private func remove() {
        guard let selection else { return }
        do {
            try ledger.removeTransaction(number: selection.id)
            rows.removeAll { $0.id == selection.id }
            workspace.completed("pl.transaction.delete")
        } catch { self.error = PurchaseNotice(error) }
    }
}

struct PurchaseTransactionForm: View {
    let workspace: Workspace
    @State var transaction: PurchaseLedger.Transaction
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, transaction: PurchaseLedger.Transaction) {
        self.workspace = workspace
        self._transaction = State(initialValue: transaction)
    }

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        Form {
            Section(plString("pl.invoice.detail")) {
                DatePicker(plString("pl.invoice.date"), selection: $transaction.date, displayedComponents: .date)
                TextField(plString("pl.supplier.code.full"), text: $transaction.supplier)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pl.invoice.supplier")
                Button(plString("pl.supplier.verify")) { confirmSupplier() }
                    .accessibilityIdentifier("pl.invoice.supplier.check")
                TextField(plString("pl.invoice.order"), text: $transaction.order)
                    .accessibilityIdentifier("pl.invoice.order")
                TextField(plString("pl.invoice.reference"), text: $transaction.reference)
                    .accessibilityIdentifier("pl.invoice.reference")
                Picker(plString("pl.invoice.type"), selection: $transaction.type) {
                    ForEach(PurchaseLedger.TransactionType.allCases) { Text($0.japaneseTitle).tag($0) }
                }
                if transaction.type == .creditNote {
                    TextField(plString("pl.invoice.original"), value: $transaction.creditReference, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }
            }
            ForEach(transaction.lines.indices, id: \.self) { i in
                Section(String(format: plString("pl.invoice.line.title"), i + 1)) {
                    TextField(plString("pl.analysis.code"), text: $transaction.lines[i].code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pl.invoice.line.\(i).code")
                    currency(plString("pl.invoice.netAmount"), Binding(
                        get: { transaction.lines[i].net },
                        set: {
                            if $0 != transaction.lines[i].net { transaction.lines[i].tax = nil }
                            transaction.lines[i].net = $0
                        }
                    ))
                        .accessibilityIdentifier("pl.invoice.line.\(i).net")
                    Picker(plString("pl.invoice.taxCode"), selection: Binding(
                        get: { transaction.lines[i].taxCode },
                        set: {
                            if $0 != transaction.lines[i].taxCode { transaction.lines[i].tax = nil }
                            transaction.lines[i].taxCode = $0
                        }
                    )) {
                        Text(plString("pl.invoice.taxCode.none")).tag(Int64(0))
                        ForEach(Int64(1)...3, id: \.self) { Text(String(format: plString("pl.invoice.taxCode.value"), Int($0))).tag($0) }
                    }
                    LabeledContent(plString("pl.invoice.tax"), value: purchaseAmount(
                        transaction.lines[i].tax ?? ledger.tax(net: transaction.lines[i].net, code: transaction.lines[i].taxCode)))
                    if transaction.lines.count > 1 {
                        Button(plString("pl.invoice.line.delete"), role: .destructive) { transaction.lines.remove(at: i) }
                    }
                }
            }
            Button(plString("pl.invoice.line.add"), systemImage: "plus") { transaction.lines.append(.init()) }
                .disabled(transaction.lines.count >= 40)
            Section(plString("pl.invoice.additional")) {
                currency(plString("pl.invoice.carriage"), Binding(
                    get: { transaction.carriage },
                    set: {
                        if $0 != transaction.carriage { transaction.carriageTax = nil }
                        transaction.carriage = $0
                    }
                ))
                LabeledContent(plString("pl.invoice.carriageTax"), value: purchaseAmount(
                    transaction.carriageTax ?? ledger.tax(net: transaction.carriage, code: 1)))
                currency(plString("pl.invoice.deduction"), $transaction.deduction)
                TextField(plString("pl.invoice.deductionDays"), value: $transaction.deductionDays, format: .number)
            }
            Button(plString("pl.action.save"), action: save)
                .accessibilityIdentifier("pl.invoice.save")
        }
        .navigationTitle(transaction.number == nil ? plString("pl.invoice.add") : plString("pl.invoice.edit"))
        .onAppear { workspace.completed("pl.transaction.screen") }
        .purchaseAlert($error)
    }

    private func currency(_ title: String, _ value: Binding<Int64>) -> some View {
        TextField(title, value: Binding(
            get: { Decimal(value.wrappedValue) / 100 },
            set: {
                if $0 >= 0, $0 < 10_000_000 {
                    value.wrappedValue = NSDecimalNumber(decimal: $0 * 100).int64Value
                }
            }
        ), format: .number.grouping(.never))
        .keyboardType(.decimalPad)
    }

    private func confirmSupplier() {
        do {
            let supplier = try ledger.supplier(code: transaction.supplier)
            transaction.supplier = supplier.code
        } catch {
            self.error = PurchaseNotice(error)
            workspace.completed("pl.transaction.reject")
        }
    }

    private func save() {
        do {
            try ledger.saveTransaction(transaction)
            workspace.completed("pl.transaction.save")
            dismiss()
        } catch {
            self.error = PurchaseNotice(error)
            if case PurchaseLedger.Error.supplierNotFound = error { workspace.completed("pl.transaction.reject") }
        }
    }
}

extension PurchaseLedger.TransactionType {
    var japaneseTitle: String {
        switch self {
        case .receipt: plString("pl.invoice.type.receipt")
        case .invoice: plString("pl.invoice.type.invoice")
        case .creditNote: plString("pl.invoice.type.credit")
        }
    }
}
