import ACASCore
import SwiftUI

struct StockMenu: View {
    let workspace: Workspace
    let closeStock: () -> Void
    @State private var processingDate: Date?
    @State private var proposedDate = Date()
    @State private var showDate = true

    private var stock: StockService { StockService(workspace.context) }

    var body: some View {
        List {
            Button(stockText("menu.date")) {
                proposedDate = processingDate ?? stock.today
                showDate = true
            }
            .accessibilityIdentifier("stock.date")
            NavigationLink(stockText("menu.master")) { master }
                .accessibilityIdentifier("stock.master")
            NavigationLink(stockText("menu.movements")) { movements }
                .accessibilityIdentifier("stock.movements")
            NavigationLink(stockText("menu.reports")) { reports }
                .accessibilityIdentifier("stock.reports")
            NavigationLink(stockText("menu.closePeriod")) {
                StockMaintenance(stock: stock, closing: true)
                    .onAppear { workspace.completed("stock.closePeriod.open") }
            }
            .accessibilityIdentifier("stock.closePeriod")
            NavigationLink(stockText("menu.rebuild")) {
                StockMaintenance(stock: stock, closing: false)
                    .onAppear { workspace.completed("stock.rebuild.open") }
            }
            .accessibilityIdentifier("stock.rebuild")
            NavigationLink(stockText("menu.settings")) {
                SystemMenu(workspace: workspace)
                    .onAppear { workspace.completed("stock.settings.open") }
            }
                .accessibilityIdentifier("stock.settings")
            NavigationLink(stockText("import.title")) { StockImportView(workspace: workspace) }
                .accessibilityIdentifier("stock.import")
            Button(stockText("action.closeStock"), action: closeStock)
                .accessibilityIdentifier("stock.closeStock")
        }
        .onAppear { if processingDate == nil { proposedDate = stock.today } }
        .sheet(isPresented: $showDate) {
            NavigationStack {
                Form {
                    DatePicker(stockText("field.date"), selection: $proposedDate, displayedComponents: .date)
                        .environment(\.timeZone, workspace.context.timeZone)
                    Button(stockText("action.commit")) {
                        processingDate = proposedDate
                        showDate = false
                        workspace.completed("stock.date")
                    }
                    .accessibilityIdentifier("stock.confirmDate")
                }
                .navigationTitle(stockText("date.title"))
                .onAppear {
                    workspace.completed(processingDate == nil ? "stock.date.initial.open" : "stock.date.reopen.open")
                }
            }
            .interactiveDismissDisabled(processingDate == nil)
        }
    }

    private var master: some View {
        List {
            itemForm(.create)
            itemForm(.edit)
            itemForm(.delete)
            itemForm(.renumber)
            itemForm(.lookup)
            NavigationLink(stockText("report.master")) { StockMasterReportView(workspace: workspace) }
                .accessibilityIdentifier("stock.masterReport")
        }
        .navigationTitle(stockText("menu.master"))
        .onAppear { workspace.completed("stock.master.open") }
    }

    private var movements: some View {
        List {
            itemForm(.receive)
            itemForm(.issue)
            itemForm(.barcode)
            itemForm(.order)
            NavigationLink(stockText("report.audit")) {
                StockAuditView(workspace: workspace)
            }
            .accessibilityIdentifier("stock.audit")
        }
        .navigationTitle(stockText("menu.movements"))
        .onAppear { workspace.completed("stock.movements.open") }
    }

    private var reports: some View {
        List {
            ForEach(StockService.Report.allCases, id: \.rawValue) { report in
                NavigationLink(stockText("report." + report.rawValue)) {
                    StockReportForm(workspace: workspace, report: report, date: processingDate ?? stock.today)
                }
                .accessibilityIdentifier("stock." + report.rawValue)
            }
        }
        .navigationTitle(stockText("menu.reports"))
        .onAppear { workspace.completed("stock.reports.open") }
    }

    private func itemForm(_ operation: StockItemForm.Operation) -> some View {
        NavigationLink(operation.title) {
            StockItemForm(workspace: workspace, operation: operation, date: processingDate ?? stock.today)
        }
        .accessibilityIdentifier("stock." + operation.rawValue)
    }

}

private struct StockReportForm: View {
    let workspace: Workspace
    let report: StockService.Report
    let date: Date
    @State private var selection = StockService.ReportSelection.all
    @State private var abbreviation = false
    @State private var from = ""
    @State private var through = ""
    @State private var message = ""

    var body: some View {
        Form {
            let options = StockService.ReportSelection.options(for: report)
            if options.count > 1 {
                Picker(stockText("report.selection"), selection: $selection) {
                    ForEach(options, id: \.rawValue) { option in
                        Text(stockText("report.selection." + option.rawValue)).tag(option)
                    }
                }
            }
            Toggle(stockText("report.abbreviationRange"), isOn: $abbreviation)
            TextField(stockText("report.from"), text: $from)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField(stockText("report.through"), text: $through)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button(stockText("action.generateReport")) {
                do {
                    try StockService(workspace.context).printReport(report, date: date, selection: selection,
                                                                  byAbbreviation: abbreviation, from: from, through: through)
                    message = stockText("result.reportGenerated")
                    workspace.completed("stock.report." + report.rawValue)
                } catch { message = stockError(error) }
            }
            .accessibilityIdentifier("stock.generateReport")
            if !message.isEmpty {
                Text(message).accessibilityIdentifier("stock.reportResult")
            }
        }
        .navigationTitle(stockText("report." + report.rawValue))
    }
}

private struct StockAuditView: View {
    let workspace: Workspace
    @State private var result: StockService.AuditReport?
    @State private var message = ""

    var body: some View {
        Form {
            Button(stockText("action.run")) {
                let stock = StockService(workspace.context)
                do {
                    result = try stock.generateAuditReport(date: stock.today)
                    message = stockText("audit.generated")
                } catch {
                    result = nil
                    message = stockError(error)
                }
                workspace.completed("stock.audit")
            }
            .accessibilityIdentifier("stock.generateAudit")
            if !message.isEmpty { Text(message) }
            if let result {
                LabeledContent(stockText("field.received"), value: result.additions.formatted())
                LabeledContent(stockText("field.issued"), value: result.deductions.formatted())
            }
        }
        .navigationTitle(stockText("report.audit"))
    }
}

private struct StockItemTable: View {
    let stock: StockService
    let title: String
    let id: String
    @State private var filter = ""

    var body: some View {
        Table(stock.items.filter { row in
            (filter.isEmpty || row.code.localizedStandardContains(filter) || row.name.localizedStandardContains(filter))
                && (id != "reorder" || row.held <= row.reorderPoint)
        }) {
            TableColumn(stockText("field.code"), value: \.code)
            TableColumn(stockText("field.name"), value: \.name)
            TableColumn(stockText("field.held")) { Text($0.held.formatted()) }
            TableColumn(stockText("field.received")) { Text($0.added.formatted()) }
            TableColumn(stockText("field.issued")) { Text($0.deducted.formatted()) }
            TableColumn(stockText("field.value")) { Text((Decimal($0.value) / 100).formatted()) }
        }
        .searchable(text: $filter, prompt: stockText("search.prompt"))
        .navigationTitle(title)
    }
}

private struct StockMasterReportView: View {
    let workspace: Workspace
    @State private var message = ""

    var body: some View {
        let stock = StockService(workspace.context)
        StockItemTable(stock: stock, title: stockText("report.master"), id: "masterReport")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(stockText("action.generateReport")) {
                        do {
                            try stock.printMasterReport()
                            message = stockText("result.reportGenerated")
                            workspace.completed("stock.masterReport")
                        } catch {
                            message = stockError(error)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("stock.generateMasterReport")
                    Text(message).accessibilityIdentifier("stock.masterReportResult")
                }
                .padding()
            }
    }
}

private struct StockMaintenance: View {
    let stock: StockService
    let closing: Bool
    @State private var current = false
    @State private var yearly = false
    @State private var recovery = false
    @State private var confirming = false
    @State private var message = ""

    var body: some View {
        Form {
            if closing {
                Toggle(stockText("maintenance.current"), isOn: $current)
                Toggle(stockText("maintenance.annual"), isOn: $yearly)
            } else {
                Toggle(stockText("rebuild.recover"), isOn: $recovery)
            }
            Button(stockText("action.run"), role: .destructive) { confirming = true }
                .disabled(closing && !current && !yearly)
            if !message.isEmpty { Text(message) }
        }
        .navigationTitle(closing ? stockText("menu.closePeriod") : stockText("menu.rebuild"))
        .confirmationDialog(stockText("action.identity"), isPresented: $confirming, titleVisibility: .visible) {
            Button(stockText("action.confirm"), role: .destructive) {
                do {
                    if closing { try stock.closePeriod(current: current, yearly: yearly) }
                    else { try stock.rebuild(recovery: recovery) }
                    message = stockText("maintenance.done")
                } catch { message = stockError(error) }
            }
        }
    }
}

func stockError(_ error: Error) -> String {
    switch error as? StockService.Failure {
    case .missing: stockText("error.missing")
    case .duplicate: stockText("error.duplicate")
    case .hasStockOrOrders: stockText("error.hasStockOrOrders")
    case .auditRequired: stockText("error.auditRequired")
    case .missingRecovery: stockText("error.missingRecovery")
    case .invalidAnalysisRecordLength: stockText("error.invalidAnalysisRecordLength")
    default: stockText("error.invalid")
    }
}
