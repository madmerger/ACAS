import ACASCore
import SwiftUI

struct SalesMenu: View {
    let workspace: Workspace
    @State private var entered = false

    var body: some View {
        if entered {
            actions
        } else {
            SalesDateView(workspace: workspace, onConfirm: { entered = true })
        }
    }

    private var actions: some View {
        List {
            Section(slText("sales.customer.section")) {
                NavigationLink(slText("sales.date.title")) { SalesDateView(workspace: workspace) }
                    .accessibilityIdentifier("sales.date")
                NavigationLink(slText("sales.customer.menu")) { SalesCustomersMenu(workspace: workspace) }
                    .accessibilityIdentifier("sales.customers")
            }
            Section(slText("sales.invoice.section")) {
                NavigationLink(slText("sales.invoice.saleTitle")) { SalesInvoiceEditor(workspace: workspace, title: slText("sales.invoice.saleTitle")) }
                    .accessibilityIdentifier("sales.invoice.sale")
                NavigationLink(slText("sales.invoice.amendSaleTitle")) { SalesInvoiceList(workspace: workspace, action: .edit) }
                    .accessibilityIdentifier("sales.invoice.amendSale")
                NavigationLink(slText("sales.proof")) {
                    #if DEBUG
                    if workspace.evidence != nil, ProcessInfo.processInfo.environment["ACAS_COMPACT_REPORT"] == "1" {
                        SalesProofView(workspace: workspace)
                            .environment(\.horizontalSizeClass, .compact)
                    } else {
                        SalesProofView(workspace: workspace)
                    }
                    #else
                    SalesProofView(workspace: workspace)
                    #endif
                }
                .accessibilityIdentifier("sales.proof")
                NavigationLink(slText("sales.post.title")) { SalesPostingView(workspace: workspace) }
                    .accessibilityIdentifier("sales.post")
                NavigationLink(slText("sales.invoice.menuTitle")) { SalesInvoiceMenu(workspace: workspace) }
                    .accessibilityIdentifier("sales.invoice.menu")
            }
            Section(slText("sales.payment.section")) {
                NavigationLink(slText("sales.payment.entry")) {
                    SalesPaymentGate(workspace: workspace, operation: .entry, title: "sales.payment.entry") {
                        SalesPaymentsView(workspace: workspace)
                    }
                }
                .accessibilityIdentifier("sales.payment.entry")
                NavigationLink(slText("sales.payment.amend")) {
                    SalesPaymentGate(workspace: workspace, operation: .amend, title: "sales.payment.amend") {
                        SalesPaymentAmendView(workspace: workspace)
                    }
                }
                .accessibilityIdentifier("sales.payment.amend")
                NavigationLink(slText("sales.payment.proof")) {
                    SalesPaymentGate(workspace: workspace, operation: .proof, title: "sales.payment.proof") {
                        SalesPaymentProofView(workspace: workspace)
                    }
                }
                .accessibilityIdentifier("sales.payment.proof")
                NavigationLink(slText("sales.payment.post")) {
                    SalesPaymentGate(workspace: workspace, operation: .post, title: "sales.payment.post") {
                        SalesPaymentPostingView(workspace: workspace)
                    }
                }
                .accessibilityIdentifier("sales.payment.post")
            }
            Section(slText("sales.analysis.section")) {
                NavigationLink(slText("sales.analysis.codes")) { SalesAnalysisMenu(workspace: workspace) }
                    .accessibilityIdentifier("sales.analysis.codes")
                NavigationLink(slText("sales.analysis.totals")) { SalesAnalysisReportView(workspace: workspace, kind: .totals) }
                    .accessibilityIdentifier("sales.analysis.totals")
            }
            Section(slText("sales.period.section")) {
                NavigationLink(slText("sales.dayBook.title")) { SalesDayBookView(workspace: workspace) }
                    .accessibilityIdentifier("sales.dayBook")
                NavigationLink(slText("sales.period.title")) { SalesPeriodCloseView(workspace: workspace) }
                    .accessibilityIdentifier("sales.period")
            }
            Section(slText("sales.receivables.section")) {
                NavigationLink(slText("sales.statement.title")) { SalesStatementsView(workspace: workspace) }
                    .accessibilityIdentifier("sales.statement")
                NavigationLink(slText("sales.dunning.title")) { SalesDunningView(workspace: workspace) }
                    .accessibilityIdentifier("sales.dunning")
                NavigationLink(slText("sales.customer.report.alphabetical")) {
                    SalesCustomerReportView(workspace: workspace, kind: .alphabetical)
                }
                .accessibilityIdentifier("sales.customer.alphabetical")
                NavigationLink(slText("sales.customer.report.turnover")) {
                    SalesCustomerReportView(workspace: workspace, kind: .turnover)
                }
                .accessibilityIdentifier("sales.customer.turnover")
            }
        }
    }
}

private struct SalesProofView: View {
    let workspace: Workspace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var entries: [SalesProofReport.Entry]?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "sales.action.generate", table: "SL"), systemImage: "doc.badge.plus", action: generate)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("action.generate")
            }
            .padding()
            if let entries {
                Table(entries) {
                    TableColumn(String(localized: "sales.proof.customer", table: "SL")) { entry in
                        if horizontalSizeClass == .compact {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.customer)
                                Text(entry.name)
                                amountRow("sales.proof.net", entry.net, id: "net")
                                amountRow("sales.proof.tax", entry.tax, id: "tax")
                                amountRow("sales.proof.gross", entry.gross, id: "gross")
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text(entry.customer)
                        }
                    }
                    TableColumn(String(localized: "sales.proof.name", table: "SL")) { Text($0.name) }
                    TableColumn(String(localized: "sales.proof.net", table: "SL")) { Text(amount($0.net)) }
                    TableColumn(String(localized: "sales.proof.tax", table: "SL")) { Text(amount($0.tax)) }
                    TableColumn(String(localized: "sales.proof.gross", table: "SL")) { Text(amount($0.gross)) }
                }
                .accessibilityIdentifier("sales.proof.preview")
            } else {
                ContentUnavailableView(String(localized: "sales.proof.ready", table: "SL"), systemImage: "doc.text")
            }
        }
        .navigationTitle(String(localized: "sales.proof", table: "SL"))
        .alert(String(localized: "sales.proof.failed", table: "SL"), isPresented: $failed) {
            Button("action.close", role: .cancel) {}
        }
    }

    private func generate() {
        do {
            entries = try SalesProofReport.generate(in: workspace.context)
            workspace.completed("sales-proof")
        } catch {
            failed = true
        }
    }

    private func amount(_ value: Int64) -> String {
        (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
    }

    private func amountRow(_ label: String.LocalizationValue, _ value: Int64, id: String) -> some View {
        HStack {
            Text(String(localized: label, table: "SL"))
            Spacer()
            Text(amount(value))
                .accessibilityIdentifier("sales.proof.compact." + id)
        }
    }
}
