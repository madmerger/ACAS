import ACASCore
import SwiftUI

struct FinancialStatementsForm: View {
    let workspace: Workspace
    @Environment(\.locale) private var locale
    @State private var confirming = false
    @State private var report: [UInt8]?
    @State private var status: String?

    var body: some View {
        Form {
            HStack {
                Text(ledgerText("financial-statements.date"))
                Spacer()
                Text(GeneralLedgerSetup(workspace.context).processingDate,
                     format: Date.FormatStyle(date: .long, time: .omitted, locale: locale,
                                              calendar: workspace.context.calendar, timeZone: workspace.context.timeZone))
                    .accessibilityIdentifier("gl.financial-statements.date")
            }
            Button(ledgerText("financial-statements.prepare")) { confirming = true }
                .accessibilityIdentifier("gl.financial-statements.prepare")
            if let status { Text(status).accessibilityIdentifier("gl.financial-statements.status") }
            if let report { LedgerReportShare(bytes: report) }
        }
        .environment(\.timeZone, workspace.context.timeZone)
        .environment(\.calendar, workspace.context.calendar)
        .navigationTitle(ledgerText("financial-statements"))
        .onAppear { workspace.completed("gl-financial-statements-date") }
        .confirmationDialog(ledgerText("financial-statements.confirm"), isPresented: $confirming, titleVisibility: .visible) {
            Button(ledgerText("financial-statements.print"), action: printReport)
                .accessibilityIdentifier("gl.financial-statements.print")
        }
    }

    private func printReport() {
        report = nil
        do {
            report = try FinancialStatements(workspace.context).generateReport()
            status = ledgerText("financial-statements.ready")
            workspace.completed("gl-financial-statements-print")
        } catch FinancialStatements.Error.missingLedger {
            status = ledgerText("trial-balance.missing")
        } catch {
            status = ledgerText("error.other")
        }
    }
}
