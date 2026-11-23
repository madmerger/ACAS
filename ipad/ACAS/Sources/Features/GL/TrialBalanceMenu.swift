import ACASCore
import SwiftUI

struct TrialBalanceMenu: View {
    let workspace: Workspace
    @State private var status: String?
    @State private var reportBytes: [UInt8]?

    var body: some View {
        List {
            Button(ledgerText("trial-balance.detail")) { printReport(structured: false) }
                .accessibilityIdentifier("gl.trial-balance.detail")
            Button(ledgerText("trial-balance.structured")) { printReport(structured: true) }
                .accessibilityIdentifier("gl.trial-balance.structured")
            if let status {
                Text(status).accessibilityIdentifier("gl.trial-balance.result")
            }
            if let reportBytes { LedgerReportShare(bytes: reportBytes) }
        }
        .navigationTitle(ledgerText("trial-balance"))
        .onAppear { workspace.completed("gl-trial-balance-menu") }
    }

    private func printReport(structured: Bool) {
        reportBytes = nil
        do {
            if structured {
                try StructuredTrialBalance(workspace.context).generateReport()
            } else {
                try DetailedTrialBalance(workspace.context).generateReport()
            }
            reportBytes = workspace.context.store.readRaw(CompanySetup.reportPath)
            status = ledgerText(structured ? "trial-balance.structured-ready" : "trial-balance.ready")
            workspace.completed(structured ? "gl-trial-balance-structured" : "gl-trial-balance-detail")
        } catch DetailedTrialBalance.Error.missingLedger {
            status = ledgerText("trial-balance.missing")
        } catch {
            status = ledgerText("error.other")
        }
    }
}
