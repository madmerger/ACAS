import ACASCore
import SwiftUI

func ledgerText(_ key: String) -> String {
    String(localized: String.LocalizationValue("gl." + key), table: "GL")
}

struct GeneralLedgerMenu: View {
    let workspace: Workspace
    @State private var opened = false

    var body: some View {
        if opened {
            List {
                NavigationLink(ledgerText("business-date")) { LedgerBusinessDate(workspace: workspace) {} }
                    .accessibilityIdentifier("gl.business-date")
                NavigationLink(ledgerText("accounts")) { LedgerAccountsMenu(workspace: workspace) }
                    .accessibilityIdentifier("gl.accounts")
                NavigationLink(ledgerText("defaults")) { LedgerDefaultsMenu(workspace: workspace) }
                    .accessibilityIdentifier("gl.defaults")
                NavigationLink(ledgerText("batches")) { LedgerBatchMenu(workspace: workspace) }
                    .accessibilityIdentifier("gl.batches")
                NavigationLink(ledgerText("batch-status")) { LedgerBatchStatusMenu(workspace: workspace) }
                    .accessibilityIdentifier("gl.batch-status")
                NavigationLink("section.system") { SystemMenu(workspace: workspace) }
                    .accessibilityIdentifier("gl.company-settings")
                Button(ledgerText("close-ledger")) { opened = false }
                    .accessibilityIdentifier("gl.close-ledger")
            }
        } else {
            LedgerBusinessDate(workspace: workspace) { opened = true }
        }
    }
}

private struct LedgerBusinessDate: View {
    let workspace: Workspace
    let started: () -> Void
    @State private var year = ""
    @State private var month = ""
    @State private var day = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section(ledgerText("business-date")) {
                field("year", input: $year)
                field("month", input: $month)
                field("day", input: $day)
                Button(ledgerText("confirm-date"), action: start)
                    .accessibilityIdentifier("gl.confirm-date")
                if let status { Text(status) }
            }
        }
        .task {
            let today = workspace.context.calendar.dateComponents([.year, .month, .day], from: workspace.context.now())
            year = String(today.year ?? 0)
            month = String(today.month ?? 0)
            day = String(today.day ?? 0)
        }
    }

    private func field(_ key: String, input: Binding<String>) -> some View {
        TextField(ledgerText(key), text: input)
            .keyboardType(.numberPad)
            .accessibilityIdentifier("gl.date." + key)
    }

    private func start() {
        do {
            try GeneralLedgerSetup(workspace.context).start(year: Int(year) ?? 0, month: Int(month) ?? 0, day: Int(day) ?? 0)
            status = ledgerText("date-confirmed")
            started()
        } catch GeneralLedgerSetup.Error.missingCompany {
            status = ledgerText("missing-company")
        } catch {
            status = ledgerText("invalid-date")
        }
    }
}

private struct LedgerAccountsMenu: View {
    let workspace: Workspace
    @State private var accounts: [LedgerAccount] = []
    @State private var selected: LedgerAccount?

    var body: some View {
        List {
            NavigationLink(ledgerText("account-add")) {
                LedgerAccountEditor(workspace: workspace, initial: nil)
            }
            .accessibilityIdentifier("gl.accounts.add")
            NavigationLink(ledgerText("account-edit")) {
                List(accounts) { account in
                    Button {
                        selected = account
                    } label: {
                        LabeledContent(account.name, value: account.code)
                    }
                    .accessibilityIdentifier("gl.accounts.edit." + account.id)
                }
                .navigationTitle(ledgerText("account-edit"))
                .sheet(item: $selected, onDismiss: reload) { account in
                    NavigationStack { LedgerAccountEditor(workspace: workspace, initial: account) }
                }
            }
            .accessibilityIdentifier("gl.accounts.edit")
            NavigationLink(ledgerText("account-list")) {
                Table(accounts) {
                    TableColumn(ledgerText("account-code"), value: \.code)
                    TableColumn(ledgerText("account-name"), value: \.name)
                    TableColumn(ledgerText("account-balance")) { account in
                        Text(Cobol.rtrim(Pic.edit("-(8)9.99", value: account.balance, scale: 2)))
                    }
                }
                .navigationTitle(ledgerText("account-list"))
            }
            .accessibilityIdentifier("gl.accounts.list")
        }
        .navigationTitle(ledgerText("accounts"))
        .onAppear {
            ChartOfAccounts(workspace.context).prepare()
            reload()
        }
    }

    private func reload() { accounts = ChartOfAccounts(workspace.context).accounts }
}

private struct LedgerAccountEditor: View {
    let workspace: Workspace
    let initial: LedgerAccount?
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var branch = ""
    @State private var name = ""
    @State private var type = 0
    @State private var placement = ""
    @State private var level = 1
    @State private var status: String?
    @State private var deleteConfirm = false

    var body: some View {
        Form {
            TextField(ledgerText("account-code"), text: $code)
                .keyboardType(.numberPad)
                .disabled(initial != nil)
                .accessibilityIdentifier("gl.account.code")
            if ["P", "B"].contains(CompanySetup(workspace.context).settings.text("p-c")) {
                TextField(ledgerText("account-branch"), text: $branch)
                    .keyboardType(.numberPad)
                    .disabled(initial != nil)
                    .accessibilityIdentifier("gl.account.branch")
            }
            TextField(ledgerText("account-name"), text: $name)
                .accessibilityIdentifier("gl.account.name")
            if code.count != 6 || code.hasSuffix("00") {
                Picker(ledgerText("account-type"), selection: $type) {
                    Text(ledgerText("type-header")).tag(0)
                    Text(ledgerText("type-detail")).tag(1)
                    Text(ledgerText("type-control")).tag(9)
                }
                .accessibilityIdentifier("gl.account.type")
                if type == 0 {
                    TextField(ledgerText("account-placement"), text: $placement)
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("gl.account.placement")
                    Stepper("\(ledgerText("account-level"))：\(level)", value: $level, in: 1...4)
                }
            }
            Button(ledgerText("action.save"), action: save)
                .accessibilityIdentifier("gl.account.save")
            if initial != nil {
                Button(ledgerText("account-delete"), role: .destructive) { deleteConfirm = true }
            }
            if let status { Text(status) }
        }
        .navigationTitle(ledgerText(initial == nil ? "account-add" : "account-edit"))
        .confirmationDialog(ledgerText("delete-confirm"), isPresented: $deleteConfirm) {
            Button(ledgerText("account-delete"), role: .destructive) { remove() }
        }
        .onAppear {
            code = initial?.code ?? ""
            branch = initial?.branch ?? "00"
            name = initial?.name ?? ""
            type = initial?.type ?? 0
            placement = initial?.placement ?? ""
            level = max(1, initial?.level ?? 1)
        }
    }

    private func save() {
        perform {
            let chart = ChartOfAccounts(workspace.context)
            if initial == nil {
                try chart.add(code: code, branch: branch, name: name, type: type, placement: placement, level: level)
                status = ledgerText("saved")
                workspace.completed("gl-account-add")
            } else {
                try chart.amend(code: code, branch: branch, name: name, type: type, placement: placement, level: level)
                dismiss()
            }
        }
    }

    private func remove() {
        perform {
            try ChartOfAccounts(workspace.context).delete(code: code, branch: branch)
            dismiss()
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch let error as ChartOfAccounts.Error {
            status = ledgerText("error." + String(describing: error))
        } catch {
            status = ledgerText("error.other")
        }
    }
}
