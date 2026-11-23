import ACASCore
import SwiftUI

struct SalesMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink("sales.proof") { SalesProofView(workspace: workspace) }
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
                Button("action.generate", systemImage: "doc.badge.plus", action: generate)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("action.generate")
            }
            .padding()
            if let entries {
                Table(entries) {
                    TableColumn("sales.proof.customer") { Text($0.customer) }
                    TableColumn("sales.proof.name") { Text($0.name) }
                    TableColumn("sales.proof.net") { Text(amount($0.net)) }
                    TableColumn("sales.proof.tax") { Text(amount($0.tax)) }
                    TableColumn("sales.proof.gross") { Text(amount($0.gross)) }
                }
                .accessibilityIdentifier("sales.proof.preview")
            } else {
                ContentUnavailableView("sales.proof.ready", systemImage: "doc.text")
            }
        }
        .navigationTitle("sales.proof")
        .alert("sales.proof.failed", isPresented: $failed) {
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
