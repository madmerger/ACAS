import ACASCore
import SwiftUI

struct PurchasePaymentForm: View {
    let workspace: Workspace
    @State private var payment: PurchaseLedger.Payment
    @State private var available: [PurchaseLedger.Allocation] = []
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace) {
        self.workspace = workspace
        _payment = State(initialValue: .init(date: PurchaseLedger(workspace.context).processingDate))
    }

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        Form {
            Section(plString("purchase.payment.details")) {
                Picker(plString("purchase.supplier.code"), selection: $payment.supplier) {
                    Text(plString("purchase.payment.selectSupplier")).tag("")
                    ForEach(ledger.suppliers(byName: true)) { supplier in
                        Text("\(supplier.code)  \(supplier.name)").tag(supplier.code)
                    }
                }
                .accessibilityIdentifier("pl.payment.supplier")
                DatePicker(plString("purchase.invoice.date"), selection: $payment.date, displayedComponents: .date)
                Toggle(plString("purchase.payment.useCredit"), isOn: $payment.credit)
                paymentCurrency(plString("purchase.payment.amount"), $payment.amount)
                    .accessibilityIdentifier("pl.payment.amount")
            }
            Section(plString("purchase.payment.allocation")) {
                Button(plString("purchase.payment.propose"), action: propose)
                    .disabled(payment.supplier.isEmpty || payment.amount == 0)
                    .accessibilityIdentifier("pl.payment.propose")
                ForEach(available) { invoice in
                    LabeledContent(plString("purchase.invoice.number"), value: String(invoice.id))
                    paymentCurrency(plString("purchase.payment.allocated"), allocation(for: invoice.id))
                        .accessibilityIdentifier("pl.payment.allocation.\(invoice.id)")
                }
                LabeledContent(plString("purchase.payment.unallocated"),
                               value: purchaseAmount(payment.amount - payment.allocated))
            }
            Button(plString("purchase.action.save"), action: save)
                .disabled(payment.supplier.isEmpty || payment.amount == 0)
                .accessibilityIdentifier("pl.payment.save")
        }
        .navigationTitle(plString("purchase.payment.add"))
        .purchaseAlert($error)
        .onChange(of: payment.supplier) { _, _ in clearAllocations() }
        .onChange(of: payment.date) { _, _ in clearAllocations() }
        .onChange(of: payment.amount) { _, _ in clearAllocations() }
        .onAppear { workspace.completed("pl.payment.add.screen") }
    }

    private func clearAllocations() {
        available = []
        payment.allocations = []
    }

    private func propose() {
        do {
            available = try ledger.proposedAllocations(supplier: payment.supplier, amount: .max, date: payment.date)
            payment.allocations = try ledger.proposedAllocations(supplier: payment.supplier, amount: payment.amount, date: payment.date)
        } catch { self.error = PurchaseNotice(error) }
    }

    private func allocation(for id: Int64) -> Binding<Int64> {
        Binding {
            payment.allocations.first { $0.id == id }?.amount ?? 0
        } set: { amount in
            let candidate = available.first { $0.id == id }
            payment.allocations.removeAll { $0.id == id }
            if amount > 0 {
                payment.allocations.append(.init(invoice: id, amount: amount,
                                                discount: candidate?.amount == amount ? candidate?.discount ?? 0 : 0))
            }
        }
    }

    private func save() {
        do {
            try ledger.savePayment(payment)
            workspace.completed("pl.payment.save")
            dismiss()
        } catch { self.error = PurchaseNotice(error) }
    }
}

struct PurchasePaymentsView: View {
    enum Mode: String {
        case edit, proof, post
        var title: String { plString("purchase.payment." + rawValue) }
    }

    let workspace: Workspace
    let mode: Mode
    @State private var rows: [PurchaseLedger.Payment] = []
    @State private var reversing: PurchaseLedger.Payment?
    @State private var confirmation = false
    @State private var generated = false
    @State private var error: PurchaseNotice?

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        List {
            if mode != .edit {
                if mode == .proof {
                    Button(plString("purchase.report.generate"), action: proof)
                        .disabled(rows.isEmpty)
                        .accessibilityIdentifier("pl.payment.proof.generate")
                } else {
                    Button(plString("purchase.action.post")) { confirmation = true }
                        .disabled(rows.isEmpty || generated)
                        .accessibilityIdentifier("pl.payment.post.start")
                }
                if generated, let bytes = workspace.context.store.readRaw(PurchaseLedger.reportPath) {
                    ShareLink(item: Data(bytes), preview: SharePreview(plString("purchase.report.original")))
                }
            }
            ForEach(rows) { payment in
                Section {
                    LabeledContent(plString("purchase.payment.amount"), value: purchaseAmount(payment.amount))
                        .accessibilityIdentifier("pl.payment.pending.amount.\(payment.id)")
                        .accessibilityValue(purchaseAmount(payment.amount))
                    LabeledContent(plString("purchase.payment.allocated"), value: purchaseAmount(payment.allocated))
                    LabeledContent(plString("purchase.invoice.deduction"), value: purchaseAmount(payment.discount))
                    if mode == .edit {
                        Button(plString("purchase.payment.reverse"), role: .destructive) { reversing = payment }
                            .accessibilityIdentifier("pl.payment.cancel.\(payment.number ?? 0)")
                    }
                } header: {
                    Text("\(payment.supplier)  \(payment.number ?? 0)  \(payment.date.formatted(.dateTime.year().month().day()))")
                }
            }
        }
        .navigationTitle(mode.title)
        .onAppear {
            rows = ledger.pendingPayments()
            workspace.completed("pl.payment.\(mode.rawValue).screen")
        }
        .sheet(item: $reversing) { payment in
            NavigationStack {
                PurchasePaymentCancellation(workspace: workspace, payment: payment) { rows = ledger.pendingPayments() }
            }
        }
        .confirmationDialog(plString("purchase.payment.post.confirm"), isPresented: $confirmation, titleVisibility: .visible) {
            Button(plString("purchase.action.post"), action: post)
                .accessibilityIdentifier("pl.payment.post.confirm")
            Button(plString("purchase.action.cancel"), role: .cancel) {}
        }
        .purchaseAlert($error)
    }

    private func proof() {
        do {
            rows = try ledger.proofPayments()
            generated = !rows.isEmpty
            workspace.completed("pl.payment.proof")
        } catch { self.error = PurchaseNotice(error) }
    }

    private func post() {
        do {
            rows = try ledger.postPayments()
            generated = true
            workspace.completed("pl.payment.post")
        } catch { self.error = PurchaseNotice(error) }
    }
}

private struct PurchasePaymentCancellation: View {
    let workspace: Workspace
    let payment: PurchaseLedger.Payment
    let refresh: () -> Void
    @State private var restoring: [Int64: Int64] = [:]
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if payment.discount > 0 {
                Section(plString("purchase.payment.restoreDiscount")) {
                    LabeledContent(plString("purchase.invoice.deduction"), value: purchaseAmount(payment.discount))
                    ForEach(payment.allocations) { allocation in
                        paymentCurrency(String(allocation.id), Binding(
                            get: { restoring[allocation.id] ?? 0 },
                            set: { restoring[allocation.id] = $0 }
                        ))
                    }
                }
            }
            Button(plString("purchase.payment.reverse"), role: .destructive, action: cancel)
                .accessibilityIdentifier("pl.payment.cancel.confirm")
        }
        .navigationTitle(plString("purchase.payment.reverse"))
        .toolbar { Button(plString("purchase.action.close")) { dismiss() } }
        .purchaseAlert($error)
    }

    private func cancel() {
        guard let number = payment.number else { return }
        do {
            try PurchaseLedger(workspace.context).cancelPayment(
                supplier: payment.supplier, number: number, restoringDiscounts: restoring.filter { $0.value != 0 }
            )
            workspace.completed("pl.payment.cancel")
            refresh()
            dismiss()
        } catch { self.error = PurchaseNotice(error) }
    }
}

private func paymentCurrency(_ title: String, _ value: Binding<Int64>) -> some View {
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
