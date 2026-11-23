import ACASCore
import SwiftUI

extension SalesInvoices.Kind {
    var title: String {
        switch self {
        case .receipt: slText("sales.invoice.receipt")
        case .invoice: slText("sales.invoice.invoice")
        case .creditNote: slText("sales.invoice.creditNote")
        case .proForma: slText("sales.invoice.proForma")
        }
    }
}

struct SalesInvoiceMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(slText("sales.invoice.pendingTitle")) { SalesInvoiceEditor(workspace: workspace, title: slText("sales.invoice.registerTitle")) }
                .accessibilityIdentifier("sales.invoice.pending")
            NavigationLink(slText("sales.invoice.immediateTitle")) { SalesInvoiceEditor(workspace: workspace, title: slText("sales.invoice.immediateTitle"), immediate: true) }
                .accessibilityIdentifier("sales.invoice.immediate")
            NavigationLink(slText("sales.invoice.editTitle")) { SalesInvoiceList(workspace: workspace, action: .edit) }
                .accessibilityIdentifier("sales.invoice.amend")
            NavigationLink(slText("sales.invoice.deleteTitle")) { SalesInvoiceList(workspace: workspace, action: .delete) }
                .accessibilityIdentifier("sales.invoice.remove")
            NavigationLink(slText("sales.invoice.printTitle")) { SalesInvoiceList(workspace: workspace, action: .print) }
                .accessibilityIdentifier("sales.invoice.print")
        }
        .navigationTitle(slText("sales.invoice.menuTitle"))
    }
}

struct SalesInvoiceEditor: View {
    let workspace: Workspace
    let title: String
    let immediate: Bool
    let existing: SalesInvoices.Number?
    @State private var draft: SalesInvoices.Draft
    @State private var result: String?
    @State private var saved = false
    @State private var confirms = false
    @State private var editingLine: LineSelection?
    @FocusState private var focusedInput: String?

    private struct LineSelection: Identifiable {
        let id: Int
    }

    init(workspace: Workspace, title: String, immediate: Bool = false, existing: SalesInvoices.Number? = nil) {
        self.workspace = workspace
        self.title = title
        self.immediate = immediate
        self.existing = existing
        let invoices = SalesInvoices(workspace.context)
        _draft = State(initialValue: existing.flatMap { try? invoices.draft(for: $0) } ?? .init(date: invoices.processingDate))
    }

    var body: some View {
        Form {
            Section(slText("sales.invoice.details")) {
                DatePicker(slText("sales.invoice.date"), selection: $draft.date, displayedComponents: .date)
                    .environment(\.timeZone, workspace.context.timeZone)
                input(slText("sales.invoice.customer"), text: $draft.customer, id: "customer")
                LabeledContent(slText("sales.invoice.kind")) {
                    Picker(slText("sales.invoice.kind"), selection: $draft.kind) {
                        ForEach(SalesInvoices.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                input(slText("sales.invoice.reference"), text: $draft.reference, id: "reference")
                input(slText("sales.invoice.order"), text: $draft.order, id: "order")
                if draft.kind == .creditNote {
                    LabeledContent(slText("sales.invoice.creditedInvoice")) {
                        TextField(slText("sales.invoice.creditedInvoice"), value: $draft.creditedInvoice, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                    }
                }
            }
            Section(slText("sales.invoice.lines")) {
                ForEach(Array(draft.lines.indices), id: \.self) { index in
                    Button {
                        editingLine = LineSelection(id: index)
                    } label: {
                        LabeledContent(slText("sales.invoice.line \(index + 1)"), value: draft.lines[index].product)
                    }
                    .accessibilityIdentifier("sales.invoice.line.\(index)")
                    .swipeActions {
                        if draft.lines.count > 1 {
                            Button(slText("sales.invoice.removeLine"), role: .destructive) {
                                draft.lines.remove(at: index)
                            }
                        }
                    }
                }
                if draft.lines.count < 40 {
                    Button(slText("sales.invoice.addLine")) {
                        draft.lines.append(.init())
                        editingLine = LineSelection(id: draft.lines.count - 1)
                    }
                }
            }
        }
        .disabled(saved)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top) {
            HStack {
                if let result { Text(result).accessibilityIdentifier("sales.invoice.result") }
                Spacer()
                Button(immediate ? slText("sales.invoice.saveAndPrint") : slText("sales.invoice.save")) {
                    focusedInput = nil
                    if immediate { confirms = true } else { save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saved)
                .accessibilityIdentifier("sales.invoice.save")
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(title)
        .fullScreenCover(item: $editingLine) { selection in
            lineEditor(selection.id)
        }
        .confirmationDialog(slText("sales.invoice.confirmImmediate"), isPresented: $confirms, titleVisibility: .visible) {
            Button(slText("sales.invoice.saveAndPrint"), action: save)
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    private func lineEditor(_ index: Int) -> some View {
        let line = $draft.lines[index]
        return NavigationStack {
            Form {
                input(slText("sales.invoice.product"), text: line.product, id: "product.\(index)")
                input(slText("sales.invoice.analysis"), text: line.analysis, id: "analysis.\(index)")
                input(slText("sales.invoice.description"), text: line.description, id: "description.\(index)")
                LabeledContent(slText("sales.invoice.quantity")) {
                    TextField(slText("sales.invoice.quantity"), value: line.quantity, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }
                LabeledContent(slText("sales.invoice.unit")) {
                    TextField(slText("sales.invoice.unit"), value: decimal(line.unit), format: .number.grouping(.never))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("sales.invoice.unit.\(index)")
                }
                LabeledContent(slText("sales.customer.discount")) {
                    TextField(slText("sales.customer.discount"), value: decimal(line.discount), format: .number.grouping(.never))
                        .keyboardType(.decimalPad)
                }
                LabeledContent(slText("sales.invoice.taxCode")) {
                    Picker(slText("sales.invoice.taxCode"), selection: line.taxCode) {
                        Text(slText("sales.invoice.taxExempt")).tag(Int64(0))
                        ForEach(1...3, id: \.self) { number in Text(slText("sales.invoice.taxRate \(number)")).tag(Int64(number)) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(slText("sales.invoice.line \(index + 1)"))
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button(slText("sales.action.dismiss")) { editingLine = nil }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("sales.invoice.line.done")
                }
                .padding()
                .background(.bar)
            }
        }
        #if DEBUG
        .safeAreaInset(edge: .top, spacing: 0) {
            if let evidence = workspace.evidence { CaseBanner(evidence: evidence) }
        }
        #endif
    }

    private func input(_ title: String, text: Binding<String>, id: String) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedInput, equals: id)
                .submitLabel(.done)
                .onSubmit { focusedInput = nil }
                .accessibilityIdentifier("sales.invoice." + id)
        }
    }

    private func decimal(_ value: Binding<Int64>) -> Binding<Decimal> {
        Binding(get: { Decimal(value.wrappedValue) / 100 }, set: { newValue in
            let scaled = newValue * 100
            if scaled >= 0, scaled <= Decimal(Int64.max) {
                value.wrappedValue = NSDecimalNumber(decimal: scaled).int64Value
            }
        })
    }

    private func save() {
        do {
            let service = SalesInvoices(workspace.context)
            let invoice = try service.save(draft, replacing: existing)
            saved = true
            if immediate { _ = try service.printInvoices([invoice.id]) }
            result = immediate ? slText("sales.invoice.immediatelyPrinted \(invoice.id.display)") : slText("sales.invoice.saved \(invoice.id.display)")
        } catch {
            result = SalesInvoiceMessage.text(for: error)
        }
        workspace.completed("sales-invoice-save")
    }
}

struct SalesInvoiceList: View {
    enum Action {
        case edit, delete, print
        var title: String {
            switch self {
            case .edit: slText("sales.invoice.editTitle")
            case .delete: slText("sales.invoice.deleteTitle")
            case .print: slText("sales.invoice.printTitle")
            }
        }
    }

    let workspace: Workspace
    let action: Action
    @State private var entries = [SalesInvoices.Invoice]()
    @State private var result: String?
    @State private var toDelete: SalesInvoices.Number?
    @State private var confirmingDeletion = false
    @State private var confirmingPrint = false
    @State private var reprint = false
    private var service: SalesInvoices { SalesInvoices(workspace.context) }

    var body: some View {
        VStack(spacing: 0) {
            if let result { Text(result).padding().accessibilityIdentifier("sales.invoice.result") }
            if action == .print {
                HStack {
                    Toggle(slText("sales.invoice.reprint"), isOn: $reprint).fixedSize()
                    Spacer()
                    Button(slText("sales.invoice.generate"), systemImage: "printer") { confirmingPrint = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("sales.invoice.generate")
                }
                .padding()
            }
            if entries.isEmpty {
                ContentUnavailableView(slText("sales.invoice.emptyList"), systemImage: "doc.text")
            } else {
                Table(entries) {
                    TableColumn(slText("sales.invoice.number")) { row in
                        if action == .edit {
                            NavigationLink(row.id.display) {
                                SalesInvoiceEditor(workspace: workspace, title: slText("sales.invoice.editTitle"), existing: row.id)
                            }
                        } else { Text(row.id.display) }
                    }
                    TableColumn(slText("sales.invoice.account"), value: \.customer)
                    TableColumn(slText("sales.invoice.type")) { Text($0.kind.title) }
                    TableColumn(slText("sales.invoice.total")) { Text((Decimal($0.total) / 100).formatted(.number.precision(.fractionLength(2)))) }
                    TableColumn(slText("sales.customer.status")) { row in
                        if action == .delete {
                            Button(slText("sales.invoice.delete"), role: .destructive) {
                                toDelete = row.id
                                confirmingDeletion = true
                            }
                        } else { Text(row.printed ? slText("sales.invoice.printed") : slText("sales.invoice.notPrinted")) }
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .navigationTitle(action.title)
        .confirmationDialog(slText("sales.invoice.deletePrompt"), isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button(slText("sales.customer.confirmDelete"), role: .destructive, action: delete)
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
        .confirmationDialog(slText("sales.invoice.printPrompt"), isPresented: $confirmingPrint, titleVisibility: .visible) {
            Button(slText("sales.invoice.confirmPrint"), action: printInvoices).accessibilityIdentifier("sales.invoice.confirmPrint")
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    private func reload() { entries = service.invoices() }

    private func delete() {
        guard let toDelete else { return }
        do {
            try service.delete(toDelete)
            result = slText("sales.invoice.deleted")
            reload()
        } catch { result = SalesInvoiceMessage.text(for: error) }
    }

    private func printInvoices() {
        do {
            let selected = reprint ? entries.filter(\.printed).map(\.id) : nil
            let printed = try service.printInvoices(selected)
            result = slText("sales.invoice.batchPrinted \(printed.count)")
            reload()
        } catch { result = SalesInvoiceMessage.text(for: error) }
        workspace.completed("sales-invoice-print")
    }
}

private enum SalesInvoiceMessage {
    static func text(for error: Error) -> String {
        switch error as? SalesInvoices.Error {
        case .missingCompany: slText("sales.error.missingCompany")
        case .missingCustomer: slText("sales.invoice.error.missingCustomer")
        case .missingInvoice: slText("sales.invoice.error.missingInvoice")
        case .invalidInput: slText("sales.invoice.error.invalidInput")
        case .duplicate: slText("sales.invoice.error.duplicate")
        case .locked: slText("sales.invoice.error.locked")
        case .empty: slText("sales.invoice.error.empty")
        case .writeFailed: slText("sales.error.operationFailed")
        case nil: slText("sales.error.operationFailed")
        }
    }
}
