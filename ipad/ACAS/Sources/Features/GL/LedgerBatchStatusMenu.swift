import ACASCore
import SwiftUI

struct LedgerBatchStatusMenu: View {
    let workspace: Workspace
    @State private var generationResult: String?

    var body: some View {
        List {
            NavigationLink(ledgerText("batch-status-display")) {
                LedgerBatchStatusList(report: LedgerBatchStatus(workspace.context))
                    .onAppear { workspace.completed("gl-batch-status-display") }
            }
            .accessibilityIdentifier("gl.batch-status.display")
            Button(ledgerText("batch-status-print"), action: printReport)
                .accessibilityIdentifier("gl.batch-status.print")
            if let generationResult {
                Text(generationResult).accessibilityIdentifier("gl.batch-status.result")
            }
        }
        .navigationTitle(ledgerText("batch-status"))
        .onAppear { workspace.completed("gl-batch-status-menu") }
    }

    private func printReport() {
        do {
            try LedgerBatchStatus(workspace.context).generateReport()
            generationResult = ledgerText("batch-status-printed")
            workspace.completed("gl-batch-status-print")
        } catch {
            generationResult = ledgerText("batch-status-print-failed")
        }
    }
}

private struct LedgerBatchStatusList: View {
    let report: LedgerBatchStatus

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(report.cycle, format: .number)
                        .accessibilityIdentifier("gl.batch-status.cycle")
                } label: {
                    Text(ledgerText("batch-cycle"))
                }
            }
            ForEach(report.rows) { row in
                Section("\(ledgerText("batch-ledger.\(row.ledger.rawValue)"))　\(row.number)") {
                    LabeledContent(ledgerText("batch-state"), value: ledgerText("batch-state." + row.state.rawValue))
                    if row.day > 0 {
                        let date = Maps04.dateOfInteger(Int(row.day))
                        LabeledContent(ledgerText("batch-activity"), value: "\(date.year)年\(date.month)月\(date.day)日")
                    }
                    LabeledContent(ledgerText("batch-count"), value: String(row.items))
                    LabeledContent(ledgerText("batch-gross"), value: money(row.expectedGross))
                    LabeledContent(ledgerText("batch-tax"), value: money(row.expectedTax))
                    LabeledContent(ledgerText("batch-gross-actual"), value: money(row.actualGross))
                    LabeledContent(ledgerText("batch-tax-actual"), value: money(row.actualTax))
                }
                .accessibilityIdentifier("gl.batch-status.row." + row.id)
            }
        }
        .navigationTitle(ledgerText("batch-status-display"))
    }

    private func money(_ cents: Int64) -> String {
        (Decimal(cents) / 100).formatted(.number.precision(.fractionLength(2)))
    }
}
