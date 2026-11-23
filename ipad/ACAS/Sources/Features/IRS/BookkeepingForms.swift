import ACASCore
import SwiftUI

struct BookkeepingConfigurationForm: View {
    let workspace: Workspace
    @State private var value: BookkeepingService.Configuration
    @State private var message = ""

    init(workspace: Workspace) {
        self.workspace = workspace
        _value = State(initialValue: BookkeepingService(workspace.context).configuration)
    }

    var body: some View {
        Form {
            Section("事業者情報") {
                TextField("担当者名", text: $value.operatorName).accessibilityIdentifier("irs.operatorName")
                TextField("事業者名", text: $value.client).accessibilityIdentifier("irs.client")
                TextField("番地", text: $value.street)
                TextField("市区町村", text: $value.city)
                TextField("国・地域", text: $value.country)
                TextField("郵便番号", text: $value.postcode)
            }
            Section("会計期間と税率") {
                DatePicker("開始日", selection: $value.start, displayedComponents: .date)
                DatePicker("終了日", selection: $value.end, displayedComponents: .date)
                TextField("付加価値税率", value: $value.taxRate, format: .percent.scale(0.01))
                    .keyboardType(.decimalPad)
                TextField("帳票の出力先", text: $value.printDestination)
            }
            Button("保存") {
                do {
                    try BookkeepingService(workspace.context).save(value)
                    message = "簡易記帳設定を保存しました。"
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.settings")
            }
            .accessibilityIdentifier("irs.saveSettings")
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle("簡易記帳設定")
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
                Picker("勘定科目", selection: $selection) {
                    Text("選択してください").tag(String?.none)
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
                TextField("科目番号", text: $code).keyboardType(.numberPad).accessibilityIdentifier("irs.accountCode")
                TextField("補助科目番号（任意）", text: $child).keyboardType(.numberPad)
            }
            TextField("科目名", text: $name).accessibilityIdentifier("irs.accountName")
            Picker("分類", selection: $category) {
                ForEach(BookkeepingService.Category.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("保存") {
                guard let id = Int(code), let sub = child.isEmpty ? 0 : Int(child) else {
                    message = "科目番号を確認してください。"
                    return
                }
                do {
                    try service.saveAccount(code: id, child: sub, name: name, category: category, editing: editing)
                    message = "勘定科目を保存しました。"
                    if !editing { code = ""; child = ""; name = "" }
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.accounts")
            }
            .accessibilityIdentifier("irs.saveAccount")
            .disabled(editing && selection == nil)
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle(editing ? "科目表変更" : "科目表登録")
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
            Picker("登録番号", selection: $slot) {
                ForEach(1...29, id: \.self) { Text(verbatim: String($0)).tag($0) }
                Text("期首残高").tag(30)
                Text("仕入付加価値税").tag(31)
                Text("売上付加価値税").tag(32)
            }
            TextField("科目番号", text: $account).keyboardType(.numberPad)
            if slot < 30 {
                TextField("略号", text: $label)
                Toggle("付加価値税の対象", isOn: $tax)
            }
            Button("保存") {
                guard let code = Int(account) else { message = "科目番号を確認してください。"; return }
                do {
                    try service.saveDefault(slot: slot, account: code, label: label, usesTax: tax)
                    message = "既定勘定を保存しました。"
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.defaults")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle(editing ? "既定勘定変更" : "既定勘定登録")
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
            Picker("既定勘定", selection: $slot) {
                ForEach(service.defaults.filter { $0.account != 0 }) { Text($0.label).tag($0.id) }
            }
            Picker("既定勘定の区分", selection: $side) {
                Text("借方").tag(BookkeepingService.Side.debit)
                Text("貸方").tag(BookkeepingService.Side.credit)
            }
            DatePicker("取引日", selection: $date, displayedComponents: .date)
            TextField("相手科目番号", text: $account).keyboardType(.numberPad)
                .accessibilityIdentifier("irs.postAccount")
            TextField("摘要", text: $description).accessibilityIdentifier("irs.postDescription")
            TextField("金額", text: $amount).keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("irs.postAmount")
            Button("転記") {
                guard let id = Int(account), let decimal = Decimal(string: amount, locale: Locale(identifier: "ja_JP")),
                      (-9_999_999...9_999_999).contains(decimal)
                else { message = "科目番号と金額を確認してください。"; return }
                do {
                    try service.post(defaultSlot: slot, side: side, account: id, date: date,
                                     amount: NSDecimalNumber(decimal: decimal * 100).int64Value, description: description)
                    message = "仕訳を転記しました。"
                } catch { message = bookkeepingError(error) }
                workspace.completed("irs.post")
            }
            .accessibilityIdentifier("irs.submitPost")
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.result") }
        }
        .navigationTitle("仕訳転記")
        .onAppear {
            date = service.today
            slot = service.defaults.first(where: { $0.account != 0 })?.id ?? 1
        }
    }
}
