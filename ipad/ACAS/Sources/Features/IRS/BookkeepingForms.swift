import ACASCore
import SwiftUI

struct BookkeepingConfigurationForm: View {
    let workspace: Workspace
    @State private var value: BookkeepingService.Configuration
    @State private var password = ""
    @State private var newPassword = ""
    @State private var message = ""
    @State private var authenticated = false

    init(workspace: Workspace) {
        self.workspace = workspace
        _value = State(initialValue: BookkeepingService(workspace.context).configuration)
    }

    var body: some View {
        Form {
            if authenticated {
                Section(irsText("settings.company")) {
                    TextField(irsText("settings.operator"), text: $value.operatorName).accessibilityIdentifier("irs.operatorName")
                    TextField(irsText("settings.client"), text: $value.client).accessibilityIdentifier("irs.client")
                    TextField(irsText("settings.street"), text: $value.street)
                    TextField(irsText("settings.city"), text: $value.city)
                    TextField(irsText("settings.country"), text: $value.country)
                    TextField(irsText("settings.postcode"), text: $value.postcode)
                }
                Section(irsText("settings.period")) {
                    DatePicker(irsText("settings.start"), selection: $value.start, displayedComponents: .date)
                    DatePicker(irsText("settings.end"), selection: $value.end, displayedComponents: .date)
                    TextField(irsText("settings.taxRate"), value: $value.taxRate, format: .percent.scale(0.01))
                        .keyboardType(.decimalPad)
                    TextField(irsText("settings.printDestination"), text: $value.printDestination)
                }
                SecureField(irsText("field.newPassword"), text: $newPassword)
                    .accessibilityIdentifier("irs.newPassword")
                Button(irsText("action.save")) {
                    do {
                        try BookkeepingService(workspace.context).save(value, password: password,
                                                                       newPassword: newPassword.isEmpty ? nil : newPassword)
                        message = irsText("result.settingsSaved")
                        authenticated = false
                        password = ""
                        newPassword = ""
                    } catch { message = bookkeepingError(error) }
                    workspace.completed("irs.settings")
                }
                .accessibilityIdentifier("irs.saveSettings")
            } else {
                SecureField(irsText("field.password"), text: $password)
                    .accessibilityIdentifier("irs.settingsPassword")
                Button(irsText("action.authenticateSettings")) {
                    do {
                        value = try BookkeepingService(workspace.context).authenticateSettings(password: password)
                        authenticated = true
                        message = ""
                        workspace.completed("irs.settings.authenticated")
                    } catch {
                        message = bookkeepingError(error)
                        password = ""
                    }
                }
                .accessibilityIdentifier("irs.authenticateSettings")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle(irsText("menu.settings"))
    }
}

struct BookkeepingAccountForm: View {
    let workspace: Workspace
    let editing: Bool
    @State private var code = ""
    @State private var child = ""
    @State private var name = ""
    @State private var category = BookkeepingService.Category.assets
    @State private var selection: String?
    @State private var message = ""

    private var service: BookkeepingService { BookkeepingService(workspace.context) }

    var body: some View {
        Form {
            if editing {
                Picker(irsText("field.account"), selection: $selection) {
                    Text(irsText("field.choose")).tag(String?.none)
                    ForEach(service.accounts) { row in
                        Text(row.name).tag(Optional(row.id))
                    }
                }
                .onChange(of: selection) { _, next in
                    guard let next, let row = service.accounts.first(where: { $0.id == next }) else { return }
                    code = String(row.code)
                    child = row.child == 0 ? "" : String(row.child)
                    name = row.name
                    category = row.category ?? .other
                    message = ""
                }
            } else {
                TextField(irsText("field.accountCode"), text: $code).keyboardType(.numberPad).accessibilityIdentifier("irs.accountCode")
                TextField(irsText("field.childAccount"), text: $child).keyboardType(.numberPad)
            }
            TextField(irsText("field.accountName"), text: $name).accessibilityIdentifier("irs.accountName")
            Picker(irsText("field.category"), selection: $category) {
                ForEach(BookkeepingService.Category.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button(irsText("action.save")) {
                guard let id = Int(code), let sub = child.isEmpty ? 0 : Int(child) else {
                    message = irsText("error.accountCode")
                    return
                }
                do {
                    try service.saveAccount(code: id, child: sub, name: name, category: category, editing: editing)
                    message = irsText("result.accountSaved")
                    if !editing { code = ""; child = ""; name = "" }
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.accounts")
            }
            .accessibilityIdentifier("irs.saveAccount")
            .disabled(editing && selection == nil)
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle(editing ? irsText("accounts.edit") : irsText("accounts.create"))
    }
}

struct BookkeepingDefaultForm: View {
    let workspace: Workspace
    let editing: Bool
    @State private var slot = 1
    @State private var account = ""
    @State private var label = ""
    @State private var tax = false
    @State private var message = ""

    private var service: BookkeepingService { BookkeepingService(workspace.context) }

    var body: some View {
        Form {
            Picker(irsText("field.registration"), selection: $slot) {
                ForEach(1...29, id: \.self) { Text(verbatim: String($0)).tag($0) }
                Text(irsText("defaults.openingBalance")).tag(30)
                Text(irsText("defaults.inputTax")).tag(31)
                Text(irsText("defaults.outputTax")).tag(32)
            }
            TextField(irsText("field.accountCode"), text: $account).keyboardType(.numberPad)
            if slot < 30 {
                TextField(irsText("field.abbreviation"), text: $label)
                Toggle(irsText("field.usesTax"), isOn: $tax)
            }
            Button(irsText("action.save")) {
                guard let code = Int(account) else { message = irsText("error.accountCode"); return }
                do {
                    try service.saveDefault(slot: slot, account: code, label: label, usesTax: tax)
                    message = irsText("result.defaultSaved")
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.defaults")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle(editing ? irsText("defaults.edit") : irsText("defaults.create"))
        .onAppear(perform: load)
        .onChange(of: slot) { _, _ in load() }
    }

    private func load() {
        let row = service.defaults[slot - 1]
        account = row.account == 0 ? "" : String(row.account)
        label = row.label
        tax = row.usesTax
        message = ""
    }
}

struct BookkeepingPostingForm: View {
    let workspace: Workspace
    @State private var slot = 1
    @State private var side = BookkeepingService.Side.debit
    @State private var account = ""
    @State private var date = Date()
    @State private var description = ""
    @State private var amount = ""
    @State private var message = ""

    private var service: BookkeepingService { BookkeepingService(workspace.context) }

    var body: some View {
        Form {
            Picker(irsText("field.defaultAccount"), selection: $slot) {
                ForEach(service.defaults.filter { $0.account != 0 }) { Text($0.label).tag($0.id) }
            }
            Picker(irsText("field.defaultType"), selection: $side) {
                Text(irsText("field.debit")).tag(BookkeepingService.Side.debit)
                Text(irsText("field.credit")).tag(BookkeepingService.Side.credit)
            }
            .accessibilityIdentifier("irs.postSide")
            DatePicker(irsText("field.date"), selection: $date, displayedComponents: .date)
                .environment(\.timeZone, workspace.context.timeZone)
            TextField(irsText("field.otherAccount"), text: $account).keyboardType(.numberPad)
                .accessibilityIdentifier("irs.postAccount")
            TextField(irsText("field.narrative"), text: $description).accessibilityIdentifier("irs.postDescription")
            TextField(irsText("field.amount"), text: $amount).keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("irs.postAmount")
            Button(irsText("action.post")) {
                guard let id = Int(account), let decimal = Decimal(string: amount, locale: Locale(identifier: "ja_JP")),
                      (-9_999_999...9_999_999).contains(decimal)
                else { message = irsText("error.posting"); return }
                do {
                    try service.post(defaultSlot: slot, side: side, account: id, date: date,
                                     amount: NSDecimalNumber(decimal: decimal * 100).int64Value, description: description)
                    message = irsText("result.posted")
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.post")
            }
            .accessibilityIdentifier("irs.submitPost")
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle(irsText("menu.post"))
        .onAppear {
            date = service.today
            slot = service.defaults.first(where: { $0.account != 0 })?.id ?? 1
        }
    }
}
