import ACASCore
import SwiftUI

struct SalesDunningView: View {
    let workspace: Workspace
    @State private var date = Date()
    @State private var ready = false
    @State private var failure: String.LocalizationValue?

    var body: some View {
        Form {
            if ready {
                DatePicker(slText("sales.dunning.date"), selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, workspace.context.timeZone)
                Button(slText("sales.dunning.next"), action: confirmDate)
                    .accessibilityIdentifier("sales.dunning.next")
            }
            if let failure {
                Text(slText(failure))
                    .accessibilityIdentifier("sales.dunning.error")
            }
        }
        .navigationTitle(slText("sales.dunning.title"))
        .task {
            guard !ready else { return }
            do {
                date = try SalesDunning(workspace.context).prepare()
                ready = true
            } catch SalesDunning.Error.missingOpenItems {
                failure = "sales.period.openItemsMissing"
                workspace.completed("sales-dunning")
            } catch {
                failure = "sales.dunning.failed"
            }
        }
    }

    private func confirmDate() {
        do {
            try SalesDunning(workspace.context).confirmDate(date)
        } catch SalesDunning.Error.dateNotAccepted {
            failure = "sales.dunning.dateNotAccepted"
            workspace.completed("sales-dunning")
        } catch {
            failure = "sales.dunning.failed"
        }
    }
}
