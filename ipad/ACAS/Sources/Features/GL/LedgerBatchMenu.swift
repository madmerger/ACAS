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

struct LedgerBatchMaintenanceMenu: View {
    let workspace: Workspace
    @State private var choosingBatch = false
    @State private var editingBatch: LedgerBatch?
    @State private var proofReports: [LedgerBatchProof.Report] = []
    @State private var proofStatus: String?

    var body: some View {
        List {
            NavigationLink(ledgerText("batch-amend.title")) {
                let batches = LedgerBatches(workspace.context).all.filter { !$0.posted }
                List {
                    if batches.isEmpty {
                        Text(ledgerText("batch-amend.empty"))
                            .accessibilityIdentifier("gl.batch.amend.empty")
                    }
                    ForEach(batches) { batch in
                        Button("\(batch.id)　\(batch.description)") { editingBatch = batch }
                            .accessibilityIdentifier("gl.batch.amend.\(batch.id)")
                    }
                }
                .navigationTitle(ledgerText("batch-amend.title"))
                .onAppear { workspace.completed("gl-batch-amend-menu") }
                .sheet(item: $editingBatch, onDismiss: {
                    proofReports = []
                    proofStatus = nil
                }) { batch in
                    NavigationStack { LedgerBatchHeaderEditor(workspace: workspace, batch: batch) }
                }
            }
            .accessibilityIdentifier("gl.batch.amend")
            Button(ledgerText("batch-proof.all")) { proof() }
                .accessibilityIdentifier("gl.batch.proof.all")
            Button(ledgerText("batch-proof.one")) { choosingBatch = true }
                .accessibilityIdentifier("gl.batch.proof.one")
            if let proofStatus {
                Text(proofStatus).accessibilityIdentifier("gl.batch.proof.status")
            }
            ForEach(proofReports) { report in
                LabeledContent {
                    LedgerReportShare(bytes: report.bytes)
                } label: {
                    Text("\(report.id)　\(ledgerText(report.verified ? "batch-closed" : "batch-open"))")
                }
            }
        }
        .navigationTitle(ledgerText("batch-proof.title"))
        .onAppear { workspace.completed("gl-batch-maintenance-menu") }
        .sheet(isPresented: $choosingBatch) {
            NavigationStack {
                let batches = LedgerBatches(workspace.context).all
                List {
                    if batches.isEmpty {
                        Text(ledgerText("batch-proof.empty"))
                            .accessibilityIdentifier("gl.batch.proof.empty")
                    }
                    ForEach(batches) { batch in
                        Button("\(batch.id)　\(batch.description)") {
                            choosingBatch = false
                            proof(batch.id)
                        }
                        .accessibilityIdentifier("gl.batch.proof.\(batch.id)")
                    }
                }
                .navigationTitle(ledgerText("batch-proof.select"))
                .onAppear { workspace.completed("gl-batch-proof-select") }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { choosingBatch = false }
                    }
                }
            }
        }
    }

    private func proof(_ number: Int? = nil) {
        proofReports = []
        do {
            proofReports = try LedgerBatchProof(workspace.context).generate(batch: number)
            let key = proofReports.isEmpty ? "batch-proof.empty" :
                proofReports.allSatisfy(\.verified) ? "batch-proof.verified" : "batch-proof.differences"
            proofStatus = ledgerText(key)
            workspace.completed(number == nil ? "gl-batch-proof-all" : "gl-batch-proof-one")
        } catch {
            proofStatus = ledgerText("batch-proof.failed")
        }
    }
}

private struct LedgerBatchHeaderEditor: View {
    let workspace: Workspace
    let batch: LedgerBatch
    @Environment(\.dismiss) private var dismiss
    @State private var cycle = ""
    @State private var items = ""
    @State private var gross = ""
    @State private var tax = ""
    @State private var description = ""
    @State private var error: String?

    var body: some View {
        Form {
            field("batch-cycle", $cycle, .numberPad)
            field("batch-count", $items, .numberPad)
            field("batch-gross", $gross, .numbersAndPunctuation)
            if CompanySetup(workspace.context).settings.text("vat") == "Y" || batch.tax != 0 {
                field("batch-tax", $tax, .numbersAndPunctuation)
            }
            field("batch-description", $description, .default)
            Button(ledgerText("action.save"), action: save)
                .accessibilityIdentifier("gl.batch.amend.save")
            if let error { Text(error) }
        }
        .navigationTitle(ledgerText("batch-amend.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.close") { dismiss() }
            }
        }
        .onAppear {
            cycle = String(batch.cycle)
            items = String(batch.items)
            gross = "\(batch.gross / 100).\(Cobol.z(Int(batch.gross % 100), 2))"
            tax = "\(batch.tax / 100).\(Cobol.z(Int(batch.tax % 100), 2))"
            description = batch.description
        }
    }

    private func field(_ key: String, _ value: Binding<String>, _ keyboard: UIKeyboardType) -> some View {
        TextField(ledgerText(key), text: value)
            .keyboardType(keyboard)
            .accessibilityIdentifier("gl.batch.amend." + key)
    }

    private func save() {
        do {
            guard let cycle = Int(cycle) else { throw LedgerBatches.Error.cycle }
            guard let items = Int(items) else { throw LedgerBatches.Error.items }
            try LedgerBatches(workspace.context).amendHeader(number: batch.id, cycle: cycle, items: items,
                gross: LedgerBatchEditor.money(gross), tax: LedgerBatchEditor.money(tax), description: description)
            dismiss()
        } catch let problem as LedgerBatches.Error {
            error = ledgerText("batch-error." + String(describing: problem))
        } catch {
            self.error = ledgerText("batch-error.storage")
        }
    }
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
        let selected = defaults.first(where: { $0.id == selectedDefault })?.tax
        return selected == .input || selected == .output
    }

    var body: some View {
        Form {
            Section(ledgerText("batch-info")) {
                Picker(ledgerText("batch-default"), selection: $selectedDefault) {
                    Text(ledgerText("batch-select")).tag(0)
                    ForEach(defaults) { item in Text("\(item.id)：\(item.account)").tag(item.id) }
                }
                .accessibilityIdentifier("gl.batch.default")
                if usesBranches { field("batch-default-branch", $defaultBranch, type: .numberPad) }
                Picker(ledgerText("batch-direction"), selection: $direction) {
                    Text(ledgerText("batch-debit")).tag(LedgerDirection.debit)
                    Text(ledgerText("batch-credit")).tag(LedgerDirection.credit)
                }
                datePicker("batch-date", $date)
                field("batch-cycle", $cycle, type: .numberPad)
                field("batch-description", $description)
                field("batch-count", $count, type: .numberPad)
                field("batch-gross", $gross, type: .numbersAndPunctuation)
                if usesTax { field("batch-tax", $tax, type: .numbersAndPunctuation) }
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
            date = GeneralLedgerSetup(workspace.context).processingDate
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
            draft.gross = try Self.money(gross)
            draft.tax = usesTax ? try Self.money(tax) : 0
            draft.defaultBranch = defaultBranch
            let lines = try entries.map {
                JournalLine(date: parts($0.date), account: $0.account, branch: $0.branch,
                            amount: try Self.money($0.amount), memo: $0.memo, tax: usesTax ? try Self.money($0.tax) : 0)
            }
            _ = try LedgerBatches(workspace.context).add(draft, lines: lines)
            workspace.completed("gl-batch")
            dismiss()
        } catch let problem as LedgerBatches.Error {
            error = ledgerText("batch-error." + String(describing: problem))
        } catch {
            self.error = ledgerText("batch-error.storage")
        }
    }

    fileprivate static func money(_ input: String) throws -> Int64 {
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
