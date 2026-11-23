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
            link(irsText("menu.post"), "post") { postingMenu }
            link(irsText("menu.trialBalance"), "trialBalance") { BookkeepingTrialBalanceForm(workspace: workspace) }
            link(irsText("menu.audit"), "audit") {
                BookkeepingAuditOptions { journal(irsText("journal.list")) }
            }
            link(irsText("menu.statements"), "statements") { BookkeepingStatementOptions(workspace: workspace) }
            link(irsText("menu.amendment"), "amendment") { postingJournal("amendment") }
            link(irsText("menu.analysis"), "analysis") { postingJournal("analysis") }
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
            link(irsText("accounts.export"), "accountExport") { BookkeepingAccountArchiveForm(workspace: workspace, importing: false) }
            link(irsText("accounts.import"), "accountImport") { BookkeepingAccountArchiveForm(workspace: workspace, importing: true) }
        }
        .navigationTitle(irsText("menu.accounts"))
    }

    private var postingMenu: some View {
        List {
            NavigationLink(irsText("defaults.list")) { defaultTable(irsText("defaults.list")) }
                .accessibilityIdentifier("irs.postDefaults")
            NavigationLink(irsText("posting.append")) { BookkeepingPostingForm(workspace: workspace) }
                .accessibilityIdentifier("irs.postAppend")
            link(irsText("posting.clear"), "postClear") { BookkeepingPostingClearAuthentication() }
            Text(irsText("posting.import"))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("irs.postImport")
            Text(irsText("posting.unavailable")).font(.footnote)
        }
        .navigationTitle(irsText("menu.post"))
    }

    private var defaultMenu: some View {
        List {
            link(irsText("defaults.create"), "defaultCreate") { BookkeepingDefaultForm(workspace: workspace, editing: false) }
            link(irsText("defaults.edit"), "defaultEdit") { BookkeepingDefaultForm(workspace: workspace, editing: true) }
            link(irsText("defaults.list"), "defaultList") { defaultTable(irsText("defaults.list")) }
            link(irsText("defaults.print"), "defaultPrint") {
                report(.defaults, workflow: "irs.defaultPrint") { defaultTable(irsText("defaults.print")) }
            }
            link(irsText("defaults.statementSettings"), "statementSettings") { BookkeepingStatementSettingsForm(workspace: workspace) }
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
            TableColumn(irsText("field.tax")) { Text($0.tax.title) }
        }
        .navigationTitle(title)
    }

    @ViewBuilder private func postingJournal(_ destination: String) -> some View {
        let title = irsText("menu." + destination)
        if service.hasPostingFile {
            journal(title)
        } else {
            ContentUnavailableView {
                Label(irsText("error.openPosting"), systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("irs.openPostingError")
            }
            .navigationTitle(title)
            .onAppear { workspace.completed("irs." + destination + ".missingPosting") }
        }
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

private struct BookkeepingAuditOptions<Journal: View>: View {
    @ViewBuilder let journal: () -> Journal
    @State private var kind = ""
    @State private var output = ""
    @State private var sort = ""

    var body: some View {
        Form {
            Picker(irsText("audit.kind"), selection: $kind) {
                Text(irsText("field.choose")).tag("")
                Text(irsText("audit.audit")).tag("audit")
                Text(irsText("audit.ledger")).tag("ledger")
                Text(irsText("audit.tax")).tag("tax")
            }
            .accessibilityIdentifier("irs.auditKind")
            .accessibilityValue(irsText(kind.isEmpty ? "field.choose" : "audit." + kind))
            Picker(irsText("trialBalance.output"), selection: $output) {
                Text(irsText("field.choose")).tag("")
                Text(irsText("trialBalance.display")).tag("display")
                Text(irsText("trialBalance.print")).tag("print")
            }
            .accessibilityIdentifier("irs.auditOutput")
            .accessibilityValue(irsText(output.isEmpty ? "field.choose" : "trialBalance." + output))
            Picker(irsText("audit.sort"), selection: $sort) {
                Text(irsText("field.choose")).tag("")
                Text(irsText("audit.code")).tag("code")
                Text(irsText("audit.date")).tag("date")
                Text(irsText("audit.number")).tag("number")
            }
            .accessibilityIdentifier("irs.auditSort")
            .accessibilityValue(irsText(sort.isEmpty ? "field.choose" : "audit." + sort))
            Text(irsText("audit.unavailable")).font(.footnote)
            NavigationLink(irsText("journal.list"), destination: journal)
        }
        .navigationTitle(irsText("menu.audit"))
    }
}

private struct BookkeepingPostingClearAuthentication: View {
    @State private var password = ""

    var body: some View {
        Form {
            Text(irsText("posting.clearBackup"))
            SecureField(irsText("field.password"), text: $password)
                .accessibilityIdentifier("irs.postClearPassword")
            Text(irsText("posting.clearUnavailable")).font(.footnote)
        }
        .navigationTitle(irsText("posting.clear"))
    }
}

private struct BookkeepingStatementOptions: View {
    let workspace: Workspace
    @State private var comparison = 0
    @State private var message = ""
    @State private var ready = false

    var body: some View {
        Form {
            Picker(irsText("statement.comparison"), selection: $comparison) {
                Text(irsText("statement.noComparison")).tag(0)
                ForEach(1...4, id: \.self) { slot in
                    Text(String(format: irsText("statement.comparisonSlot"), slot)).tag(slot)
                }
            }
            .accessibilityIdentifier("irs.statementComparison")
            .accessibilityValue(comparison == 0 ? irsText("statement.noComparison")
                : String(format: irsText("statement.comparisonSlot"), comparison))
            NavigationLink(irsText("statement.continue")) { BookkeepingAnnualStatementForm(workspace: workspace) }
                .disabled(!ready || comparison != 0)
                .accessibilityIdentifier("irs.statementContinue")
            if !message.isEmpty { Text(message) }
        }
        .navigationTitle(irsText("menu.statements"))
        .onAppear {
            do {
                try BookkeepingService(workspace.context).prepareStatementAccounts()
                ready = true
                workspace.completed("irs.statements.prepare")
            } catch { message = bookkeepingError(error) }
        }
    }
}

private struct BookkeepingAnnualStatementForm: View {
    let workspace: Workspace
    @State private var title = ""
    @State private var message = ""
    @State private var document: BookkeepingReportDocument?
    @State private var exporting = false

    var body: some View {
        Form {
            TextField(irsText("statement.title"), text: $title, prompt: Text(irsText("statement.defaultTitle")))
                .accessibilityIdentifier("irs.statementTitle")
            Button(irsText("statement.generateAnnual")) {
                do {
                    let statement = try BookkeepingService(workspace.context).printAnnualStatement(title: title)
                    document = BookkeepingReportDocument(data: statement.data)
                    message = irsText(statement.interrupted ? "statement.interrupted" : "result.reportGenerated")
                    workspace.completed("irs.statements.annual")
                } catch {
                    document = nil
                    message = bookkeepingError(error)
                }
            }
            .accessibilityIdentifier("irs.generateAnnualStatement")
            if document != nil {
                Button(irsText("action.exportReport")) { exporting = true }
                    .accessibilityIdentifier("irs.exportReport")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.annualStatementResult") }
        }
        .navigationTitle(irsText("statement.profitAndLoss"))
        .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: "prt-1") {
            if case .failure = $0 { message = irsText("error.exportReport") }
        }
    }
}

private struct BookkeepingTrialBalanceForm: View {
    let workspace: Workspace
    @State private var summary: Bool?
    @State private var zeroBalances: Bool?
    @State private var printing: Bool?
    @State private var showingBalance = false

    var body: some View {
        Group {
            if printing == true, let summary, let zeroBalances {
                BookkeepingReportPreview(workspace: workspace,
                    report: .trialBalance(summary: summary, zeroBalances: zeroBalances),
                    workflow: "irs.trialBalance", preview: options)
            } else {
                options
            }
        }
        .navigationTitle(irsText("menu.trialBalance"))
        .sheet(isPresented: $showingBalance) {
            if let summary, let zeroBalances {
                let result = BookkeepingService(workspace.context).trialBalance(summary: summary, zeroBalances: zeroBalances)
                NavigationStack {
                    List {
                        ForEach(result.rows) { row in
                            Section(String(row.account.child == 0 ? row.account.code : row.account.child) + "  " + row.account.name) {
                                amounts(debit: row.debit, credit: row.credit)
                            }
                        }
                        Section(irsText("trialBalance.total")) {
                            amounts(debit: result.debit, credit: result.credit)
                        }
                    }
                    .navigationTitle(irsText("menu.trialBalance"))
                    .toolbar { Button(irsText("action.close")) { showingBalance = false } }
                }
            }
        }
    }

    private var options: some View {
        Form {
            Picker(irsText("trialBalance.scope"), selection: $summary) {
                Text(irsText("field.choose")).tag(nil as Bool?)
                Text(irsText("trialBalance.summary")).tag(true)
                Text(irsText("trialBalance.detail")).tag(false)
            }
            .accessibilityIdentifier("irs.trialBalanceScope")
            .accessibilityValue(option(summary, "summary", "detail"))
            Picker(irsText("trialBalance.zero"), selection: $zeroBalances) {
                Text(irsText("field.choose")).tag(nil as Bool?)
                Text(irsText("trialBalance.includeZero")).tag(true)
                Text(irsText("trialBalance.excludeZero")).tag(false)
            }
            .accessibilityIdentifier("irs.trialBalanceZero")
            .accessibilityValue(option(zeroBalances, "includeZero", "excludeZero"))
            Picker(irsText("trialBalance.output"), selection: $printing) {
                Text(irsText("field.choose")).tag(nil as Bool?)
                Text(irsText("trialBalance.display")).tag(false)
                Text(irsText("trialBalance.print")).tag(true)
            }
            .accessibilityIdentifier("irs.trialBalanceOutput")
            .accessibilityValue(option(printing, "print", "display"))
            if summary == false, zeroBalances == false, printing == true {
                Text(irsText("trialBalance.detailPrintIncludesZero"))
                    .accessibilityIdentifier("irs.trialBalancePrintNote")
            }
            if printing == false, summary != nil, zeroBalances != nil {
                Button(irsText("trialBalance.display")) { showingBalance = true }
            }
        }
    }

    private func option(_ setting: Bool?, _ yes: String, _ no: String) -> String {
        guard let setting else { return irsText("field.choose") }
        return irsText("trialBalance." + (setting ? yes : no))
    }

    private func amounts(debit: Int64, credit: Int64) -> some View {
        Group {
            LabeledContent(irsText("field.debit"), value: (Decimal(debit) / 100).formatted())
            LabeledContent(irsText("field.credit"), value: (Decimal(credit) / 100).formatted())
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
    @State private var generatedReport: BookkeepingService.Report?

    var body: some View {
        preview
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(irsText("action.generateReport")) {
                        do {
                            document = BookkeepingReportDocument(
                                data: try BookkeepingService(workspace.context).printReport(report)
                            )
                            generatedReport = report
                            message = irsText("result.reportGenerated")
                            workspace.completed(workflow)
                        } catch {
                            document = nil
                            message = bookkeepingError(error)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("irs.generateReport")
                    if document != nil, generatedReport == report {
                        Button(irsText("action.exportReport")) { exporting = true }
                            .accessibilityIdentifier("irs.exportReport")
                    }
                    Text(message).accessibilityIdentifier("irs.reportResult")
                }
                .padding()
            }
            .onChange(of: report) {
                document = nil
                generatedReport = nil
                message = ""
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: "prt-1") {
                if case .failure = $0 { message = irsText("error.exportReport") }
            }
    }
}

struct BookkeepingReportDocument: FileDocument {
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

extension BookkeepingService.DefaultTax {
    var title: String {
        switch self {
        case .none: irsText("tax.none")
        case .input: irsText("tax.input")
        case .output: irsText("tax.output")
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
    case .accountArchiveTooLarge: irsText("archive.tooLarge")
    default: irsText("error.invalid")
    }
}
