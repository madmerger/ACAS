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
        guard let total = parse(amount), total > 0 else { failed = true; return }
        var draft = SalesPayments.Draft(date: date)
        draft.customer = customer
        draft.amount = total
        draft.useUnappliedBalance = usesUnapplied
        draft.acceptExpiredDeduction = acceptsDeduction
        for (invoice, text) in allocations where !text.isEmpty {
            guard let value = parse(text) else { failed = true; return }
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

    private func parse(_ text: String) -> Int64? {
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
