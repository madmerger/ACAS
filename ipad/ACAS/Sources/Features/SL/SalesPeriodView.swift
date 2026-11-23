import SwiftUI
import ACASCore

struct SalesDayBookView: View {
    let workspace: Workspace
    @State private var entries: [SalesDayBook.Entry] = []
    @State private var failure: String.LocalizationValue?
    @State private var document: SalesReportDocument?

    var body: some View {
        List {
            Button(slText("sales.action.generate"), action: generate)
                .accessibilityIdentifier("sales.dayBook.generate")
            if let failure { Text(slText(failure)) }
            if document != nil, entries.isEmpty { Text(slText("sales.dayBook.empty")) }
            ForEach(entries) { entry in
                LabeledContent(entry.id.display + "　" + entry.name,
                               value: (Decimal(entry.gross) / 100).formatted(.number.precision(.fractionLength(2))))
            }
        }
        .navigationTitle(slText("sales.dayBook.title"))
        .toolbar {
            if let document {
                ToolbarItem(placement: .primaryAction) {
                    SalesReportExport(report: document, identifier: "sales.dayBook.export",
                                      filename: slText("sales.dayBook.filename"))
                }
            }
        }
    }

    private func generate() {
        do {
            guard let rows = try SalesDayBook(workspace.context).generate() else {
                failure = "sales.dayBook.missing"
                workspace.completed("sales-day-book-unavailable")
                return
            }
            entries = rows
            failure = nil
            document = workspace.context.store.readRaw(SalesDayBook.exportPath).map(SalesReportDocument.init)
            workspace.completed("sales-day-book")
        } catch {
            failure = "sales.dayBook.failed"
        }
    }
}

struct SalesPeriodCloseView: View {
    let workspace: Workspace
    @State private var backedUp = false
    @State private var acceptPending = false
    @State private var endQuarter = false
    @State private var options: SalesPeriodClose.Options?
    @State private var password = ""
    @State private var confirm = false
    @State private var finished = false
    @State private var failure: String.LocalizationValue?

    var body: some View {
        Form {
            if finished {
                Text(slText("sales.period.finished"))
                    .accessibilityIdentifier("sales.period.finished")
            } else {
                Text(slText("sales.period.notice"))
                    .accessibilityIdentifier("sales.period.notice")
                Toggle(slText("sales.period.backedUp"), isOn: $backedUp)
                    .accessibilityIdentifier("sales.period.backedUp")
                if backedUp, let options {
                    if options.warnedInvoices { Toggle(slText("sales.period.pendingInvoices"), isOn: $acceptPending) }
                    if options.manualQuarter { Toggle(slText("sales.period.endQuarter"), isOn: $endQuarter) }
                    SecureField(slText("sales.period.password"), text: $password)
                    Button(slText("sales.period.execute"), role: .destructive) { confirm = true }
                        .disabled(options.warnedInvoices && !acceptPending)
                        .accessibilityIdentifier("sales.period.execute")
                }
                if let failure { Text(slText(failure)).accessibilityIdentifier("sales.period.error") }
            }
        }
        .navigationTitle(slText("sales.period.title"))
        .task { workspace.completed("sales-period-view") }
        .onChange(of: backedUp) { _, backedUp in
            if backedUp {
                do {
                    options = try SalesPeriodClose(workspace.context).options()
                    failure = nil
                } catch {
                    setFailure(error)
                }
            } else {
                options = nil
                failure = nil
            }
        }
        .alert(slText("sales.period.confirm"), isPresented: $confirm) {
            Button(slText("sales.period.execute"), role: .destructive, action: run)
                .accessibilityIdentifier("sales.period.confirm")
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    private func run() {
        defer { password = "" }
        do {
            try SalesPeriodClose(workspace.context).close(password: password,
                acceptingPendingInvoices: acceptPending, endQuarter: endQuarter)
            finished = true
            workspace.completed("sales-period-close")
        } catch {
            setFailure(error)
        }
    }

    private func setFailure(_ error: Error) {
        switch error {
        case SalesPeriodClose.Error.missingAnalysis: failure = "sales.period.analysisMissing"
        case SalesPeriodClose.Error.pendingPayments: failure = "sales.period.pendingPayments"
        case SalesPeriodClose.Error.analysisReportRequired: failure = "sales.period.analysisRequired"
        case SalesPeriodClose.Error.invalidPassword: failure = "sales.period.invalidPassword"
        case SalesPeriodClose.Error.missingOpenItems: failure = "sales.period.openItemsMissing"
        default: failure = "sales.period.failed"
        }
    }
}
