import ACASCore
import SwiftUI

struct StockMenu: View {
    let workspace: Workspace
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
            NavigationLink(stockText("menu.settings")) { SystemMenu(workspace: workspace) }
                .accessibilityIdentifier("stock.settings")
        }
        .onAppear { if processingDate == nil { proposedDate = stock.today } }
        .sheet(isPresented: $showDate) {
            NavigationStack {
                Form {
                    DatePicker(stockText("field.date"), selection: $proposedDate, displayedComponents: .date)
                    Button(stockText("action.commit")) {
                        processingDate = proposedDate
                        showDate = false
                        workspace.completed("stock.date")
                    }
                    .accessibilityIdentifier("stock.confirmDate")
                }
                .navigationTitle(stockText("date.title"))
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
            report(stockText("report.master"), id: "masterReport")
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
            report(stockText("report.valuation"), id: "valuation")
            report(stockText("report.activity"), id: "activity")
            report(stockText("report.reorder"), id: "reorder")
            report(stockText("report.history"), id: "history")
            report(stockText("report.listing"), id: "listing")
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

    private func report(_ title: String, id: String) -> some View {
        NavigationLink(title) { StockItemTable(stock: stock, title: title, id: id) }
            .accessibilityIdentifier("stock." + id)
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
    default: stockText("error.invalid")
    }
}
