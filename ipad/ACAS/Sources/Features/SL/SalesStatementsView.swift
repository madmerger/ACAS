import ACASCore
import SwiftUI

struct SalesStatementsView: View {
    let workspace: Workspace
    @State private var date = Date()
    @State private var customer = ""
    @State private var minimum = "0"
    @State private var message1 = ""
    @State private var message2 = ""
    @State private var ready = false
    @State private var entries: [SalesStatements.Entry] = []
    @State private var document: SalesReportDocument?
    @State private var failure: String.LocalizationValue?

    var body: some View {
        Form {
            if ready {
                DatePicker(slText("sales.dunning.date"), selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, workspace.context.timeZone)
                TextField(slText("sales.customer.report.code"), text: $customer)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField(slText("sales.statement.minimum"), text: $minimum)
                    .keyboardType(.decimalPad)
                TextField(slText("sales.statement.message1"), text: $message1)
                TextField(slText("sales.statement.message2"), text: $message2)
                Button(slText("sales.action.generate"), action: generate)
                    .accessibilityIdentifier("sales.statement.generate")
            }
            if let failure { Text(slText(failure)).accessibilityIdentifier("sales.statement.error") }
            if document != nil, entries.isEmpty { Text(slText("sales.statement.empty")) }
            ForEach(entries) { entry in
                LabeledContent(entry.customer + "　" + entry.name,
                               value: (Decimal(entry.balance) / 100).formatted(.number.precision(.fractionLength(2))))
            }
        }
        .navigationTitle(slText("sales.statement.title"))
        .task {
            guard !ready else { return }
            do {
                date = try SalesStatements(workspace.context).prepare()
                ready = true
            } catch {
                setFailure(error)
                workspace.completed("sales-statement")
            }
        }
        .toolbar {
            if let document {
                ToolbarItem(placement: .primaryAction) {
                    SalesReportExport(report: document, identifier: "sales.statement.export",
                                      filename: slText("sales.statement.filename"))
                }
            }
        }
    }

    private func generate() {
        document = nil
        entries = []
        let parts = minimum.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), (1...6).contains(parts[0].count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.count == 1 || parts[1].count <= 2,
              let value = Decimal(string: minimum, locale: Locale(identifier: "en_US_POSIX")) else {
            failure = "sales.statement.inputInvalid"
            return
        }
        do {
            let cents = NSDecimalNumber(decimal: value * 100).int64Value
            entries = try SalesStatements(workspace.context).generate(date: date, customer: customer,
                minimum: cents, message1: message1, message2: message2)
            document = workspace.context.store.readRaw(SalesStatements.exportPath).map(SalesReportDocument.init)
            ready = false
            failure = nil
            workspace.completed("sales-statement")
        } catch {
            setFailure(error)
        }
    }

    private func setFailure(_ error: Error) {
        switch error {
        case SalesStatements.Error.missingOpenItems: failure = "sales.period.openItemsMissing"
        case SalesStatements.Error.invalidInput: failure = "sales.statement.inputInvalid"
        default: failure = "sales.statement.failed"
        }
    }
}
