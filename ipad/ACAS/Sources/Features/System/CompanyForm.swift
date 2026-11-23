import ACASCore
import SwiftUI

struct PendingInitialCompany {
    let settings: CompanySettings
    let paths: SystemReportPaths
    var printReport: Bool
}

struct CompanyForm: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var settings: CompanySettings
    @State private var textDraft: [String: String] = [:]
    @State private var dateDraft: [String: String] = [:]
    @State private var saved = false
    @State private var invalid = false
    @State private var storageFailed = false
    @FocusState private var editingName: Bool
    @State private var printing = false
    @State private var printReport = true
    @State private var incompletePath: String
    @State private var ledgersPath: String
    @State private var loaded = false

    init(workspace: Workspace) {
        self.workspace = workspace
        let setup = CompanySetup(workspace.context)
        let pending = workspace.pendingInitialCompany
        let current = pending?.settings ?? setup.settings
        _settings = State(initialValue: current)
        let archivePaths = pending?.paths ?? setup.archivePaths
        _incompletePath = State(initialValue: archivePaths.incompleteRecords)
        _ledgersPath = State(initialValue: archivePaths.ledgers)
    }

    var body: some View {
        Form {
            Section(String(localized: "system.company", table: "System")) {
                TextField(String(localized: "system.company.name", table: "System"), text: textBinding("usera"))
                    .focused($editingName)
                    .submitLabel(.done)
                    .onSubmit { editingName = false }
                    .accessibilityIdentifier("system.company.name")
                NavigationLink {
                    fields(.modules)
                } label: {
                    Text(systemSetting("modules"))
                }
                .accessibilityIdentifier("system.settings.modules")
            }
            .disabled(workspace.pendingInitialCompany != nil)
            Section {
                ForEach(SystemSettingGroup.detailGroups) { group in
                    if group.module.map({ settings.number($0) == 1 }) ?? true {
                        NavigationLink { fields(group) } label: { Text(systemSetting(group.rawValue)) }
                            .accessibilityIdentifier("system.settings." + group.rawValue)
                    }
                }
            }
            .disabled(workspace.pendingInitialCompany != nil)
            Section {
                Toggle(isOn: reportSelection) { Text(systemSetting("include-report")) }
                    .accessibilityIdentifier("system.settings.include-report")
                if let pending = workspace.pendingInitialCompany {
                    Text(systemSetting("confirm-initial-report"))
                        .accessibilityIdentifier("system.settings.confirm-report")
                    Text(systemSetting(pending.printReport ? "confirm-report-on" : "confirm-report-off"))
                    Button(String(localized: "system.action.save", table: "System")) { commit(pending) }
                        .accessibilityIdentifier("system.settings.confirm-save")
                } else {
                    Button(String(localized: "system.action.save", table: "System"), action: save)
                        .accessibilityIdentifier("action.save")
                }
                if saved { Text(String(localized: "system.company.saved", table: "System")) }
                if workspace.context.store.readRaw(CompanySetup.reportPath) != nil {
                    Button { printing = true } label: { Text(systemSetting("report")) }
                        .accessibilityIdentifier("system.settings.report")
                }
            }
        }
        .navigationTitle(String(localized: "system.company", table: "System"))
        .onAppear(perform: loadSettings)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "system.company.cancel", table: "System")) {
                    workspace.pendingInitialCompany = nil
                    workspace.completed("system-company-cancel")
                    dismiss()
                }
                .accessibilityIdentifier("system.company.cancel")
            }
        }
        .alert(systemSetting("invalid"), isPresented: $invalid) {
            Button("action.close", role: .cancel) {}
        }
        .alert(String(localized: "system.company.storageFailed", table: "System"), isPresented: $storageFailed) {
            Button("action.close", role: .cancel) {}
        }
        .sheet(isPresented: $printing) {
            NavigationStack {
                let printed = CompanySetup(workspace.context).settings
                List {
                    ForEach([SystemSettingGroup.modules] + SystemSettingGroup.detailGroups) { group in
                        Section {
                            ForEach(group.fields) { field in
                                LabeledContent {
                                    value(field, in: printed)
                                } label: {
                                    Text(systemSetting(field.id))
                                }
                            }
                        } header: {
                            Text(systemSetting(group.rawValue))
                        }
                    }
                }
                .navigationTitle(systemSetting("report"))
                .toolbar {
                    Button("action.close") { printing = false }
                }
            }
        }
    }

    private func loadSettings() {
        guard !loaded else { return }
        loaded = true
        let setup = CompanySetup(workspace.context)
        let pending = workspace.pendingInitialCompany
        settings = pending?.settings ?? setup.settings
        let paths = pending?.paths ?? setup.archivePaths
        incompletePath = paths.incompleteRecords
        ledgersPath = paths.ledgers
        dateDraft = Dictionary(uniqueKeysWithValues: ["start-date", "end-date"].map { key in
            let value = settings.number(key)
            let date = Maps04.dateOfInteger(Int(value))
            return (key, value == 0 ? "" : "\(date.year)/\(date.month)/\(date.day)")
        })
    }

    private var reportSelection: Binding<Bool> {
        Binding {
            workspace.pendingInitialCompany?.printReport ?? printReport
        } set: { value in
            if workspace.pendingInitialCompany != nil {
                workspace.pendingInitialCompany?.printReport = value
            } else {
                printReport = value
            }
        }
    }

    private func fields(_ group: SystemSettingGroup) -> some View {
        Form {
            ForEach(group.fields) { field in
                switch field.kind {
                case .text:
                    TextField(systemSetting(field.id), text: textBinding(field.id))
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("system.settings." + field.id)
                case .flag:
                    Toggle(isOn: numberFlag(field.id)) { Text(systemSetting(field.id)) }
                        .accessibilityIdentifier("system.settings." + field.id)
                case .letterFlag:
                    Toggle(isOn: letterFlag(field.id)) { Text(systemSetting(field.id)) }
                        .accessibilityIdentifier("system.settings." + field.id)
                case .date:
                    TextField(systemSetting(field.id), text: Binding(
                        get: { dateDraft[field.id, default: ""] },
                        set: { dateDraft[field.id] = $0 }
                    ), prompt: Text(systemSetting("date-format")))
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("system.settings." + field.id)
                case .number, .rate:
                    SystemNumberField(field: field, value: settings.number(field.id), update: { number in
                        update { try settings.setNumber(number, for: field.id) }
                        return settings.number(field.id)
                    }, completed: {
                        if field.id == "page-lines" || field.id == "period" {
                            workspace.completed("system-company-" + field.id)
                        }
                    })
                }
            }
            if group == .operations {
                Section {
                    TextField(systemSetting("archive-incomplete"), text: $incompletePath)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("system.settings.archive-incomplete")
                    TextField(systemSetting("archive-ledgers"), text: $ledgersPath)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("system.settings.archive-ledgers")
                } header: {
                    Text(systemSetting("archive"))
                } footer: {
                    Text(systemSetting("archive-note"))
                }
            }
        }
        .accessibilityIdentifier("system.settings.form." + group.rawValue)
        .navigationTitle(systemSetting(group.rawValue))
        .onAppear {
            if group == .company { workspace.completed("system-company-data") }
        }
    }

    @ViewBuilder
    private func value(_ field: SystemSettingField, in snapshot: CompanySettings) -> some View {
        switch field.kind {
        case .number:
            Text(String(snapshot.number(field.id)))
        case .rate:
            Text(SystemNumberField.format(snapshot.number(field.id), isRate: true) + "％")
        case .text:
            Text(snapshot.text(field.id))
        case .flag:
            Text(systemSetting(snapshot.number(field.id) == 1 ? "enabled" : "disabled"))
        case .letterFlag:
            Text(systemSetting(snapshot.text(field.id) == "Y" ? "enabled" : "disabled"))
        case .date:
            let raw = snapshot.number(field.id)
            if raw > 0 {
                let date = Maps04.dateOfInteger(Int(raw))
                Text("\(date.year)年\(date.month)月\(date.day)日")
            } else {
                Text(systemSetting("not-set"))
            }
        }
    }

    private func save() {
        saved = false
        do {
            var draft = settings
            for (key, value) in textDraft { try draft.setText(value, for: key) }
            for (key, value) in dateDraft {
                if value.isEmpty {
                    try draft.setNumber(0, for: key)
                    continue
                }
                let parts = value.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
                else { throw CompanySetup.Error.invalidDate }
                try draft.setDate(year: year, month: month, day: day, for: key)
            }
            let setup = CompanySetup(workspace.context)
            let selection = PendingInitialCompany(
                settings: draft, paths: .init(incompleteRecords: incompletePath, ledgers: ledgersPath),
                printReport: printReport
            )
            guard selection.paths.isValid else { throw CompanySetup.Error.invalidField }
            if setup.name.isEmpty {
                try setup.prepareInitialRecord(draft)
                workspace.pendingInitialCompany = selection
                workspace.completed("system-initial-report-confirmation")
            } else {
                commit(selection)
            }
        } catch is CompanySetup.Error {
            invalid = true
        } catch {
            storageFailed = true
        }
    }

    private func commit(_ selection: PendingInitialCompany) {
        do {
            let setup = CompanySetup(workspace.context)
            try setup.save(selection.settings, printReport: selection.printReport, archivePaths: selection.paths)
            settings = setup.settings
            printReport = selection.printReport
            workspace.pendingInitialCompany = nil
            textDraft.removeAll()
            editingName = false
            saved = true
            workspace.completed("company")
            if selection.printReport { workspace.completed("system-company-report") }
        } catch is CompanySetup.Error {
            invalid = true
        } catch {
            storageFailed = true
        }
    }

    private func update(_ work: () throws -> Void) {
        do { try work() } catch { invalid = true }
    }

    private func textBinding(_ id: String) -> Binding<String> {
        Binding { textDraft[id] ?? settings.text(id) } set: { textDraft[id] = $0 }
    }

    private func numberFlag(_ id: String) -> Binding<Bool> {
        Binding { settings.number(id) == 1 } set: { value in
            update { try settings.setNumber(value ? 1 : 0, for: id) }
        }
    }

    private func letterFlag(_ id: String) -> Binding<Bool> {
        Binding { settings.text(id) == "Y" } set: { value in
            update { try settings.setText(value ? "Y" : "N", for: id) }
        }
    }

}

private struct SystemNumberField: View {
    let field: SystemSettingField
    @State private var input: String
    @State private var effectiveValue: Int64
    @State private var resetPageLines = false
    @FocusState private var focused: Bool
    let update: (Int64) -> Int64
    let completed: () -> Void

    init(field: SystemSettingField, value: Int64, update: @escaping (Int64) -> Int64, completed: @escaping () -> Void) {
        self.field = field
        _input = State(initialValue: Self.format(value, isRate: field.kind == .rate))
        _effectiveValue = State(initialValue: value)
        self.update = update
        self.completed = completed
    }

    var body: some View {
        LabeledContent {
            TextField(systemSetting(field.id), text: $input)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .focused($focused)
                .accessibilityIdentifier("system.settings." + field.id)
                .onChange(of: focused) {
                    if !focused { applyInput() }
                }
                .onSubmit { focused = false }
        } label: {
            Text(systemSetting(field.id))
        }
        if field.id == "period" {
            Text(systemSetting(effectiveValue == 13 ? "period.weekly" : effectiveValue == 6 ? "period.fortnightly" : "period.monthly"))
                .accessibilityIdentifier("system.settings.period.effective")
        }
        if resetPageLines {
            Text(systemSetting("page-lines.minimum"))
                .accessibilityIdentifier("system.settings.page-lines.minimum")
        }
    }

    private func applyInput() {
        let entered = number
        effectiveValue = update(entered ?? -1)
        resetPageLines = field.id == "page-lines" && (entered.map { (0...28).contains($0) } ?? false)
        if field.id != "period" || !(entered.map { (0...99).contains($0) } ?? false) {
            input = Self.format(effectiveValue, isRate: field.kind == .rate)
        }
        completed()
    }

    private var number: Int64? {
        if field.kind != .rate { return Int64(input) }
        let components = input.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(components.count), let whole = Int64(components[0]), (0...99).contains(whole)
        else { return nil }
        if components.count == 1 { return whole * 100 }
        let fraction = components[1]
        guard (1...2).contains(fraction.count), fraction.allSatisfy({ $0.isASCII && $0.isNumber }),
              let digits = Int64(fraction) else { return nil }
        return whole * 100 + digits * (fraction.count == 1 ? 10 : 1)
    }

    static func format(_ value: Int64, isRate: Bool) -> String {
        if !isRate { return String(value) }
        return String(format: "%lld.%02lld", value / 100, value % 100)
    }
}
