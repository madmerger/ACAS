import ACASCore
import SwiftUI

func plString(_ key: String) -> String {
    NSLocalizedString(key, tableName: "PL", comment: "")
}

struct PurchaseMenu: View {
    let workspace: Workspace
    @State private var opening = true
    @State private var destination: PurchaseLedger.MenuAction?
    @State private var notice: PurchaseNotice?

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        List {
            NavigationLink(plString("purchase.date")) { PurchaseDateForm(workspace: workspace) }
                .accessibilityIdentifier("pl.date")
            NavigationLink(plString("purchase.supplier.menu")) { PurchaseSupplierMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.suppliers")
            gated("purchase.enquiry", "pl.enquiry", .enquiry)
            NavigationLink(plString("purchase.invoice.add")) {
                PurchaseTransactionForm(workspace: workspace, transaction: .init(date: ledger.processingDate))
            }
            .accessibilityIdentifier("pl.transaction.add")
            NavigationLink(plString("purchase.invoice.edit")) { PurchaseTransactionsView(workspace: workspace, mode: .edit) }
                .accessibilityIdentifier("pl.transaction.edit")
            gated("purchase.invoice.delete", "pl.transaction.delete", .invoiceDelete)
            gated("purchase.invoice.proof", "pl.transaction.proof", .invoiceProof)
            gated("purchase.invoice.post", "pl.transaction.post", .invoicePost)
            gated("purchase.payment.add", "pl.payment.add", .paymentAdd)
            gated("purchase.payment.edit", "pl.payment.edit", .paymentEdit)
            gated("purchase.payment.proof", "pl.payment.proof", .paymentProof)
            gated("purchase.payment.post", "pl.payment.post", .paymentPost)
            NavigationLink(plString("purchase.cheques.menu")) { PurchaseChequeMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.cheques")
            NavigationLink(plString("purchase.analysis.menu")) { PurchaseAnalysisMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.analysis")
            NavigationLink(PurchaseReportView.Mode.analysis.title) { PurchaseReportView(workspace: workspace, mode: .analysis) }
                .accessibilityIdentifier("pl.report.analysis")
            NavigationLink(PurchaseReportView.Mode.dayBook.title) { PurchaseReportView(workspace: workspace, mode: .dayBook) }
                .accessibilityIdentifier("pl.report.day_book")
            gated("purchase.report.aged", "pl.report.aged", .agedReport)
            NavigationLink(PurchaseReportView.Mode.alphabetical.title) { PurchaseReportView(workspace: workspace, mode: .alphabetical) }
                .accessibilityIdentifier("pl.suppliers.alphabetical")
            NavigationLink(PurchaseReportView.Mode.turnover.title) { PurchaseReportView(workspace: workspace, mode: .turnover) }
                .accessibilityIdentifier("pl.report.turnover")
            NavigationLink(PurchaseReportView.Mode.file.title) { PurchaseReportView(workspace: workspace, mode: .file) }
                .accessibilityIdentifier("pl.report.supplier_file")
            NavigationLink(plString("purchase.close.title")) { PurchasePeriodCloseView(workspace: workspace) }
                .accessibilityIdentifier("pl.period.close")
            NavigationLink(plString("purchase.invoice.settings.menu")) { PurchaseInvoiceMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.invoice.settings.menu")
            NavigationLink(plString("purchase.settings")) { SystemMenu(workspace: workspace) }
                .accessibilityIdentifier("pl.settings")
        }
        .sheet(isPresented: $opening) {
            NavigationStack { PurchaseDateForm(workspace: workspace) }
        }
        .onAppear { if !opening { workspace.completed("pl.menu") } }
    }
}
        .purchaseAlert($notice)
        .navigationDestination(item: $destination) { action in
            switch action {
            case .enquiry: PurchaseSupplierLookup(workspace: workspace, mode: .enquiry)
            case .invoiceDelete: PurchaseTransactionsView(workspace: workspace, mode: .delete)
            case .invoiceProof: PurchaseTransactionsView(workspace: workspace, mode: .proof)
            case .invoicePost: PurchaseTransactionsView(workspace: workspace, mode: .post)
            case .paymentAdd: PurchasePaymentForm(workspace: workspace)
            case .paymentEdit: PurchasePaymentsView(workspace: workspace, mode: .edit)
            case .paymentProof: PurchasePaymentsView(workspace: workspace, mode: .proof)
            case .paymentPost: PurchasePaymentsView(workspace: workspace, mode: .post)
            case .agedReport: PurchaseReportView(workspace: workspace, mode: .aged)
            }
        }
    }

    private func gated(_ title: String, _ identifier: String, _ action: PurchaseLedger.MenuAction) -> some View {
        Button(plString(title)) {
            if let rejection = ledger.menuRejection(for: action) { notice = PurchaseNotice(rejection) }
            else { destination = action }
        }
        .accessibilityIdentifier(identifier)

private struct PurchaseDateForm: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var error: PurchaseNotice?

    var body: some View {
        Form {
            DatePicker(plString("purchase.date.value"), selection: $date, displayedComponents: .date)
                .accessibilityIdentifier("pl.date.value")
            Button(plString("purchase.action.confirm")) {
                do {
                    try PurchaseLedger(workspace.context).setProcessingDate(date)
                    workspace.completed("pl.date")
                    workspace.completed("pl.menu")
                    dismiss()
                } catch { self.error = PurchaseNotice(error) }
            }
            .accessibilityIdentifier("pl.date.confirm")
        }
        .navigationTitle(plString("purchase.date"))
        .onAppear { date = PurchaseLedger(workspace.context).processingDate }
        .purchaseAlert($error)
    }
}

struct PurchaseNotice: Identifiable {
    let message: String
    var id: String { message }

    init(_ error: Error) {
        if let error = error as? PurchaseLedger.PurchaseReportError {
            switch error {
        if let rejection = error as? PurchaseLedger.MenuRejection {
            message = rejection.rawValue + "： " + plString("purchase.menu.error." + rejection.rawValue)
            return
        }
            case .missingOpenItems: message = plString("purchase.report.error.open_items")
            case .proofRequired: message = plString("purchase.report.error.pending_payments")
            case .invalidMinimum: message = plString("purchase.report.error.minimum")
            }
            return
        }
        if let error = error as? PurchaseLedger.PeriodCloseError {
            switch error {
            case .uninitialized: message = plString("purchase.close.error.uninitialized")
            case .unpostedPayments: message = plString("purchase.close.error.payments")
            case .analysisRequired: message = plString("purchase.close.error.analysis")
            case .unpostedInvoices: message = plString("purchase.close.warning.invoices")
            case .incorrectPassword: message = plString("purchase.close.error.password")
            }
            return
        }
        if let error = error as? PurchaseLedger.ScheduleError {
            switch error {
            case .noSchedule: message = plString("purchase.cheques.error.empty")
            case .invalidSchedule: message = plString("purchase.cheques.error.amount")
            case .invalidAge: message = plString("purchase.cheques.error.age")
            case .invalidChequeNumber: message = plString("purchase.cheques.error.number")
            }
            return
        }
        if let error = error as? PurchaseLedger.PaymentError {
            switch error {
            case .invalidAmount: message = plString("purchase.error.payment.amount")
            case .paymentNotFound: message = plString("purchase.error.payment.missing")
            case .notProofed: message = plString("purchase.error.payment.proof")
            case .unavailableInvoice, .alreadyAllocated: message = plString("purchase.error.payment.invoice")
            case .issuedSchedule: message = plString("purchase.error.generic")
            }
            return
        }
        switch error as? PurchaseLedger.Error {
        case .invalidDate: message = plString("purchase.error.date")
        case .invalidCode: message = plString("purchase.error.code")
        case .invalidAddress: message = plString("purchase.error.address")
        case .missingAddress: message = plString("purchase.error.address.missing")
        case .addressTooLong: message = plString("purchase.error.address.tooLong")
        case .duplicateSupplier: message = plString("purchase.error.supplier.duplicate")
        case .supplierNotFound: message = plString("purchase.error.supplier.missing")
        case .supplierHasBalance: message = plString("purchase.error.supplier.balance")
        case .invalidTransaction: message = plString("purchase.error.invoice")
        case .transactionNotFound: message = plString("purchase.error.invoice.missing")
        case .alreadyPosted: message = plString("purchase.error.invoice.posted")
        case .duplicateTransaction: message = plString("purchase.error.invoice.duplicate")
        case .duplicateFolioAdvanced: message = plString("purchase.error.invoice.duplicate.advanced")
        case .analysisCodeNotFound: message = plString("purchase.error.analysis.missing")
        case .analysisFileIncompatible: message = plString("purchase.error.analysis.format")
        case .invalidInvoiceSettings: message = plString("purchase.error.invoice.settings")
        case nil: message = plString("purchase.error.generic")
        }
    }
}

extension View {
    func purchaseAlert(_ notice: Binding<PurchaseNotice?>) -> some View {
        alert(item: notice) {
            Alert(title: Text($0.message), dismissButton: .default(Text(plString("purchase.action.close"))))
        }
    }
}

func purchaseAmount(_ value: Int64) -> String {
    (Decimal(value) / 100).formatted(.number.precision(.fractionLength(2)))
}
