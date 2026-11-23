import ACASCore
import SwiftUI

struct SalesPaymentsView: View {
    let workspace: Workspace
    @State private var date = Date()
    @State private var customer = ""
    @State private var amount = ""
    @State private var usesUnapplied = false
    @State private var invoices: [SalesPayments.Allocation] = []
    @State private var allocations: [Int64: String] = [:]
    @State private var acceptsDeduction: Set<Int64> = []
    @State private var queue: [SalesPayments.Draft] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var savedBatch: Int64?

    private var service: SalesPayments { SalesPayments(workspace.context) }

    var body: some View {
        Form {
            Section {
                DatePicker(slText("sales.payment.date"), selection: $date, displayedComponents: .date)
                TextField(slText("sales.customer.code.existing"), text: $customer)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("sales.payment.customer")
                TextField(slText("sales.payment.amount"), text: $amount)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("sales.payment.amount")
                Toggle(slText("sales.payment.useUnapplied"), isOn: $usesUnapplied)
                Button(slText("sales.payment.findInvoices"), action: loadInvoices)
                    .accessibilityIdentifier("sales.payment.findInvoices")
            }
            if loaded {
                Section(slText("sales.payment.allocations")) {
                    ForEach(invoices) { invoice in
                        LabeledContent(String(invoice.invoice), value: money(invoice.outstanding))
                        if invoice.earlyPaymentDeduction != 0 {
                            LabeledContent(slText("sales.payment.deduction"), value: money(invoice.earlyPaymentDeduction))
                        } else {
                            Toggle(slText("sales.payment.acceptDeduction"), isOn: Binding(
                                get: { acceptsDeduction.contains(invoice.id) },
                                set: { if $0 { acceptsDeduction.insert(invoice.id) } else { acceptsDeduction.remove(invoice.id) } }
                            ))
                        }
                        TextField(slText("sales.payment.allocationAmount"), text: Binding(
                            get: { allocations[invoice.id, default: ""] },
                            set: { allocations[invoice.id] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("sales.payment.allocation.\(invoice.id)")
                    }
                    Button(slText("sales.payment.add"), action: enqueue)
                        .accessibilityIdentifier("sales.payment.add")
                }
            }
            if !queue.isEmpty {
                Section(slText("sales.payment.batch")) {
                    ForEach(queue.indices, id: \.self) { index in
                        LabeledContent(queue[index].customer, value: money(queue[index].amount))
                    }
                    .onDelete { queue.remove(atOffsets: $0) }
                    Button(slText("sales.payment.save"), action: save)
                        .accessibilityIdentifier("sales.payment.save")
                }
            }
            if let savedBatch {
                LabeledContent(slText("sales.payment.saved"), value: String(savedBatch))
                    .accessibilityIdentifier("sales.payment.saved")
            }
        }
        .navigationTitle(slText("sales.payment.entry"))
        .onChange(of: customer) { _, _ in resetAllocations() }
        .onChange(of: date) { _, _ in resetAllocations() }
        .alert(slText("sales.payment.failed"), isPresented: $failed) {
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    private func loadInvoices() {
        do {
            invoices = try service.allocations(customer: customer, date: date)
            loaded = true
        } catch {
            resetAllocations()
            failed = true
        }
    }

    private func enqueue() {
        guard let total = Self.parse(amount), total > 0 else { failed = true; return }
        var draft = SalesPayments.Draft(date: date)
        draft.customer = customer
        draft.amount = total
        draft.useUnappliedBalance = usesUnapplied
        draft.acceptExpiredDeduction = acceptsDeduction
        for (invoice, text) in allocations where !text.isEmpty {
            guard let value = Self.parse(text) else { failed = true; return }
            draft.allocations[invoice] = value
        }
        queue.append(draft)
        customer = ""
        amount = ""
        usesUnapplied = false
        resetAllocations()
    }

    private func save() {
        do {
            savedBatch = try service.saveBatch(queue)
            queue.removeAll()
            workspace.completed("sales-payment-entry")
        } catch {
            failed = true
        }
    }

    private func resetAllocations() {
        loaded = false
        invoices = []
        allocations = [:]
        acceptsDeduction = []
    }

    fileprivate static func parse(_ text: String) -> Int64? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let major = parts.first, (1...7).contains(major.count),
              major.utf8.allSatisfy({ (48...57).contains($0) }), let whole = Int64(major) else { return nil }
        guard parts.count == 2 else { return whole * 100 }
        let minor = parts[1]
        guard (1...2).contains(minor.count), minor.utf8.allSatisfy({ (48...57).contains($0) }),
              let fraction = Int64(minor) else { return nil }
        return whole * 100 + fraction * (minor.count == 1 ? 10 : 1)
    }

    private func money(_ value: Int64) -> String {
        (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
    }
}

struct SalesPaymentAmendView: View {
    let workspace: Workspace
    @State private var entries: [SalesPayments.Pending] = []
    @State private var selected: SalesPayments.Pending?
    @State private var deductions: [Int64: String] = [:]
    @State private var failed = false
    @State private var cancelled = false

    private var service: SalesPayments { SalesPayments(workspace.context) }

    var body: some View {
        List {
            if cancelled {
                Text(slText("sales.payment.cancelled")).accessibilityIdentifier("sales.payment.cancelled")
            }
            if entries.isEmpty {
                Text(slText("sales.payment.none"))
            }
            ForEach(entries) { entry in
                Button { deductions = [:]; selected = entry } label: {
                    SalesPaymentRow(entry: entry)
                }
                .accessibilityIdentifier("sales.payment.amend.\(entry.id)")
            }
        }
        .navigationTitle(slText("sales.payment.amend"))
        .onAppear(perform: load)
        .sheet(item: $selected) { payment in
            NavigationStack {
                Form {
                    SalesPaymentRow(entry: payment)
                    if payment.deduction > 0 {
                        LabeledContent(slText("sales.payment.restoreTotal"), value: paymentMoney(payment.deduction))
                        ForEach(service.restorableInvoices(payment), id: \.self) { invoice in
                            TextField(String(invoice), text: Binding(
                                get: { deductions[invoice, default: ""] },
                                set: { deductions[invoice] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                        }
                    }
                    Button(slText("sales.payment.reverse"), role: .destructive) { reverse(payment) }
                        .accessibilityIdentifier("sales.payment.reverse")
                }
                .navigationTitle(slText("sales.payment.amend"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(slText("sales.action.cancel")) { selected = nil }
                    }
                }
                .alert(slText("sales.payment.failed"), isPresented: $failed) {
                    Button(slText("sales.action.cancel"), role: .cancel) {}
                }
            }
        }
    }

    private func load() {
        do { entries = try service.pending() }
        catch { failed = true }
    }

    private func reverse(_ payment: SalesPayments.Pending) {
        do {
            var amounts: [Int64: Int64] = [:]
            for (invoice, text) in deductions where !text.isEmpty {
                guard let amount = SalesPaymentsView.parse(text) else { throw SalesPayments.Error.invalidInput }
                amounts[invoice] = amount
            }
            try service.cancel(payment, restoring: amounts)
            selected = nil
            cancelled = true
            load()
            workspace.completed("sales-payment-amend")
        } catch {
            failed = true
        }
    }
}

struct SalesPaymentProofView: View {
    let workspace: Workspace
    @State private var entries: [SalesPayments.Pending]?
    @State private var document: SalesReportDocument?
    @State private var failed = false

    var body: some View {
        List {
            Button(slText("sales.action.generate"), action: generate)
                .accessibilityIdentifier("sales.payment.proof.generate")
            if let entries {
                ForEach(entries) { entry in
                    SalesPaymentRow(entry: entry).accessibilityIdentifier("sales.payment.proof.\(entry.id)")
                }
                if entries.isEmpty { Text(slText("sales.payment.none")) }
            }
        }
        .navigationTitle(slText("sales.payment.proof"))
        .toolbar {
            if let document {
                ToolbarItem(placement: .primaryAction) {
                    SalesReportExport(report: document, identifier: "sales.payment.proof.export",
                                      filename: slText("sales.payment.proof.filename"))
                }
            }
        }
        .alert(slText("sales.payment.failed"), isPresented: $failed) {
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    private func generate() {
        do {
            entries = try SalesPaymentProof(workspace.context).generate()
            document = workspace.context.store.readRaw(SalesPaymentProof.exportPath).map(SalesReportDocument.init)
            workspace.completed("sales-payment-proof")
        } catch {
            failed = true
        }
    }
}

private struct SalesPaymentRow: View {
    let entry: SalesPayments.Pending

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(entry.customer, value: paymentMoney(entry.amount))
            LabeledContent(slText(entry.journal ? "sales.payment.journal" : "sales.payment.batchNumber"),
                           value: "\(entry.batch) / \(entry.item)")
                .foregroundStyle(.secondary)
        }
    }
}

private func paymentMoney(_ value: Int64) -> String {
    (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
}
