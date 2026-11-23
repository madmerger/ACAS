import ACASCore
import SwiftUI

struct SalesReceivableOpeningView: View {
    let workspace: Workspace
    let operation: SalesReceivableOpening
    @State private var message: String.LocalizationValue?

    private var identifier: String { operation == .enquiry ? "sales.enquiry" : "sales.ageing" }

    var body: some View {
        Form {
            if let message {
                Text(slText(message)).accessibilityIdentifier(identifier + ".error")
            }
        }
        .navigationTitle(slText(operation == .enquiry ? "sales.enquiry.title" : "sales.ageing.title"))
        .task {
            guard message == nil else { return }
            do {
                switch try operation.refusal(in: workspace.context) {
                case .missingOpenItems:
                    message = "sales.period.openItemsMissing"
                    workspace.completed(operation == .enquiry ? "sales-enquiry-unavailable" : "sales-ageing-unavailable")
                case .pendingPayments:
                    message = "sales.period.pendingPayments"
                case nil:
                    message = "sales.receivable.notAvailable"
                }
            } catch {
                message = "sales.receivable.notAvailable"
            }
        }
    }
}
