import ACASCore
import SwiftUI

struct TrialBalanceMenu: View {
    let workspace: Workspace
    @State private var status: String?
    @State private var reportBytes: [UInt8]?

    var body: some View {
        List {
            Button(ledgerText("trial-balance.detail"), action: printDetail)
                .accessibilityIdentifier("gl.trial-balance.detail")
            if let status {
                Text(status).accessibilityIdentifier("gl.trial-balance.result")
            }
            if let reportBytes { LedgerReportShare(bytes: reportBytes) }
        }
        .navigationTitle(ledgerText("trial-balance"))
        .onAppear { workspace.completed("gl-trial-balance-menu") }
    }

    private func printDetail() {
        reportBytes = nil
        do {
            try DetailedTrialBalance(workspace.context).generateReport()
            reportBytes = workspace.context.store.readRaw(CompanySetup.reportPath)
            status = ledgerText("trial-balance.ready")
            workspace.completed("gl-trial-balance-detail")
        } catch DetailedTrialBalance.Error.missingLedger {
            status = ledgerText("trial-balance.missing")
        } catch {
            status = ledgerText("error.other")
        }
    }
}
