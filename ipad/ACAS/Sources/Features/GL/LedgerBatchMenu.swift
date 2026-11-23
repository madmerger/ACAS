import ACASCore
import SwiftUI

struct LedgerBatchMenu: View {
    let workspace: Workspace
    @State private var batches: [LedgerBatch] = []
    @State private var editing = false
    @State private var preparationFailed = false

    var body: some View {
        List {
            Button(ledgerText("batch-new")) { editing = true }
                .accessibilityIdentifier("gl.batch.new")
                .disabled(preparationFailed)
            if preparationFailed { Text(ledgerText("batch-error.storage")) }
            Section(ledgerText("batch-list")) {
                ForEach(batches) { batch in
                    LabeledContent("\(batch.id)　\(batch.description)", value: ledgerText(batch.posted ? "batch-posted" : batch.closed ? "batch-closed" : "batch-open"))
                        .accessibilityIdentifier("gl.batch.row.\(batch.id)")
                }
            }
        }
        .navigationTitle(ledgerText("batches"))
        .onAppear {
            do {
                try LedgerBatches(workspace.context).prepare()
                preparationFailed = false
                reload()
                workspace.completed("gl-batch-menu")
            } catch {
                preparationFailed = true
            }
        }
        .sheet(isPresented: $editing, onDismiss: reload) {
            NavigationStack { LedgerBatchEditor(workspace: workspace) }
        }
    }

    private func reload() { batches = LedgerBatches(workspace.context).all }
}

private struct LedgerBatchEditor: View {
    private struct Entry: Identifiable {
        let id = UUID()
        var date: Date
        var account = ""
        var branch = "00"
        var amount = ""
        var tax = ""
        var memo = ""
    }

    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [Entry] = []
    @State private var selectedDefault = 0
    @State private var defaultBranch = "00"
    @State private var temporaryAccount = ""
    @State private var temporaryCode = ""
    @State private var temporaryTax = LedgerDefaultTax.noTax
    @State private var direction = LedgerDirection.credit
    @State private var cycle = ""
    @State private var description = ""
    @State private var count = ""
    @State private var gross = ""
    @State private var tax = ""
    @State private var date = Date()
    @State private var error: String?

    private var defaults: [LedgerDefault] {
        let chart = ChartOfAccounts(workspace.context)
        let codes = Set(chart.accounts.filter { usesBranches || $0.branch == "00" }.map(\.code))
        return GeneralLedgerSetup(workspace.context).defaults.filter { $0.id <= 32 && codes.contains($0.account) }
    }

    private var usesBranches: Bool {
        ["P", "B"].contains(CompanySetup(workspace.context).settings.text("p-c"))
    }

    private var usesTax: Bool {
        let selected = selectedDefault == 33 ? temporaryTax : defaults.first(where: { $0.id == selectedDefault })?.tax
        return selected == .input || selected == .output
    }

    private var expectsTax: Bool {
        CompanySetup(workspace.context).settings.text("vat") == "Y"
    }

    private var temporaryDefault: TemporaryLedgerDefault {
        TemporaryLedgerDefault(account: temporaryAccount, code: temporaryCode, tax: temporaryTax)
    }

    var body: some View {
        Form {
            Section(ledgerText("batch-info")) {
                Picker(ledgerText("batch-default"), selection: $selectedDefault) {
                    Text(ledgerText("batch-select")).tag(0)
                    ForEach(defaults) { item in Text("\(item.id)：\(item.account)").tag(item.id) }
                    Text(ledgerText("batch-temp-default")).tag(33)
                }
                .accessibilityIdentifier("gl.batch.default")
                if usesBranches { field("batch-default-branch", $defaultBranch, type: .numberPad) }
                if selectedDefault == 33 {
                    field("batch-temp-account", $temporaryAccount, type: .numberPad)
                    field("batch-temp-code", $temporaryCode)
                    Picker(ledgerText("tax"), selection: $temporaryTax) {
                        ForEach(LedgerDefaultTax.allCases, id: \.self) { Text(ledgerText("tax." + $0.rawValue)).tag($0) }
                    }
                    .accessibilityIdentifier("gl.batch.temp-tax")
                }
                Picker(ledgerText("batch-direction"), selection: $direction) {
                    Text(ledgerText("batch-debit")).tag(LedgerDirection.debit)
                    Text(ledgerText("batch-credit")).tag(LedgerDirection.credit)
                }
                .accessibilityIdentifier("gl.batch.direction")
                datePicker("batch-date", $date)
                field("batch-cycle", $cycle, type: .numberPad)
                field("batch-description", $description)
                field("batch-count", $count, type: .numberPad)
                field("batch-gross", $gross, type: .numbersAndPunctuation)
                if expectsTax { field("batch-tax", $tax, type: .numbersAndPunctuation) }
            }
            ForEach($entries) { $entry in
                Section(ledgerText("batch-line")) {
                    datePicker("batch-line-date", $entry.date)
                    field("account-code", $entry.account, type: .numberPad)
                    if usesBranches { field("batch-line-branch", $entry.branch, type: .numberPad) }
                    field("batch-amount", $entry.amount, type: .numbersAndPunctuation)
                    if usesTax { field("batch-line-tax", $entry.tax, type: .numbersAndPunctuation) }
                    field("batch-memo", $entry.memo)
                    Button(ledgerText("batch-remove-line"), role: .destructive) { entries.removeAll { $0.id == entry.id } }
                }
            }
            Button(ledgerText("batch-add-line")) {
                entries.append(Entry(date: date))
                workspace.completed("gl-batch-draft")
            }
                .accessibilityIdentifier("gl.batch.add-line")
            if selectedDefault == 0 {
                Button(ledgerText("batch-exit-default"), action: exitDefaultSelection)
                    .accessibilityIdentifier("gl.batch.exit-default")
            }
            if let error { Text(error).accessibilityIdentifier("gl.batch.error") }
        }
        .accessibilityIdentifier("gl.batch.form")
        .environment(\.calendar, workspace.context.calendar)
        .environment(\.timeZone, workspace.context.timeZone)
        .navigationTitle(ledgerText("batch-new"))
        .interactiveDismissDisabled(selectedDefault == 33)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.close", action: cancel).accessibilityIdentifier("gl.batch.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(ledgerText("action.save"), action: save).accessibilityIdentifier("gl.batch.save")
            }
        }
        .onAppear {
            date = GeneralLedgerSetup(workspace.context).processingDate
            cycle = String(CompanySetup(workspace.context).settings.number("scycle"))
            if let value = GeneralLedgerSetup(workspace.context).defaults.last, value.account != "000000" {
                temporaryAccount = value.account
                temporaryCode = value.transactionCode
                temporaryTax = value.tax ?? .noTax
            }
            workspace.completed("gl-batch-new-menu")
        }
    }

    private func field(_ key: String, _ value: Binding<String>, type: UIKeyboardType = .default) -> some View {
        TextField(ledgerText(key), text: value)
            .keyboardType(type)
            .accessibilityIdentifier("gl." + key)
    }

    private func datePicker(_ key: String, _ value: Binding<Date>) -> some View {
        DatePicker(ledgerText(key), selection: value, displayedComponents: .date)
            .accessibilityIdentifier("gl." + key)
    }

    private func save() {
        do {
            guard let cycle = Int(cycle) else { throw LedgerBatches.Error.cycle }
            func parts(_ day: Date) -> DateComponents { workspace.context.calendar.dateComponents([.year, .month, .day], from: day) }
            var draft = LedgerBatchDraft(cycle: cycle, defaultNumber: selectedDefault, direction: direction, date: parts(date))
            draft.description = description
            draft.expectedItems = Int(count.isEmpty ? "0" : count) ?? -1
            draft.gross = try money(gross)
            draft.tax = expectsTax ? try money(tax) : 0
            draft.defaultBranch = defaultBranch
            if selectedDefault == 33 { draft.temporaryDefault = temporaryDefault }
            let lines = try entries.map {
                JournalLine(date: parts($0.date), account: $0.account, branch: $0.branch,
                            amount: try money($0.amount), memo: $0.memo, tax: usesTax ? try money($0.tax) : 0)
            }
            _ = try LedgerBatches(workspace.context).add(draft, lines: lines)
            workspace.completed("gl-batch")
            dismiss()
        } catch let problem as LedgerBatches.Error {
            error = ledgerText("batch-error." + String(describing: problem))
            if problem == .cycleTooEarly || problem == .cycleTooLate {
                workspace.completed("gl-batch-cycle-" + String(describing: problem))
            }
            if problem == .account { workspace.completed("gl-batch-error-account") }
        } catch {
            self.error = ledgerText("batch-error.storage")
        }
    }

    private func exitDefaultSelection() {
        do {
            try LedgerBatches(workspace.context).exitDefaultSelection()
            workspace.completed("gl-batch-exit-default")
            dismiss()
        } catch {
            self.error = ledgerText("batch-error.storage")
        }
    }

    private func cancel() {
        if selectedDefault == 33, !temporaryAccount.isEmpty {
            do {
                try LedgerBatches(workspace.context).retainTemporaryDefault(temporaryDefault,
                    branch: usesBranches ? defaultBranch : "00")
            } catch GeneralLedgerSetup.Error.invalidDefault {
            } catch {
                self.error = ledgerText("batch-error.storage")
                return
            }
        }
        workspace.completed("gl-batch-cancel")
        dismiss()
    }

    private func money(_ input: String) throws -> Int64 {
        if input.isEmpty { return 0 }
        let negative = input.first == "-"
        let parts = input.dropFirst(negative ? 1 : 0).split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let units = Int64(parts[0]), units <= 999_999_999 else { throw LedgerBatches.Error.amount }
        var value = units * 100
        if parts.count == 2 {
            guard (1...2).contains(parts[1].count), let digits = Int64(parts[1]) else { throw LedgerBatches.Error.amount }
            value += digits * (parts[1].count == 1 ? 10 : 1)
        }
        return negative ? -value : value
    }
}
