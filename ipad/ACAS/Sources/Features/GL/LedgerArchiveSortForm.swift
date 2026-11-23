import ACASCore
import SwiftUI

struct LedgerArchiveSortForm: View {
    let workspace: Workspace
    @State private var status: String?

    var body: some View {
        Form {
            if let status {
                Text(status).accessibilityIdentifier("gl.archive-sort.result")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(ledgerText("archive-sort"))
        .task {
            guard status == nil else { return }
            do {
                try LedgerArchiveSort(workspace.context).prepare()
                status = ledgerText("archive-sort.ready")
            } catch LedgerArchiveSort.Error.missingArchive {
                status = ledgerText("archive-sort.ended")
                workspace.completed("gl-archive-sort-ended")
            } catch {
                status = ledgerText("archive-sort.failed")
            }
        }
    }
}
