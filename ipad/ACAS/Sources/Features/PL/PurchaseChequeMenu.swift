import ACASCore
import SwiftUI

struct PurchaseChequeMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            ForEach(PurchaseChequeScreen.Mode.allCases) { mode in
                NavigationLink(mode.title) { PurchaseChequeScreen(workspace: workspace, mode: mode) }
                    .accessibilityIdentifier("pl.cheques." + mode.rawValue)
            }
        }
        .navigationTitle(plString("purchase.cheques.menu"))
    }
}

private struct PurchaseChequeScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case generate, amend, proof, issue, register, remittance
        var id: String { rawValue }
        var title: String { plString("purchase.cheques." + rawValue) }
    }

    let workspace: Workspace
    let mode: Mode
    @State private var age = ""
    @State private var firstNumber = ""
    @State private var date = Date()
    @State private var schedules: [PurchaseLedger.ScheduledPayment] = []
    @State private var output: Data?
    @State private var confirmation = false
    @State private var error: PurchaseNotice?

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        Form {
            switch mode {
            case .generate:
                TextField(plString("purchase.cheques.age"), text: $age)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("pl.cheques.age")
            case .issue:
                TextField(plString("purchase.cheques.number"), text: $firstNumber)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("pl.cheques.number")
                DatePicker(plString("purchase.cheques.date"), selection: $date, displayedComponents: .date)
            default:
                EmptyView()
            }
            if mode != .amend {
                Button(mode.title) {
                    if mode == .register { confirmation = true } else { run() }
                }
                .disabled((mode == .issue || mode == .register) && schedules.isEmpty)
                .accessibilityIdentifier("pl.cheques.run")
            }
            if let output {
                ShareLink(item: output, preview: SharePreview(mode.title))
                    .accessibilityIdentifier("pl.cheques.share")
            }
            if mode != .remittance {
                if schedules.isEmpty { Text(plString("purchase.cheques.empty")) }
                ForEach(schedules) { schedule in
                    Section {
                        LabeledContent(plString(schedule.bankTransfer ? "purchase.cheques.bank" : "purchase.cheques.paper"),
                                       value: purchaseAmount(schedule.amount))
                        ForEach(schedule.lines) { line in
                            if mode == .amend && line.amount != 0 {
                                NavigationLink {
                                    PurchaseScheduledLineForm(workspace: workspace, schedule: schedule, line: line)
                                } label: {
                                    LabeledContent(String(line.folio), value: purchaseAmount(line.amount))
                                }
                                .accessibilityIdentifier("pl.cheques.line.\(line.id)")
                            } else {
                                LabeledContent(String(line.folio), value: purchaseAmount(line.amount))
                            }
                        }
                    } header: {
                        Text("\(schedule.supplier) / \(schedule.sequence)")
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .onAppear {
            age = String(ledger.scheduleAge)
            date = ledger.processingDate
            schedules = ledger.paymentSchedule()
        }
        .confirmationDialog(plString("purchase.cheques.register.confirm"), isPresented: $confirmation, titleVisibility: .visible) {
            Button(mode.title, action: run)
            Button(plString("purchase.action.cancel"), role: .cancel) {}
        }
        .purchaseAlert($error)
    }

    private func run() {
        output = nil
        do {
            switch mode {
            case .generate:
                guard let days = Int64(age) else { throw PurchaseLedger.ScheduleError.invalidAge }
                try ledger.generatePaymentSchedule(age: days)
            case .amend:
                return
            case .proof:
                try ledger.proofPaymentSchedule()
            case .issue:
                guard let number = Int64(firstNumber) else { throw PurchaseLedger.ScheduleError.invalidChequeNumber }
                output = try ledger.generateChequeFile(firstNumber: number, date: date)
            case .register:
                try ledger.registerScheduledPayments()
            case .remittance:
                try ledger.remittanceAdvice()
            }
            if mode != .issue {
                output = workspace.context.store.readRaw(PurchaseLedger.reportPath).map { Data($0) }
            }
            schedules = ledger.paymentSchedule()
            workspace.completed("pl.cheques." + mode.rawValue)
        } catch { self.error = PurchaseNotice(error) }
    }
}

private struct PurchaseScheduledLineForm: View {
    let workspace: Workspace
    let schedule: PurchaseLedger.ScheduledPayment
    let line: PurchaseLedger.ScheduledPayment.Line
    @State private var amount = ""
    @State private var error: PurchaseNotice?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            LabeledContent(plString("purchase.invoice.number"), value: String(line.folio))
            if !line.reference.isEmpty {
                LabeledContent(plString("purchase.cheques.reference"), value: line.reference)
            }
            TextField(plString("purchase.payment.amount"), text: $amount)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("pl.cheques.amount")
            Button(plString("purchase.action.save"), action: save)
        }
        .navigationTitle(plString("purchase.cheques.amend"))
        .onAppear { amount = (Decimal(line.amount) / 100).formatted(.number.grouping(.never).precision(.fractionLength(2))) }
        .purchaseAlert($error)
    }

    private func save() {
        do {
            let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
            guard let whole = parts.first, (1...7).contains(whole.count), whole.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let units = Int64(whole), parts.count <= 2 else { throw PurchaseLedger.ScheduleError.invalidSchedule }
            var cents: Int64 = 0
            if parts.count == 2 {
                let fraction = parts[1]
                guard (1...2).contains(fraction.count), fraction.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let value = Int64(fraction) else { throw PurchaseLedger.ScheduleError.invalidSchedule }
                cents = fraction.count == 1 ? value * 10 : value
            }
            try PurchaseLedger(workspace.context).amendPaymentSchedule(
                supplier: schedule.supplier, sequence: schedule.sequence, line: line.id, amount: units * 100 + cents)
            workspace.completed("pl.cheques.amend")
            dismiss()
        } catch { self.error = PurchaseNotice(error) }
    }
}
