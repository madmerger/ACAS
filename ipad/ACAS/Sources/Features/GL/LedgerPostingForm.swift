import ACASCore
import SwiftUI

struct LedgerPostingForm: View {
    let workspace: Workspace
    @State private var confirm = false
    @State private var status: String?
    @State private var reportBytes: [UInt8]?

    var body: some View {
        Form {
            Section(ledgerText("posting.check")) {
                LabeledContent(ledgerText("batch-cycle"), value: String(LedgerBatchStatus(workspace.context).cycle))
                Button(ledgerText("posting.run")) { confirm = true }
                    .accessibilityIdentifier("gl.posting.run")
                if let status {
                    Text(status).accessibilityIdentifier("gl.posting.result")
                }
                if let reportBytes { LedgerReportShare(bytes: reportBytes) }
            }
        }
        .navigationTitle(ledgerText("posting"))
        .onAppear { workspace.completed("gl-posting-menu") }
        .confirmationDialog(ledgerText("posting.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(ledgerText("posting.run"), action: post)
                .accessibilityIdentifier("gl.posting.confirm")
        }
    }

    private func post() {
        reportBytes = nil
        do {
            let result = try LedgerPosting(workspace.context).postCurrentCycle()
            if result.batches > 0 {
                reportBytes = workspace.context.store.readRaw(CompanySetup.reportPath)
            }
            status = ledgerText(result.batches == 0 ? "posting.empty" : "posting.ready")
        } catch LedgerPosting.Error.openBatches {
            status = ledgerText("posting.open-batch")
        } catch LedgerPosting.Error.invalidPostings, LedgerPosting.Error.missingAccount {
            status = ledgerText("posting.invalid")
        } catch {
            status = ledgerText("posting.failed")
        }
    }
}
