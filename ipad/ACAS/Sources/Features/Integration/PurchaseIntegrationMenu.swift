import ACASCore
import SwiftUI

struct PurchaseIntegrationMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(intText("purchase.title")) { PurchasePostingView(workspace: workspace) }
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
            Section(intText("purchase.section")) {
                Text(intText("purchase.notice"))
                Button(intText("purchase.review")) { confirming = true }
                    .accessibilityIdentifier("integration.reviewPurchasePosting")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("integration.purchaseResult") }
        }
        .navigationTitle(intText("purchase.title"))
        .confirmationDialog(intText("purchase.confirm"), isPresented: $confirming, titleVisibility: .visible) {
            Button(intText("purchase.perform"), action: post)
            Button(intText("action.cancel"), role: .cancel) {}
        }
    }

    private func post() {
        do {
            let batches = try PurchaseTransfer(workspace.context).postPending()
            message = batches.isEmpty ? intText("purchase.empty") : String(format: intText("purchase.completed"), batches.joined(separator: "、"))
        } catch {
            message = intText("purchase.error")
        }
        workspace.completed("integration.purchasePosting")
    }
}
