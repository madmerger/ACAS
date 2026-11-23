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
        var amount = ""
        var memo = ""
    }

    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [Entry] = []
    @State private var selectedDefault = 0
    @State private var direction = LedgerDirection.credit
    @State private var cycle = ""
    @State private var description = ""
    @State private var count = ""
    @State private var gross = ""
    @State private var date = Date()
    @State private var error: String?

    private var defaults: [LedgerDefault] {
        let chart = ChartOfAccounts(workspace.context)
        return GeneralLedgerSetup(workspace.context).defaults.filter { chart.account(code: $0.account) != nil }
    }

    var body: some View {
        Form {
            Section(ledgerText("batch-info")) {
                Picker(ledgerText("batch-default"), selection: $selectedDefault) {
                    Text(ledgerText("batch-select")).tag(0)
                    ForEach(defaults) { item in Text("\(item.id)：\(item.account)").tag(item.id) }
                }
                .accessibilityIdentifier("gl.batch.default")
                Picker(ledgerText("batch-direction"), selection: $direction) {
                    Text(ledgerText("batch-debit")).tag(LedgerDirection.debit)
                    Text(ledgerText("batch-credit")).tag(LedgerDirection.credit)
                }
                datePicker("batch-date", $date)
                field("batch-cycle", $cycle, type: .numberPad)
                field("batch-description", $description)
                field("batch-count", $count, type: .numberPad)
                field("batch-gross", $gross, type: .numbersAndPunctuation)
            }
            ForEach($entries) { $entry in
                Section(ledgerText("batch-line")) {
                    datePicker("batch-line-date", $entry.date)
                    field("account-code", $entry.account, type: .numberPad)
                    field("batch-amount", $entry.amount, type: .numbersAndPunctuation)
                    field("batch-memo", $entry.memo)
                    Button(ledgerText("batch-remove-line"), role: .destructive) { entries.removeAll { $0.id == entry.id } }
                }
            }
            Button(ledgerText("batch-add-line")) { entries.append(Entry(date: date)) }
                .accessibilityIdentifier("gl.batch.add-line")
            if let error { Text(error).accessibilityIdentifier("gl.batch.error") }
        }
        .accessibilityIdentifier("gl.batch.form")
        .environment(\.calendar, workspace.context.calendar)
        .environment(\.timeZone, workspace.context.timeZone)
        .navigationTitle(ledgerText("batch-new"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(ledgerText("action.save"), action: save).accessibilityIdentifier("gl.batch.save")
            }
        }
        .onAppear {
            date = workspace.context.now()
            cycle = String(CompanySetup(workspace.context).settings.number("scycle"))
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
            let lines = try entries.map { JournalLine(date: parts($0.date), account: $0.account, amount: try money($0.amount), memo: $0.memo) }
            _ = try LedgerBatches(workspace.context).add(draft, lines: lines)
            workspace.completed("gl-batch")
            dismiss()
        } catch let problem as LedgerBatches.Error {
            error = ledgerText("batch-error." + String(describing: problem))
        } catch {
            self.error = ledgerText("batch-error.storage")
        }
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
