import ACASCore
import SwiftUI

struct PeriodClosingLink: View {
    let workspace: Workspace
    let ledger: PeriodClosing.Ledger

    var body: some View {
        NavigationLink(intText("period.title")) {
            PeriodClosingView(workspace: workspace, initialLedger: ledger)
        }
        .accessibilityIdentifier(ledger == .sales ? "integration.salesPeriod" : "integration.purchasePeriod")
    }
}

struct PeriodClosingView: View {
    let workspace: Workspace
    let initialLedger: PeriodClosing.Ledger
    @State private var stage = Stage.backup
    @State private var date = Date()
    @State private var sales = false
    @State private var purchases = false
    @State private var password = ""
    @State private var proceedWithUnposted = false
    @State private var quarterEnd = false
    @State private var warning: PeriodClosing.Warning?
    @State private var message = ""

    private enum Stage { case backup, credentials, complete }
    private var service: PeriodClosing { PeriodClosing(workspace.context) }

    var body: some View {
        Form {
            switch stage {
            case .backup:
                Section(intText("period.backup")) {
                    Text(intText("period.backupNotice"))
                    DatePicker(intText("period.date"), selection: $date, displayedComponents: .date)
                    Button(intText("period.backupConfirmed")) {
                        do {
                            warning = try service.warning()
                            stage = .credentials
                            workspace.completed("integration." + (initialLedger == .sales ? "salesPeriod" : "purchasePeriod"))
                        } catch { show(error) }
                    }
                    .accessibilityIdentifier("integration.confirmBackup")
                }
            case .credentials:
                Section(intText("period.ledgers")) {
                    Toggle(intText("period.sales"), isOn: $sales)
                    Toggle(intText("period.purchases"), isOn: $purchases)
                }
                Section(intText("period.confirmation")) {
                    SecureField(intText("period.password"), text: $password)
                        .accessibilityIdentifier("integration.password")
                    if warning?.hasUnpostedInvoices == true {
                        Toggle(intText("period.proceedUnposted"), isOn: $proceedWithUnposted)
                    }
                    if warning?.requiresQuarterChoice == true {
                        Toggle(intText("period.quarter"), isOn: $quarterEnd)
                    }
                    Button(intText("period.perform"), role: .destructive, action: close)
                        .disabled(!sales && !purchases)
                }
            case .complete:
                Text(intText("period.completed"))
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("integration.result") }
        }
        .navigationTitle(intText("period.title"))
        .onAppear {
            date = workspace.context.now()
            sales = initialLedger == .sales
            purchases = initialLedger == .purchases
        }
    }

    private func close() {
        var ledgers: Set<PeriodClosing.Ledger> = []
        if sales { ledgers.insert(.sales) }
        if purchases { ledgers.insert(.purchases) }
        do {
            try service.close(ledgers, date: date, password: password, proceedWithUnposted: proceedWithUnposted,
                              endOfQuarter: quarterEnd)
            password = ""
            message = ""
            stage = .complete
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        switch error as? PeriodClosing.Failure {
        case .unconfigured: message = intText("error.unconfigured")
        case .missingLedger: message = intText("error.missingLedger")
        case .unfinishedUpdates: message = intText("error.unfinished")
        case .wrongPassword: message = intText("error.password")
        default: message = intText("error.date")
        }
    }
}
