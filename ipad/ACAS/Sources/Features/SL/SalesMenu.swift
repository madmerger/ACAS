import ACASCore
import SwiftUI

struct SalesMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(String(localized: "sales.proof", table: "SL")) { SalesProofView(workspace: workspace) }
                .accessibilityIdentifier("sales.proof")
        }
    }
}

private struct SalesProofView: View {
    let workspace: Workspace
    @State private var entries: [SalesProofReport.Entry]?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "action.generate", table: "SL"), systemImage: "doc.badge.plus", action: generate)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("action.generate")
            }
            .padding()
            if let entries {
                Table(entries) {
                    TableColumn(String(localized: "sales.proof.customer", table: "SL")) { Text($0.customer) }
                    TableColumn(String(localized: "sales.proof.name", table: "SL")) { Text($0.name) }
                    TableColumn(String(localized: "sales.proof.net", table: "SL")) { Text(amount($0.net)) }
                    TableColumn(String(localized: "sales.proof.tax", table: "SL")) { Text(amount($0.tax)) }
                    TableColumn(String(localized: "sales.proof.gross", table: "SL")) { Text(amount($0.gross)) }
                }
                .accessibilityIdentifier("sales.proof.preview")
            } else {
                ContentUnavailableView(String(localized: "sales.proof.ready", table: "SL"), systemImage: "doc.text")
            }
        }
        .navigationTitle(String(localized: "sales.proof", table: "SL"))
        .alert(String(localized: "sales.proof.failed", table: "SL"), isPresented: $failed) {
            Button("action.close", role: .cancel) {}
        }
    }

    private func generate() {
        do {
            entries = try SalesProofReport.generate(in: workspace.context)
            workspace.completed("sales-proof")
        } catch {
            failed = true
        }
    }

    private func amount(_ value: Int64) -> String {
        (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
    }
}
