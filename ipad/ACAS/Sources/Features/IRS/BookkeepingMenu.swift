import ACASCore
import SwiftUI

struct BookkeepingMenu: View {
    let workspace: Workspace

    private var service: BookkeepingService { BookkeepingService(workspace.context) }

    var body: some View {
        List {
            link("簡易記帳設定", "settings") { BookkeepingConfigurationForm(workspace: workspace) }
            link("勘定科目管理", "accounts") { accountMenu }
            link("既定勘定管理", "defaults") { defaultMenu }
            link("仕訳転記", "post") { BookkeepingPostingForm(workspace: workspace) }
            link("試算表", "trialBalance") { accountTable("試算表") }
            link("監査証跡", "audit") { journal("監査証跡") }
            link("決算書作成", "statements") { accountTable("決算書作成") }
            link("転記修正", "amendment") { journal("転記修正") }
            link("分析帳票", "analysis") { journal("分析帳票") }
            link("元帳再計算", "recalculate") { BookkeepingRecalculate(service: service) }
        }
    }

    private var accountMenu: some View {
        List {
            link("科目表登録", "accountCreate") { BookkeepingAccountForm(workspace: workspace, editing: false) }
            link("科目表変更", "accountEdit") { BookkeepingAccountForm(workspace: workspace, editing: true) }
            link("科目表表示", "accountList") { accountTable("科目表表示") }
            link("科目表印刷", "accountPrint") { accountTable("科目表印刷") }
            link("科目表エクスポート", "accountExport") { accountTable("科目表エクスポート") }
            link("科目表インポート", "accountImport") { accountTable("科目表インポート") }
        }
        .navigationTitle("勘定科目管理")
    }

    private var defaultMenu: some View {
        List {
            link("既定勘定登録", "defaultCreate") { BookkeepingDefaultForm(workspace: workspace, editing: false) }
            link("既定勘定変更", "defaultEdit") { BookkeepingDefaultForm(workspace: workspace, editing: true) }
            link("既定勘定表示", "defaultList") { defaultTable("既定勘定表示") }
            link("既定勘定印刷", "defaultPrint") { defaultTable("既定勘定印刷") }
            link("決算書設定", "statementSettings") { defaultTable("決算書設定") }
        }
        .navigationTitle("既定勘定管理")
    }

    private func link<Content: View>(_ title: String, _ id: String,
                                     @ViewBuilder destination: () -> Content) -> some View {
        NavigationLink(title, destination: destination)
            .accessibilityIdentifier("irs." + id)
    }

    private func accountTable(_ title: String) -> some View {
        Table(service.accounts) {
            TableColumn("科目番号") { Text(verbatim: String($0.code)) }
            TableColumn("科目名", value: \.name)
            TableColumn("分類") { Text($0.category?.title ?? "") }
            TableColumn("借方") { Text((Decimal($0.debit) / 100).formatted()) }
            TableColumn("貸方") { Text((Decimal($0.credit) / 100).formatted()) }
        }
        .navigationTitle(title)
    }

    private func defaultTable(_ title: String) -> some View {
        Table(service.defaults.filter { $0.account != 0 }) {
            TableColumn("登録番号") { Text(verbatim: String($0.id)) }
            TableColumn("勘定科目") { Text(verbatim: String($0.account)) }
            TableColumn("略号", value: \.label)
            TableColumn("付加価値税") { Text($0.usesTax ? "対象" : "対象外") }
        }
        .navigationTitle(title)
    }

    @ViewBuilder private func journal(_ title: String) -> some View {
        if service.postings.isEmpty {
            ContentUnavailableView("転記データがありません", systemImage: "doc.text")
                .navigationTitle(title)
        } else {
            Table(service.postings) {
                TableColumn("仕訳番号") { Text(verbatim: String($0.id)) }
                TableColumn("借方科目") { Text(verbatim: String($0.debit)) }
                TableColumn("貸方科目") { Text(verbatim: String($0.credit)) }
                TableColumn("摘要", value: \.description)
                TableColumn("金額") { Text((Decimal($0.amount) / 100).formatted()) }
            }
            .navigationTitle(title)
        }
    }
}

private struct BookkeepingRecalculate: View {
    let service: BookkeepingService
    @State private var confirming = false
    @State private var status = ""

    var body: some View {
        Form {
            Button("元帳を再計算", role: .destructive) { confirming = true }
            if !status.isEmpty { Text(status) }
        }
        .navigationTitle("元帳再計算")
        .confirmationDialog("転記データから元帳を再計算しますか？", isPresented: $confirming, titleVisibility: .visible) {
            Button("再計算する", role: .destructive) {
                do {
                    try service.recalculate()
                    status = "元帳を再計算しました。"
                } catch { status = bookkeepingError(error) }
            }
        }
    }
}

extension BookkeepingService.Category {
    var title: String {
        switch self {
        case .assets: "資産"
        case .liabilities: "負債"
        case .income: "収益"
        case .expense: "費用"
        case .other: "その他"
        }
    }
}

func bookkeepingError(_ error: Error) -> String {
    switch error as? BookkeepingService.Failure {
    case .duplicateAccount: "この勘定科目は既に登録されています。"
    case .missingAccount: "勘定科目が見つかりません。"
    case .missingDefault: "選択した番号の既定勘定がありません。"
    case .missingPosting: "転記データがありません。"
    default: "入力内容を確認してください。"
    }
}
