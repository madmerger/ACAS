import ACASCore
import SwiftUI

struct SalesDeliveryPrintView: View {
    private enum Mode { case print, reprint }

    let workspace: Workspace
    @State private var mode = Mode.print
    @State private var processingDate: String?
    @State private var failed = false

    var body: some View {
        Form {
            if let processingDate {
                LabeledContent(slText("sales.date.field")) {
                    Text(processingDate).accessibilityIdentifier("sales.invoice.deliveryPrint.date")
                }
                Picker(slText("sales.invoice.deliveryPrint.mode"), selection: $mode) {
                    Text(slText("sales.invoice.deliveryPrint.print")).tag(Mode.print)
                    Text(slText("sales.invoice.deliveryPrint.reprint")).tag(Mode.reprint)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sales.invoice.deliveryPrint.mode")
            } else if failed {
                Text(slText("sales.invoice.deliveryPrint.unavailable"))
            }
        }
        .navigationTitle(slText("sales.invoice.deliveryPrint.title"))
        .task {
            guard processingDate == nil, !failed else { return }
            do {
                if let date = try SalesInvoices(workspace.context).openDeliveryPrint() {
                    processingDate = date
                    workspace.completed("sales-invoice-delivery-print-view")
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}
