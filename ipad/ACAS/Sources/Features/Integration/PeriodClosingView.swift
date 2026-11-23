import ACASCore
import SwiftUI

struct PeriodClosingLink: View {
    let workspace: Workspace
    let ledger: PeriodClosing.Ledger

    var body: some View {
        NavigationLink("期末処理") {
            PeriodClosingView(workspace: workspace, initialLedger: ledger)
        }
        .accessibilityIdentifier(ledger == .sales ? "integration.salesPeriod" : "integration.purchasePeriod")
    }
}

struct PeriodClosingView: View {
    let workspace: Workspace
    let initialLedger: PeriodClosing.Ledger
    @State private var stage = Stage.backup
    @State private var date = Date()
    @State private var sales = false
    @State private var purchases = false
    @State private var password = ""
    @State private var proceedWithUnposted = false
    @State private var quarterEnd = false
    @State private var warning: PeriodClosing.Warning?
    @State private var message = ""

    private enum Stage { case backup, credentials, complete }
    private var service: PeriodClosing { PeriodClosing(workspace.context) }

    var body: some View {
        Form {
            switch stage {
            case .backup:
                Section("実行前の確認") {
                    Text("期末日を確認し、すべての会計データをバックアップしてください。")
                    DatePicker("期末日", selection: $date, displayedComponents: .date)
                    Button("バックアップ済み・続ける") {
                        do {
                            warning = try service.warning()
                            stage = .credentials
                            workspace.completed("integration." + (initialLedger == .sales ? "salesPeriod" : "purchasePeriod"))
                        } catch { show(error) }
                    }
                    .accessibilityIdentifier("integration.confirmBackup")
                }
            case .credentials:
                Section("対象台帳") {
                    Toggle("売掛元帳", isOn: $sales)
                    Toggle("買掛元帳", isOn: $purchases)
                }
                Section("実行の確認") {
                    SecureField("パスワード", text: $password)
                        .accessibilityIdentifier("integration.password")
                    if warning?.hasUnpostedInvoices == true {
                        Toggle("未転記の請求書がある状態で続ける", isOn: $proceedWithUnposted)
                    }
                    if warning?.requiresQuarterChoice == true {
                        Toggle("四半期末として処理する", isOn: $quarterEnd)
                    }
                    Button("期末処理を実行", role: .destructive, action: close)
                        .disabled(!sales && !purchases)
                }
            case .complete:
                Text("期末処理が完了しました。")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("integration.result") }
        }
        .navigationTitle("期末処理")
        .onAppear {
            date = workspace.context.now()
            sales = initialLedger == .sales
            purchases = initialLedger == .purchases
        }
    }

    private func close() {
        var ledgers: Set<PeriodClosing.Ledger> = []
        if sales { ledgers.insert(.sales) }
        if purchases { ledgers.insert(.purchases) }
        do {
            try service.close(ledgers, date: date, password: password, proceedWithUnposted: proceedWithUnposted,
                              endOfQuarter: quarterEnd)
            password = ""
            message = ""
            stage = .complete
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        switch error as? PeriodClosing.Failure {
        case .unconfigured: message = "期末処理に必要な会社設定がありません。"
        case .missingLedger: message = "選択した台帳が利用できません。"
        case .unfinishedUpdates: message = "未完了の更新があります。台帳を確認してください。"
        case .wrongPassword: message = "パスワードが一致しません。"
        default: message = "期末日を確認してください。"
        }
    }
}
