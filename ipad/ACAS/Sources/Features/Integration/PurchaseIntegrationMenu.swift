import ACASCore
import SwiftUI

struct PurchaseIntegrationMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink("仕入請求書の転記") { PurchasePostingView(workspace: workspace) }
                .accessibilityIdentifier("integration.purchasePosting")
            PeriodClosingLink(workspace: workspace, ledger: .purchases)
        }
    }
}

private struct PurchasePostingView: View {
    let workspace: Workspace
    @State private var confirming = false
    @State private var message = ""

    var body: some View {
        Form {
            Section("転記対象") {
                Text("未転記の仕入請求書を買掛元帳と連携先へ転記します。")
                Button("転記を確認") { confirming = true }
                    .accessibilityIdentifier("integration.reviewPurchasePosting")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("integration.purchaseResult") }
        }
        .navigationTitle("仕入請求書の転記")
        .confirmationDialog("仕入請求書を転記しますか？", isPresented: $confirming, titleVisibility: .visible) {
            Button("転記を実行", action: post)
            Button("取り消す", role: .cancel) {}
        }
    }

    private func post() {
        do {
            let batches = try PurchaseTransfer(workspace.context).postPending()
            message = batches.isEmpty ? "未転記の仕入請求書がありません。" : "転記バッチを作成しました：\(batches.joined(separator: "、"))"
        } catch {
            message = "仕入先、請求書、会計設定を確認してください。転記できませんでした。"
        }
        workspace.completed("integration.purchasePosting")
    }
}
