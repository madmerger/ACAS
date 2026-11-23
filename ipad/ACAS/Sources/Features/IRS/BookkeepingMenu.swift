import ACASCore
import SwiftUI
import UniformTypeIdentifiers

struct BookkeepingMenu: View {
    let workspace: Workspace
    let closeBookkeeping: () -> Void

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
            Button(irsText("action.close"), action: closeBookkeeping)
                .accessibilityIdentifier("irs.close")
        }
        .onAppear { workspace.completed("irs.menu.open") }
    }

    private var accountMenu: some View {
        List {
            link(irsText("accounts.create"), "accountCreate") { BookkeepingAccountForm(workspace: workspace, editing: false) }
            link(irsText("accounts.edit"), "accountEdit") { BookkeepingAccountForm(workspace: workspace, editing: true) }
            link(irsText("accounts.list"), "accountList") { accountTable(irsText("accounts.list")) }
            link(irsText("accounts.print"), "accountPrint") {
                report(.accounts, workflow: "irs.accountPrint") { accountTable(irsText("accounts.print")) }
            }
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
            link(irsText("defaults.print"), "defaultPrint") {
                report(.defaults, workflow: "irs.defaultPrint") { defaultTable(irsText("defaults.print")) }
            }
            link(irsText("defaults.statementSettings"), "statementSettings") { defaultTable(irsText("defaults.statementSettings")) }
        }
        .navigationTitle(irsText("menu.defaults"))
    }

    private func link<Content: View>(_ title: String, _ id: String,
                                     @ViewBuilder destination: () -> Content) -> some View {
        NavigationLink(title) {
            destination()
                .onAppear { workspace.completed("irs." + id + ".open") }
        }
        .accessibilityIdentifier("irs." + id)
    }

    private func accountTable(_ title: String) -> some View {
        BookkeepingAccountTable(service: service, title: title)
    }

    private func report<Content: View>(_ report: BookkeepingService.Report, workflow: String,
                                       @ViewBuilder preview: () -> Content) -> some View {
        BookkeepingReportPreview(workspace: workspace, report: report, workflow: workflow, preview: preview())
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

private struct BookkeepingReportPreview<Content: View>: View {
    let workspace: Workspace
    let report: BookkeepingService.Report
    let workflow: String
    let preview: Content
    @State private var message = ""
    @State private var document: BookkeepingReportDocument?
    @State private var exporting = false

    var body: some View {
        preview
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(irsText("action.generateReport")) {
                        do {
                            document = BookkeepingReportDocument(
                                data: try BookkeepingService(workspace.context).printReport(report)
                            )
                            message = irsText("result.reportGenerated")
                            workspace.completed(workflow)
                        } catch {
                            document = nil
                            message = bookkeepingError(error)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("irs.generateReport")
                    if document != nil {
                        Button(irsText("action.exportReport")) { exporting = true }
                            .accessibilityIdentifier("irs.exportReport")
                    }
                    Text(message).accessibilityIdentifier("irs.reportResult")
                }
                .padding()
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: "prt-1") {
                if case .failure = $0 { message = irsText("error.exportReport") }
            }
    }
}

private struct BookkeepingReportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct BookkeepingAccountTable: View {
    let service: BookkeepingService
    let title: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var accounts: [BookkeepingService.Account] = []

    var body: some View {
        Table(accounts) {
            TableColumn(irsText("field.accountCode")) { account in
                VStack(alignment: .leading) {
                    Text(verbatim: String(account.code))
                    if horizontalSizeClass == .compact {
                        Text(account.name)
                        LabeledContent(irsText("field.debit"), value: (Decimal(account.debit) / 100).formatted())
                        LabeledContent(irsText("field.credit"), value: (Decimal(account.credit) / 100).formatted())
                    }
                }
            }
            TableColumn(irsText("field.accountName"), value: \.name)
            TableColumn(irsText("field.category")) { Text($0.category?.title ?? "") }
            TableColumn(irsText("field.debit")) { Text((Decimal($0.debit) / 100).formatted()) }
            TableColumn(irsText("field.credit")) { Text((Decimal($0.credit) / 100).formatted()) }
        }
        .navigationTitle(title)
        .onAppear { accounts = service.accounts }
    }
}

private struct BookkeepingRecalculate: View {
    let service: BookkeepingService
    @State private var confirming = false
    @State private var password = ""
    @State private var status = ""

    var body: some View {
        Form {
            SecureField(irsText("field.password"), text: $password)
            Button(irsText("action.recalculate"), role: .destructive) { confirming = true }
            if !status.isEmpty { Text(status) }
        }
        .navigationTitle(irsText("menu.recalculate"))
        .confirmationDialog(irsText("recalculate.confirm"), isPresented: $confirming, titleVisibility: .visible) {
            Button(irsText("action.confirmRecalculate"), role: .destructive) {
                do {
                    try service.recalculate(password: password)
                    status = irsText("result.recalculated")
                } catch { status = bookkeepingError(error) }
                password = ""
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
    case .wrongPassword: irsText("error.wrongPassword")
    default: irsText("error.invalid")
    }
}
