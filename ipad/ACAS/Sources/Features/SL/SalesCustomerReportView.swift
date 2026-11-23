import ACASCore
import SwiftUI

struct SalesCustomerReportView: View {
    let workspace: Workspace
    var kind: SalesCustomerReport.Kind = .listing
    @State private var code = ""
    @State private var status = SalesCustomerReport.Status.all
    @State private var creditDays = Criterion()
    @State private var invoiceCount = Criterion()
    @State private var averageValue = Criterion()
    @State private var overdueDays = Criterion()
    @State private var dateRelation: SalesCustomerReport.Relation?
    @State private var creationDate = Date()
    @State private var preview: Preview?
    @State private var showsError = false

    private var title: String.LocalizationValue {
        switch kind {
        case .listing: "sales.customer.report.title"
        case .alphabetical: "sales.customer.report.alphabetical"
        case .turnover: "sales.customer.report.turnover"
        }
    }

    var body: some View {
        Form {
            Button(slText("sales.action.generate"), systemImage: "doc.badge.plus", action: generate)
                .accessibilityIdentifier("sales.customer.report.generate")
            Section(slText("sales.customer.report.criteria")) {
                TextField(slText("sales.customer.report.code"), text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Picker(slText("sales.customer.status"), selection: $status) {
                    Text(slText("sales.customer.report.all")).tag(SalesCustomerReport.Status.all)
                    Text(slText("sales.customer.active")).tag(SalesCustomerReport.Status.active)
                    Text(slText("sales.customer.report.dormant")).tag(SalesCustomerReport.Status.dormant)
                }
                criterion("sales.customer.creditDays", $creditDays)
                criterion("sales.customer.report.invoiceCount", $invoiceCount)
                criterion("sales.customer.report.averageValue", $averageValue)
                criterion("sales.customer.report.overdueDays", $overdueDays)
                comparison("sales.customer.report.creationDate", $dateRelation)
                if dateRelation != nil {
                    DatePicker(slText("sales.customer.report.creationDate"), selection: $creationDate, displayedComponents: .date)
                        .environment(\.timeZone, workspace.context.timeZone)
                }
            }
        }
        .navigationTitle(slText(title))
        .alert(slText("sales.customer.report.failed"), isPresented: $showsError) {
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
        .sheet(item: $preview) { preview in
            NavigationStack {
                List(preview.entries) { entry in
                    VStack(alignment: .leading) {
                        LabeledContent(entry.code, value: entry.name)
                            .accessibilityIdentifier("sales.customer.report.row." + entry.code)
                        ForEach(entry.quarterlyTurnover.indices, id: \.self) { index in
                            LabeledContent(slText("sales.customer.report.quarter \(index + 1)"),
                                           value: (Decimal(entry.quarterlyTurnover[index]) / 100)
                                           .formatted(.number.precision(.fractionLength(2))))
                        }
                    }
                }
                .overlay {
                    if preview.entries.isEmpty {
                        ContentUnavailableView(slText("sales.customer.report.empty"), systemImage: "doc.text")
                    }
                }
                .accessibilityIdentifier("sales.customer.report.preview")
                .navigationTitle(slText(title))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(slText("sales.action.cancel")) { self.preview = nil }
                    }
                    if let document = preview.document {
                        ToolbarItem(placement: .primaryAction) {
                            SalesReportExport(report: document, identifier: "sales.customer.report.export",
                                              filename: slText(title))
                        }
                    }
                }
            }
        }
        .task {
            switch kind {
            case .listing: workspace.completed("sales-customer-report-view")
            case .alphabetical: workspace.completed("sales-customer-alphabetical-view")
            case .turnover:
                do {
                    try SalesCustomerReport(workspace.context).prepareTurnover()
                    workspace.completed("sales-customer-turnover-view")
                } catch {
                    showsError = true
                }
            }
        }
    }

    private struct Preview: Identifiable {
        let id = UUID()
        let entries: [SalesCustomerReport.Entry]
        let document: SalesReportDocument?
    }

    private struct Criterion {
        var relation: SalesCustomerReport.Relation?
        var input = ""

        func read() throws -> (SalesCustomerReport.Relation, Int64)? {
            guard let relation else { return nil }
            guard let value = Int64(input) else { throw SalesLedger.Error.invalidField }
            return (relation, value)
        }
    }

    @ViewBuilder
    private func criterion(_ label: String.LocalizationValue, _ input: Binding<Criterion>) -> some View {
        comparison(label, input.relation)
        if input.wrappedValue.relation != nil {
            TextField(slText(label), text: input.input)
                .keyboardType(.numberPad)
        }
    }

    private func comparison(_ label: String.LocalizationValue, _ selection: Binding<SalesCustomerReport.Relation?>) -> some View {
        Picker(slText(label), selection: selection) {
            Text(slText("sales.customer.report.unfiltered")).tag(nil as SalesCustomerReport.Relation?)
            Text(slText("sales.customer.report.less")).tag(SalesCustomerReport.Relation.less as SalesCustomerReport.Relation?)
            Text(slText("sales.customer.report.greater")).tag(SalesCustomerReport.Relation.greater as SalesCustomerReport.Relation?)
            Text(slText("sales.customer.report.equal")).tag(SalesCustomerReport.Relation.equal as SalesCustomerReport.Relation?)
        }
    }

    private func generate() {
        do {
            var filter = SalesCustomerReport.Filter()
            filter.code = code
            filter.status = status
            filter.creditDays = try creditDays.read()
            filter.invoiceCount = try invoiceCount.read()
            filter.averageValue = try averageValue.read()
            filter.overdueDays = try overdueDays.read()
            filter.creationDate = dateRelation.map { ($0, creationDate) }
            let entries = try SalesCustomerReport(workspace.context).generate(filter, kind: kind)
            let document = workspace.context.store.readRaw(SalesCustomerReport.exportPath).map(SalesReportDocument.init)
            preview = Preview(entries: entries, document: document)
        } catch {
            showsError = true
        }
    }
}
