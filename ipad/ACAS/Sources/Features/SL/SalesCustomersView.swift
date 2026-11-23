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
            DatePicker("処理日", selection: $date, displayedComponents: .date)
                .environment(\.timeZone, workspace.context.timeZone)
                .accessibilityIdentifier("sales.date.value")
            Button("処理日を確定") {
                do {
                    try SalesLedger(workspace.context).setProcessingDate(date)
                    result = "処理日を確定しました"
                } catch {
                    result = SalesMessage.text(for: error)
                }
                workspace.completed("sales-date")
            }
            .accessibilityIdentifier("sales.date.save")
            if let result { Text(result).accessibilityIdentifier("sales.date.result") }
        }
        .navigationTitle("処理日入力")
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
        .navigationTitle("得意先マスター管理")
    }
}

private struct SalesCustomerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case register, edit, remove, view

        var id: String { rawValue }
        var title: String {
            switch self {
            case .register: "得意先登録"
            case .edit: "得意先変更"
            case .remove: "得意先削除"
            case .view: "得意先表示"
            }
        }
    }

    let workspace: Workspace
    let mode: Mode
    @State private var code = ""
    @State private var draft: SalesLedger.Customer?
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
                TextField(mode == .register ? "得意先コード（6桁）" : "得意先コード（7桁）", text: codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .code)
                    .accessibilityIdentifier("sales.customer.code")
                if mode != .register {
                    Button("得意先を検索", action: lookup)
                        .accessibilityIdentifier("sales.customer.search")
                }
                if let result { Text(result).accessibilityIdentifier("sales.customer.result") }
            }
            if let model = Binding($draft) {
                if mode == .register || mode == .edit {
                    details(model)
                } else {
                    summary(model.wrappedValue)
                }
            }
        }
        .onAppear {
            if mode == .register && draft == nil {
                do { draft = try ledger.newCustomer() } catch { result = SalesMessage.text(for: error) }
            }
        }
        .navigationTitle(mode.title)
        .toolbar {
            if draft != nil && (mode == .register || mode == .edit) {
                Button("得意先を保存", action: save)
                    .accessibilityIdentifier("sales.customer.save")
            }
            if draft != nil && mode == .remove {
                Button("得意先を削除", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("sales.customer.delete")
            }
        }
        .confirmationDialog("得意先を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { close(permanently: true) }
                .accessibilityIdentifier("sales.customer.confirmDelete")
            Button("取り消す", role: .cancel) {}
        }
    }

    @ViewBuilder private func details(_ customer: Binding<SalesLedger.Customer>) -> some View {
        Section("基本情報") {
            TextField("名称", text: customer.name).focused($focused, equals: .name)
                .accessibilityIdentifier("sales.customer.name")
            TextField("住所（上段）", text: customer.address1).focused($focused, equals: .address)
                .accessibilityIdentifier("sales.customer.address1")
            TextField("住所（下段）", text: customer.address2)
            TextField("電話番号", text: customer.phone).keyboardType(.phonePad)
            TextField("内線", text: customer.extensionNumber)
            TextField("メールアドレス", text: customer.email).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("ファクス番号", text: customer.fax).keyboardType(.phonePad)
        }
        Section("通知") {
            Toggle("延滞料", isOn: customer.lateCharges)
            Toggle("督促状", isOn: customer.dunning)
            Toggle("請求書をメール送付", isOn: customer.emailInvoice)
            Toggle("明細書をメール送付", isOn: customer.emailStatement)
            Toggle("督促状をメール送付", isOn: customer.emailLetters)
        }
        Section("納品先と備考") {
            TextField("納品先名称", text: customer.deliveryName)
            TextField("納品先住所（上段）", text: customer.deliveryAddress1)
            TextField("納品先住所（下段）", text: customer.deliveryAddress2)
            TextField("備考（上段）", text: customer.notes1)
            TextField("備考（下段）", text: customer.notes2)
        }
    }

    @ViewBuilder private func summary(_ customer: SalesLedger.Customer) -> some View {
        Section("得意先情報") {
            LabeledContent("名称", value: customer.name)
            LabeledContent("状態", value: customer.active ? "取引中" : "取引停止")
            LabeledContent("住所（上段）", value: customer.address1)
            LabeledContent("住所（下段）", value: customer.address2)
            LabeledContent("電話番号", value: customer.phone)
            LabeledContent("内線", value: customer.extensionNumber)
            LabeledContent("メールアドレス", value: customer.email)
            LabeledContent("ファクス番号", value: customer.fax)
            LabeledContent("売掛残高", value: amount(customer.balance))
            LabeledContent("未消込残高", value: amount(customer.unapplied))
        }
        if mode == .remove {
            Section {
                Button("取引を停止") { close(permanently: false) }
            }
        }
    }

    private func amount(_ value: Int64) -> String {
        (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
    }

    private func lookup() {
        focused = nil
        do {
            draft = try ledger.customer(code: code)
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
            if mode == .register {
                customer.code = code
                let saved = try ledger.register(customer)
                result = "得意先を登録しました：\(saved.code)"
                code = ""
                draft = try ledger.newCustomer()
            } else {
                try ledger.update(customer)
                result = "得意先を更新しました"
            }
        } catch {
            result = SalesMessage.text(for: error)
        }
        workspace.completed("sales-customer-" + mode.rawValue)
    }

    private func close(permanently: Bool) {
        guard let customer = draft else { return }
        do {
            try ledger.closeCustomer(code: customer.code, permanently: permanently)
            draft = nil
            result = permanently ? "得意先を削除しました" : "得意先の取引を停止しました"
        } catch {
            result = SalesMessage.text(for: error)
        }
        workspace.completed("sales-customer-remove")
    }
}

private enum SalesMessage {
    static func text(for error: Error) -> String {
        switch error as? SalesLedger.Error {
        case .missingCompany: "先に会社設定を保存してください"
        case .deliveryWriteFailed: "納品先または備考を保存できませんでした"
        case .invalidDate: "処理日を確認してください"
        case .invalidCode: "得意先コードは半角の英数字またはハイフン6桁で入力してください"
        case .duplicateCustomer: "この得意先はすでに登録されています"
        case .missingCustomer: "指定した得意先は登録されていません"
        case .invalidField: "入力した文字または項目の長さを確認してください"
        case .invalidAddress: "住所は会社設定の区切り文字を使って分け、最初の部分を短くしてください"
        case .outstandingBalance: "売掛残高または未消込残高があるため処理できません"
        case nil: "処理を完了できませんでした"
        }
    }
}
