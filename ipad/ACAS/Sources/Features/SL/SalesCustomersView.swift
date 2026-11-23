import ACASCore
import SwiftUI

struct SalesDateView: View {
    let workspace: Workspace
    @State private var date: Date
    @State private var result: String?

    init(workspace: Workspace) {
        self.workspace = workspace
        _date = State(initialValue: SalesLedger(workspace.context).currentDate)
    }

    var body: some View {
        Form {
            DatePicker(slText("sales.date.field"), selection: $date, displayedComponents: .date)
                .environment(\.timeZone, workspace.context.timeZone)
                .accessibilityIdentifier("sales.date.value")
            Button(slText("sales.date.confirm")) {
                do {
                    try SalesLedger(workspace.context).setProcessingDate(date)
                    result = slText("sales.date.confirmed")
                } catch {
                    result = SalesMessage.text(for: error)
                }
                workspace.completed("sales-date")
            }
            .accessibilityIdentifier("sales.date.save")
            if let result { Text(result).accessibilityIdentifier("sales.date.result") }
        }
        .navigationTitle(slText("sales.date.title"))
    }
}

struct SalesCustomersMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            ForEach(SalesCustomerView.Mode.allCases) { mode in
                NavigationLink(mode.title) { SalesCustomerView(workspace: workspace, mode: mode) }
                    .accessibilityIdentifier("sales.customer." + mode.rawValue)
            }
        }
        .navigationTitle(slText("sales.customer.menu"))
    }
}

private struct SalesCustomerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case register, edit, remove, view

        var id: String { rawValue }
        var title: String {
            switch self {
            case .register: slText("sales.customer.register")
            case .edit: slText("sales.customer.edit")
            case .remove: slText("sales.customer.remove")
            case .view: slText("sales.customer.view")
            }
        }
    }

    let workspace: Workspace
    let mode: Mode
    @State private var code = ""
    @State private var draft: SalesLedger.Customer?
    @State private var terms = TermsInput()
    @State private var result: String?
    @State private var confirmDelete = false
    @FocusState private var focused: Field?

    private enum Field { case code, name, address }
    private var ledger: SalesLedger { SalesLedger(workspace.context) }
    private var codeInput: Binding<String> {
        Binding(get: { code }, set: { value in
            if mode != .register && value.uppercased() != code.uppercased() {
                draft = nil
                result = nil
                confirmDelete = false
            }
            code = value
        })
    }

    var body: some View {
        Form {
            Section {
                TextField(mode == .register ? slText("sales.customer.code.new") : slText("sales.customer.code.existing"), text: codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .code)
                    .accessibilityIdentifier("sales.customer.code")
                if mode != .register {
                    Button(slText("sales.customer.search"), action: lookup)
                        .accessibilityIdentifier("sales.customer.search")
                }
                if let result { Text(result).accessibilityIdentifier("sales.customer.result") }
            }
            if let customer = draft {
                if mode == .register || mode == .edit {
                    details(Binding(get: { draft ?? customer }, set: { edited in
                        if draft?.id == customer.id { draft = edited }
                    }))
                } else {
                    summary(customer)
                }
            }
        }
        .onAppear {
            if mode == .register && draft == nil {
                do { setDraft(try ledger.newCustomer()) } catch { result = SalesMessage.text(for: error) }
            }
        }
        .navigationTitle(mode.title)
        .toolbar {
            if draft != nil && (mode == .register || mode == .edit) {
                Button(slText("sales.customer.save"), action: save)
                    .accessibilityIdentifier("sales.customer.save")
            }
            if draft != nil && mode == .remove {
                Button(slText("sales.customer.delete"), role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("sales.customer.delete")
            }
        }
        .confirmationDialog(slText("sales.customer.deletePrompt"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(slText("sales.customer.confirmDelete"), role: .destructive) { close(permanently: true) }
                .accessibilityIdentifier("sales.customer.confirmDelete")
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder private func details(_ customer: Binding<SalesLedger.Customer>) -> some View {
        Section(slText("sales.customer.info")) {
            TextField(slText("sales.customer.name"), text: customer.name).focused($focused, equals: .name)
                .accessibilityIdentifier("sales.customer.name")
            TextField(slText("sales.customer.address1"), text: customer.address1).focused($focused, equals: .address)
                .accessibilityIdentifier("sales.customer.address1")
            TextField(slText("sales.customer.address2"), text: customer.address2)
            TextField(slText("sales.customer.phone"), text: customer.phone).keyboardType(.phonePad)
            TextField(slText("sales.customer.extension"), text: customer.extensionNumber)
            TextField(slText("sales.customer.email"), text: customer.email).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField(slText("sales.customer.fax"), text: customer.fax).keyboardType(.phonePad)
        }
        Section(slText("sales.customer.terms")) {
            termField("sales.customer.creditDays", text: $terms.creditDays)
            termField("sales.customer.creditLimit", text: $terms.creditLimit)
            TextField(slText("sales.customer.discount"), value: discount(customer.discount), format: .number.grouping(.never))
                .keyboardType(.decimalPad)
            Toggle(slText("sales.customer.lateCharge"), isOn: customer.lateCharges)
            termField("sales.customer.lateChargeMinimumBalance", text: $terms.lateChargeMinimumBalance)
            termField("sales.customer.lateChargeMaximum", text: $terms.lateChargeMaximum)
        }
        Section(slText("sales.customer.notifications")) {
            Toggle(slText("sales.customer.dunning"), isOn: customer.dunning)
            Toggle(slText("sales.customer.emailInvoice"), isOn: customer.emailInvoice)
            Toggle(slText("sales.customer.emailStatement"), isOn: customer.emailStatement)
            Toggle(slText("sales.customer.emailLetters"), isOn: customer.emailLetters)
        }
        Section(slText("sales.customer.deliveryAndNotes")) {
            TextField(slText("sales.customer.deliveryName"), text: customer.deliveryName)
            TextField(slText("sales.customer.deliveryAddress1"), text: customer.deliveryAddress1)
            TextField(slText("sales.customer.deliveryAddress2"), text: customer.deliveryAddress2)
            TextField(slText("sales.customer.notes1"), text: customer.notes1)
            TextField(slText("sales.customer.notes2"), text: customer.notes2)
        }
    }

    @ViewBuilder private func summary(_ customer: SalesLedger.Customer) -> some View {
        Section(slText("sales.customer.summary")) {
            LabeledContent(slText("sales.customer.name"), value: customer.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slText("sales.customer.name"))
                .accessibilityValue(customer.name)
                .accessibilityIdentifier("sales.customer.summary.name")
            LabeledContent(slText("sales.customer.status"), value: customer.active ? slText("sales.customer.active") : slText("sales.customer.inactive"))
            LabeledContent(slText("sales.customer.address1"), value: customer.address1)
            LabeledContent(slText("sales.customer.address2"), value: customer.address2)
            LabeledContent(slText("sales.customer.phone"), value: customer.phone)
            LabeledContent(slText("sales.customer.extension"), value: customer.extensionNumber)
            LabeledContent(slText("sales.customer.email"), value: customer.email)
            LabeledContent(slText("sales.customer.fax"), value: customer.fax)
            LabeledContent(slText("sales.customer.creditDays"), value: customer.creditDays.formatted())
            LabeledContent(slText("sales.customer.creditLimit"), value: customer.creditLimit.formatted())
            LabeledContent(slText("sales.customer.discount"), value: amount(customer.discount))
            LabeledContent(slText("sales.customer.lateChargeMinimumBalance"), value: customer.lateChargeMinimumBalance.formatted())
            LabeledContent(slText("sales.customer.lateChargeMaximum"), value: customer.lateChargeMaximum.formatted())
            LabeledContent(slText("sales.customer.balance"), value: amount(customer.balance))
            LabeledContent(slText("sales.customer.unapplied"), value: amount(customer.unapplied))
        }
        if mode == .remove {
            Section {
                Button(slText("sales.customer.suspend")) { close(permanently: false) }
            }
        }
    }

    private func amount(_ value: Int64) -> String {
        (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
    }

    private func termField(_ key: String, text: Binding<String>) -> some View {
        LabeledContent(slText(String.LocalizationValue(key))) {
            TextField(slText(String.LocalizationValue(key)), text: text)
                .keyboardType(.numberPad)
                .accessibilityIdentifier(key)
        }
    }

    private func discount(_ hundredths: Binding<Int64>) -> Binding<Decimal> {
        Binding(get: { Decimal(hundredths.wrappedValue) / 100 }, set: {
            let scaled = $0 * 100
            hundredths.wrappedValue = (scaled >= 0 && scaled <= 9_999) ? NSDecimalNumber(decimal: scaled).int64Value : -1
        })
    }

    private func lookup() {
        focused = nil
        do {
            setDraft(try ledger.customer(code: code))
            result = nil
        } catch {
            draft = nil
            result = SalesMessage.text(for: error)
        }
        if mode == .view { workspace.completed("sales-customer-view") }
    }

    private func save() {
        guard var customer = draft else { return }
        focused = nil
        do {
            try terms.apply(to: &customer)
            if mode == .register {
                customer.code = code
                let saved = try ledger.register(customer)
                result = slText("sales.customer.registered \(saved.code)")
                code = ""
                setDraft(try ledger.newCustomer())
            } else {
                try ledger.update(customer)
                result = slText("sales.customer.updated")
            }
        } catch is TermsInput.Invalid {
            result = slText("sales.customer.error.invalidTerms")
        } catch {
            result = SalesMessage.text(for: error)
        }
        workspace.completed("sales-customer-" + mode.rawValue)
    }

    private func setDraft(_ customer: SalesLedger.Customer) {
        terms = TermsInput(customer)
        draft = customer
    }

    private func close(permanently: Bool) {
        guard let customer = draft else { return }
        do {
            try ledger.closeCustomer(code: customer.code, permanently: permanently)
            draft = nil
            result = permanently ? slText("sales.customer.deleted") : slText("sales.customer.suspended")
        } catch {
            result = SalesMessage.text(for: error)
        }
        workspace.completed("sales-customer-remove")
    }
}

private struct TermsInput {
    struct Invalid: Error {}

    var creditDays = ""
    var creditLimit = ""
    var lateChargeMinimumBalance = ""
    var lateChargeMaximum = ""

    init() {}

    init(_ customer: SalesLedger.Customer) {
        creditDays = String(customer.creditDays)
        creditLimit = String(customer.creditLimit)
        lateChargeMinimumBalance = String(customer.lateChargeMinimumBalance)
        lateChargeMaximum = String(customer.lateChargeMaximum)
    }

    func apply(to customer: inout SalesLedger.Customer) throws {
        customer.creditDays = try integer(creditDays, maximum: 99)
        customer.creditLimit = try integer(creditLimit, maximum: 9_999_999)
        customer.lateChargeMinimumBalance = try integer(lateChargeMinimumBalance, maximum: 9_999)
        customer.lateChargeMaximum = try integer(lateChargeMaximum, maximum: 9_999)
    }

    private func integer(_ text: String, maximum: Int64) throws -> Int64 {
        guard text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int64(text), value <= maximum else { throw Invalid() }
        return value
    }
}

private enum SalesMessage {
    static func text(for error: Error) -> String {
        switch error as? SalesLedger.Error {
        case .missingCompany: slText("sales.error.missingCompany")
        case .deliveryWriteFailed: slText("sales.customer.error.deliveryWriteFailed")
        case .invalidDate: slText("sales.date.error.invalid")
        case .invalidCode: slText("sales.customer.error.invalidCode")
        case .duplicateCustomer: slText("sales.customer.error.duplicate")
        case .missingCustomer: slText("sales.customer.error.missing")
        case .invalidField: slText("sales.customer.error.invalidField")
        case .invalidAddress: slText("sales.customer.error.invalidAddress")
        case .outstandingBalance: slText("sales.customer.error.outstandingBalance")
        case nil: slText("sales.error.operationFailed")
        }
    }
}
