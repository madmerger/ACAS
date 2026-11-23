import ACASCore
import SwiftUI

struct BookkeepingMenu: View {
    let workspace: Workspace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var service: BookkeepingService { BookkeepingService(workspace.context) }

    var body: some View {
        List {
            link(irsText("menu.settings"), "settings") { BookkeepingConfigurationForm(workspace: workspace) }
            link(irsText("menu.accounts"), "accounts") { accountMenu }
            link(irsText("menu.defaults"), "defaults") { defaultMenu }
            link(irsText("menu.post"), "post") { BookkeepingPostingForm(workspace: workspace) }
            link(irsText("menu.trialBalance"), "trialBalance") { accountTable(irsText("menu.trialBalance")) }
            link(irsText("menu.audit"), "audit") { journal(irsText("menu.audit")) }
            link(irsText("menu.statements"), "statements") { accountTable(irsText("menu.statements")) }
            link(irsText("menu.amendment"), "amendment") { journal(irsText("menu.amendment")) }
            link(irsText("menu.analysis"), "analysis") { journal(irsText("menu.analysis")) }
            link(irsText("menu.recalculate"), "recalculate") { BookkeepingRecalculate(service: service) }
        }
    }

    private var accountMenu: some View {
        List {
            link(irsText("accounts.create"), "accountCreate") { BookkeepingAccountForm(workspace: workspace, editing: false) }
            link(irsText("accounts.edit"), "accountEdit") { BookkeepingAccountForm(workspace: workspace, editing: true) }
            link(irsText("accounts.list"), "accountList") { accountTable(irsText("accounts.list")) }
            link(irsText("accounts.print"), "accountPrint") { accountTable(irsText("accounts.print")) }
            link(irsText("accounts.export"), "accountExport") { accountTable(irsText("accounts.export")) }
            link(irsText("accounts.import"), "accountImport") { accountTable(irsText("accounts.import")) }
        }
        .navigationTitle(irsText("menu.accounts"))
    }

    private var defaultMenu: some View {
        List {
            link(irsText("defaults.create"), "defaultCreate") { BookkeepingDefaultForm(workspace: workspace, editing: false) }
            link(irsText("defaults.edit"), "defaultEdit") { BookkeepingDefaultForm(workspace: workspace, editing: true) }
            link(irsText("defaults.list"), "defaultList") { defaultTable(irsText("defaults.list")) }
            link(irsText("defaults.print"), "defaultPrint") { defaultTable(irsText("defaults.print")) }
            link(irsText("defaults.statementSettings"), "statementSettings") { defaultTable(irsText("defaults.statementSettings")) }
        }
        .navigationTitle(irsText("menu.defaults"))
    }

    private func link<Content: View>(_ title: String, _ id: String,
                                     @ViewBuilder destination: () -> Content) -> some View {
        NavigationLink(title, destination: destination)
            .accessibilityIdentifier("irs." + id)
    }

    private func accountTable(_ title: String) -> some View {
        Table(service.accounts) {
            TableColumn(irsText("field.accountCode")) { account in
                VStack(alignment: .leading) {
                    Text(verbatim: String(account.code))
                    if horizontalSizeClass == .compact { Text(account.name) }
                }
            }
            TableColumn(irsText("field.accountName"), value: \.name)
            TableColumn(irsText("field.category")) { Text($0.category?.title ?? "") }
            TableColumn(irsText("field.debit")) { Text((Decimal($0.debit) / 100).formatted()) }
            TableColumn(irsText("field.credit")) { Text((Decimal($0.credit) / 100).formatted()) }
        }
        .navigationTitle(title)
    }

    private func defaultTable(_ title: String) -> some View {
        Table(service.defaults.filter { $0.account != 0 }) {
            TableColumn(irsText("field.registration")) { Text(verbatim: String($0.id)) }
            TableColumn(irsText("field.account")) { Text(verbatim: String($0.account)) }
            TableColumn(irsText("field.abbreviation"), value: \.label)
            TableColumn(irsText("field.tax")) { Text($0.usesTax ? irsText("field.applicable") : irsText("field.notApplicable")) }
        }
        .navigationTitle(title)
    }

    @ViewBuilder private func journal(_ title: String) -> some View {
        if service.postings.isEmpty {
            ContentUnavailableView(irsText("journal.empty"), systemImage: "doc.text")
                .navigationTitle(title)
        } else {
            Table(service.postings) {
                TableColumn(irsText("field.journalNumber")) { Text(verbatim: String($0.id)) }
                TableColumn(irsText("field.debitAccount")) { Text(verbatim: String($0.debit)) }
                TableColumn(irsText("field.creditAccount")) { Text(verbatim: String($0.credit)) }
                TableColumn(irsText("field.narrative"), value: \.description)
                TableColumn(irsText("field.amount")) { Text((Decimal($0.amount) / 100).formatted()) }
            }
            .navigationTitle(title)
        }
    }
}

private struct BookkeepingRecalculate: View {
    let service: BookkeepingService
    @State private var confirming = false
    @State private var status = ""

    var body: some View {
        Form {
            Button(irsText("action.recalculate"), role: .destructive) { confirming = true }
            if !status.isEmpty { Text(status) }
        }
        .navigationTitle(irsText("menu.recalculate"))
        .confirmationDialog(irsText("recalculate.confirm"), isPresented: $confirming, titleVisibility: .visible) {
            Button(irsText("action.confirmRecalculate"), role: .destructive) {
                do {
                    try service.recalculate()
                    status = irsText("result.recalculated")
                } catch { status = bookkeepingError(error) }
            }
        }
    }
}

extension BookkeepingService.Category {
    var title: String {
        switch self {
        case .assets: irsText("category.asset")
        case .liabilities: irsText("category.liability")
        case .income: irsText("category.income")
        case .expense: irsText("category.expense")
        case .other: irsText("category.other")
        }
    }
}

func bookkeepingError(_ error: Error) -> String {
    switch error as? BookkeepingService.Failure {
    case .duplicateAccount: irsText("error.duplicateAccount")
    case .missingAccount: irsText("error.missingAccount")
    case .missingDefault: irsText("error.missingDefault")
    case .missingPosting: irsText("error.missingPosting")
    default: irsText("error.invalid")
    }
}
