import ACASCore
import SwiftUI

struct PurchasePeriodCloseView: View {
    let workspace: Workspace
    @State private var status: PurchaseLedger.PeriodCloseStatus?
    @State private var dayBook: Data?
    @State private var analysis: Data?
    @State private var password = ""
    @State private var endQuarter = false
    @State private var confirming = false
    @State private var completed = false
    @State private var notice: PurchaseNotice?

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        Form {
            Section {
                if let status {
                    LabeledContent(plString("purchase.date"), value: status.date.formatted(.dateTime.year().month().day()))
                    if status.warnsAboutInvoices { Text(plString("purchase.close.warning.invoices")) }
                    if status.asksForQuarterEnd && !completed {
                        Toggle(plString("purchase.close.quarter"), isOn: $endQuarter)
                    }
                    if status.requiresPassword && !completed {
                        SecureField(plString("purchase.close.password"), text: $password)
                    }
                }
            } footer: {
                Text(plString("purchase.close.warning.backup"))
            }
            if let dayBook {
                ShareLink(item: dayBook, preview: SharePreview(plString("purchase.close.dayBook"))) {
                    Label(plString("purchase.close.dayBook"), systemImage: "square.and.arrow.up")
                }
            }
            if status?.needsPurchaseAnalysis == true {
                Button(plString("purchase.close.analysis")) { generateAnalysis() }
                    .accessibilityIdentifier("pl.period.close.analysis")
            }
            if let analysis {
                ShareLink(item: analysis, preview: SharePreview(plString("purchase.close.analysis.share"))) {
                    Label(plString("purchase.close.analysis.share"), systemImage: "square.and.arrow.up")
                }
            }
            if status?.needsSalesAnalysis == true { Text(plString("purchase.close.warning.salesAnalysis")) }
            if completed {
                Text(plString("purchase.close.completed"))
                    .accessibilityIdentifier("pl.period.close.completed")
            } else {
                Button(plString("purchase.close.run"), role: .destructive) { confirming = true }
                    .disabled(status == nil)
                    .accessibilityIdentifier("pl.period.close.run")
            }
        }
        .navigationTitle(plString("purchase.close.title"))
        .task {
            guard status == nil else { return }
            status = ledger.periodCloseStatus
            do { dayBook = try ledger.purchaseDayBook() } catch { notice = PurchaseNotice(error) }
        }
        .confirmationDialog(plString("purchase.close.confirm"), isPresented: $confirming, titleVisibility: .visible) {
            Button(plString("purchase.close.run"), role: .destructive, action: closePeriod)
                .accessibilityIdentifier("pl.period.close.confirm")
        } message: {
            Text(plString(status?.warnsAboutInvoices == true ? "purchase.close.confirm.invoices" : "purchase.close.warning.backup"))
        }
        .purchaseAlert($notice)
    }

    private func generateAnalysis() {
        analysis = nil
        do {
            analysis = try ledger.purchaseAnalysisReport()
            status = ledger.periodCloseStatus
        } catch { notice = PurchaseNotice(error) }
    }

    private func closePeriod() {
        defer { password = "" }
        do {
            try ledger.closePeriod(confirmUnpostedInvoices: status?.warnsAboutInvoices == true,
                                   password: password, endQuarter: endQuarter)
            completed = true
        } catch {
            status = ledger.periodCloseStatus
            notice = PurchaseNotice(error)
        }
    }
}
