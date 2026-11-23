import ACASCore
import SwiftUI

struct LedgerCycleCloseForm: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Text(ledgerText("cycle-close.backup"))
                Button(ledgerText("cycle-close.cancel")) {
                    workspace.completed("gl-cycle-close-cancel")
                    dismiss()
                }
                .accessibilityIdentifier("gl.cycle-close.cancel")
                Button(ledgerText("cycle-close.run"), role: .destructive) { confirm = true }
                    .accessibilityIdentifier("gl.cycle-close.run")
                if let status { Text(status) }
            }
        }
        .navigationTitle(ledgerText("cycle-close"))
        .onAppear { workspace.completed("gl-cycle-close-menu") }
        .confirmationDialog(ledgerText("cycle-close.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(ledgerText("cycle-close.run"), role: .destructive, action: close)
        }
    }

    private func close() {
        do {
            try LedgerCycleClose(workspace.context).close()
            status = ledgerText("cycle-close.done")
        } catch LedgerCycleClose.Error.unfinishedBatches {
            status = ledgerText("cycle-close.unfinished")
        } catch {
            status = ledgerText("cycle-close.failed")
        }
    }
}
