import ACASCore
import SwiftUI

struct PurchaseTransactionsView: View {
    enum Mode {
        case edit, delete, proof, post
        var title: String {
            switch self {
            case .edit: plString("purchase.invoice.edit")
            case .delete: plString("purchase.invoice.delete")
            case .proof: plString("purchase.invoice.proof")
            case .post: plString("purchase.invoice.post")
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
                        Button(plString("purchase.report.generate"), systemImage: "doc.badge.plus") {
                            do {
                                rows = try ledger.purchaseProof()
                                generated = true
                                workspace.completed("pl.transaction.proof")
                            } catch { self.error = PurchaseNotice(error) }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("pl.proof.generate")
                    } else {
                        Button(plString("purchase.invoice.post.start"), systemImage: "checkmark.circle") { confirmPosting = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(rows.isEmpty || generated)
                            .accessibilityIdentifier("pl.post.start")
                    }
                    if let bytes = workspace.context.store.readRaw(PurchaseLedger.reportPath), generated {
                        ShareLink(item: Data(bytes), preview: SharePreview(plString("purchase.report.original")))
                    }
                }.padding()
            }
            if mode == .proof && !generated {
                ContentUnavailableView(plString("purchase.invoice.proof"), systemImage: "doc.text",
                                       description: Text(plString("purchase.invoice.proof.description")))
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
                    TableColumn(plString("purchase.invoice.number")) {
                        Text(String($0.id)).accessibilityIdentifier("pl.transaction.number")
                    }
                    TableColumn(plString("purchase.invoice.date")) { Text($0.date.formatted(.dateTime.year().month().day())) }
                    TableColumn(plString("purchase.supplier.code")) { row in
                        Text(row.supplier).accessibilityIdentifier("pl.transaction.\(row.id).supplier")
                    }
                    TableColumn(plString("purchase.invoice.type")) { row in
                        Text(row.type.japaneseTitle).accessibilityIdentifier("pl.transaction.\(row.id).type")
                    }
                    TableColumn(plString("purchase.invoice.net")) { row in
                        Text(purchaseAmount(amounts(for: row).net))
                            .accessibilityIdentifier("pl.transaction.\(row.id).net")
                    }
                    TableColumn(plString("purchase.invoice.tax")) { row in
                        Text(purchaseAmount(amounts(for: row).tax))
                            .accessibilityIdentifier("pl.transaction.\(row.id).tax")
                    }
                    TableColumn(plString("purchase.invoice.state")) { row in
                        if mode == .edit || mode == .delete {
                            action(for: row)
                        } else {
                            Text(row.posted ? plString("purchase.invoice.posted") : plString("purchase.invoice.pending"))
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
        .confirmationDialog(plString("purchase.invoice.delete.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(plString("purchase.action.delete"), role: .destructive, action: remove)
            Button(plString("purchase.action.cancel"), role: .cancel) {}
        }
        .confirmationDialog(plString("purchase.invoice.post.confirm"), isPresented: $confirmPosting, titleVisibility: .visible) {
            Button(plString("purchase.action.post")) {
                do {
                    rows = try ledger.postTransactions()
                    generated = true
                    workspace.completed("pl.transaction.post")
                } catch { self.error = PurchaseNotice(error) }
            }
            .accessibilityIdentifier("pl.post.confirm")
            Button(plString("purchase.action.cancel"), role: .cancel) {}
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
        Button(mode == .edit ? plString("purchase.action.edit") : plString("purchase.action.delete"),
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
            Section(plString("purchase.invoice.detail")) {
                if transaction.number == nil && ledger.invoiceSettings().nextFolio > 99_999_999 {
                    LabeledContent(plString("purchase.invoice.number"), value: Cobol.z(ledger.nextTransactionFolio, 8))
                        .accessibilityIdentifier("pl.invoice.nextFolio")
                }
                DatePicker(plString("purchase.invoice.date"), selection: $transaction.date, displayedComponents: .date)
                TextField(plString("purchase.supplier.code.full"), text: $transaction.supplier)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pl.invoice.supplier")
                Button(plString("purchase.supplier.verify")) { confirmSupplier() }
                    .accessibilityIdentifier("pl.invoice.supplier.check")
                TextField(plString("purchase.invoice.order"), text: $transaction.order)
                    .accessibilityIdentifier("pl.invoice.order")
                TextField(plString("purchase.invoice.reference"), text: $transaction.reference)
                    .accessibilityIdentifier("pl.invoice.reference")
                Picker(plString("purchase.invoice.type"), selection: $transaction.type) {
                    ForEach(PurchaseLedger.TransactionType.allCases) { Text($0.japaneseTitle).tag($0) }
                }
                if transaction.type == .creditNote {
                    TextField(plString("purchase.invoice.original"), value: $transaction.creditReference, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }
            }
            ForEach(transaction.lines.indices, id: \.self) { i in
                Section(String(format: plString("purchase.invoice.line.title"), i + 1)) {
                    TextField(plString("purchase.analysis.code"), text: $transaction.lines[i].code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pl.invoice.line.\(i).code")
                    currency(plString("purchase.invoice.netAmount"), Binding(
                        get: { transaction.lines[i].net },
                        set: {
                            if $0 != transaction.lines[i].net { transaction.lines[i].tax = nil }
                            transaction.lines[i].net = $0
                        }
                    ))
                        .accessibilityIdentifier("pl.invoice.line.\(i).net")
                    Picker(plString("purchase.invoice.taxCode"), selection: Binding(
                        get: { transaction.lines[i].taxCode },
                        set: {
                            if $0 != transaction.lines[i].taxCode { transaction.lines[i].tax = nil }
                            transaction.lines[i].taxCode = $0
                        }
                    )) {
                        Text(plString("purchase.invoice.taxCode.none")).tag(Int64(0))
                        ForEach(Int64(1)...3, id: \.self) { Text(String(format: plString("purchase.invoice.taxCode.value"), Int($0))).tag($0) }
                    }
                    LabeledContent(plString("purchase.invoice.tax"), value: purchaseAmount(
                        transaction.lines[i].tax ?? ledger.tax(net: transaction.lines[i].net, code: transaction.lines[i].taxCode)))
                    if transaction.lines.count > 1 {
                        Button(plString("purchase.invoice.line.delete"), role: .destructive) { transaction.lines.remove(at: i) }
                    }
                }
            }
            Button(plString("purchase.invoice.line.add"), systemImage: "plus") { transaction.lines.append(.init()) }
                .disabled(transaction.lines.count >= 40)
            Section(plString("purchase.invoice.additional")) {
                currency(plString("purchase.invoice.carriage"), Binding(
                    get: { transaction.carriage },
                    set: {
                        if $0 != transaction.carriage { transaction.carriageTax = nil }
                        transaction.carriage = $0
                    }
                ))
                LabeledContent(plString("purchase.invoice.carriageTax"), value: purchaseAmount(
                    transaction.carriageTax ?? ledger.tax(net: transaction.carriage, code: 1)))
                currency(plString("purchase.invoice.deduction"), $transaction.deduction)
                TextField(plString("purchase.invoice.deductionDays"), value: $transaction.deductionDays, format: .number)
            }
            Button(plString("purchase.action.save"), action: save)
                .accessibilityIdentifier("pl.invoice.save")
        }
        .navigationTitle(transaction.number == nil ? plString("purchase.invoice.add") : plString("purchase.invoice.edit"))
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
        case .receipt: plString("purchase.invoice.type.receipt")
        case .invoice: plString("purchase.invoice.type.invoice")
        case .creditNote: plString("purchase.invoice.type.credit")
        }
    }
}
