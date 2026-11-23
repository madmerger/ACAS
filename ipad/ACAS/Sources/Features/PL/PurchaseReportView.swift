import ACASCore
import SwiftUI

struct PurchaseReportView: View {
    enum Mode {
        case aged, alphabetical, turnover, listing, file, analysisCodes, allAnalysisCodes, analysis, dayBook

        var title: String {
            switch self {
            case .aged: plString("purchase.report.aged")
            case .alphabetical: plString("purchase.supplier.alphabetical")
            case .turnover: plString("purchase.report.turnover")
            case .file: plString("purchase.report.supplier_file")
            case .listing: plString("purchase.report.supplier_listing")
            case .analysisCodes: plString("purchase.report.analysis_codes")
            case .allAnalysisCodes: plString("purchase.report.all_analysis_codes")
            case .analysis: plString("purchase.close.analysis")
            case .dayBook: plString("purchase.report.day_book")
            }
        }

        var supplierReport: PurchaseLedger.SupplierReport? {
            switch self {
            case .alphabetical: .alphabetical
            case .turnover: .turnover
            case .file: .file
            case .listing: .listing
            default: nil
            }
        }
    }

    let workspace: Workspace
    let mode: Mode
    @State private var filter = PurchaseLedger.SupplierReportFilter()
    @State private var date = Date()
    @State private var minimum: Decimal = 0
    @State private var alphabetical = false
    @State private var useCreationDate = false
    @State private var output: Data?
    @State private var showingPreview = false
    @State private var empty = false
    @State private var notice: PurchaseNotice?

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        Form {
            if mode == .alphabetical {
                NavigationLink(plString("purchase.supplier.list")) {
                    PurchaseSuppliersView(workspace: workspace, byName: true)
                }
            }
            if mode == .aged || mode.supplierReport != nil {
                Section(plString("purchase.report.filters")) {
                    TextField(plString("purchase.supplier.code"), text: $filter.supplier)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pl.report.supplier")
                    if mode == .aged {
                        DatePicker(plString("purchase.report.date"), selection: $date, displayedComponents: .date)
                        TextField(plString("purchase.report.minimum"), value: $minimum, format: .number.grouping(.never))
                            .keyboardType(.decimalPad)
                        Toggle(plString("purchase.supplier.alphabetical"), isOn: $alphabetical)
                    } else {
                        Picker(plString("purchase.report.status"), selection: $filter.status) {
                            Text(plString("purchase.report.any")).tag(PurchaseLedger.SupplierReportFilter.Status.all)
                            Text(plString("purchase.report.active")).tag(PurchaseLedger.SupplierReportFilter.Status.active)
                            Text(plString("purchase.report.dormant")).tag(PurchaseLedger.SupplierReportFilter.Status.dormant)
                        }
                        criterion("purchase.report.credit", $filter.credit)
                        criterion("purchase.report.activity", $filter.activity)
                        criterion("purchase.report.average", $filter.average)
                        criterion("purchase.report.overdue", $filter.overdue)
                        if filter.overdue.comparison != .any {
                            Text(plString("purchase.report.overdue.help"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if mode != .file {
                            comparison("purchase.report.created", $filter.created.comparison)
                                .accessibilityIdentifier("pl.report.created")
                            if filter.created.comparison != .any {
                                if mode == .listing {
                                    Toggle(plString("purchase.report.use_creation_date"), isOn: $useCreationDate)
                                }
                                if mode != .listing || useCreationDate {
                                    DatePicker(plString("purchase.report.date"), selection: $date, displayedComponents: .date)
                                        .accessibilityIdentifier("pl.report.created.date")
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button(plString("purchase.report.generate"), action: generate)
                    .accessibilityIdentifier("pl.report.generate")
                if let output {
                    Button(plString("purchase.report.preview")) {
                        showingPreview = true
                    }
                    .accessibilityIdentifier("pl.report.preview")
                    ShareLink(item: output, preview: SharePreview(mode.title)) {
                        Label(plString("purchase.report.share"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("pl.report.share")
                }
                if empty { Text(plString("purchase.report.empty")).accessibilityIdentifier("pl.report.empty") }
            }
        }
        .navigationTitle(mode.title)
        .sheet(isPresented: $showingPreview) {
            if let output {
                PurchaseReportPreview(title: mode.title, bytes: output) { showingPreview = false }
            }
        }
        .onAppear { date = ledger.processingDate }
        .purchaseAlert($notice)
    }

    private func criterion(_ key: String, _ binding: Binding<PurchaseLedger.SupplierReportFilter.Criterion>) -> some View {
        Group {
            comparison(key, binding.comparison)
            if binding.wrappedValue.comparison != .any {
                TextField(plString("purchase.report.threshold"), value: binding.value, format: .number.grouping(.never))
                    .keyboardType(.numbersAndPunctuation)
            }
        }
    }

    private func comparison(_ key: String, _ binding: Binding<PurchaseLedger.SupplierReportFilter.Comparison>) -> some View {
        Picker(plString(key), selection: binding) {
            Text(plString("purchase.report.any")).tag(PurchaseLedger.SupplierReportFilter.Comparison.any)
            Text(plString("purchase.report.less")).tag(PurchaseLedger.SupplierReportFilter.Comparison.less)
            Text(plString("purchase.report.greater")).tag(PurchaseLedger.SupplierReportFilter.Comparison.greater)
            Text(plString("purchase.report.equal")).tag(PurchaseLedger.SupplierReportFilter.Comparison.equal)
        }
    }

    private func generate() {
        output = nil
        empty = false
        do {
            switch mode {
            case .aged:
                guard minimum >= 0, minimum < 10_000_000 else { throw PurchaseLedger.PurchaseReportError.invalidMinimum }
                let cents = NSDecimalNumber(decimal: minimum * 100).int64Value
                output = try ledger.agedCreditorsReport(date: date, supplier: filter.supplier, minimum: cents, alphabetical: alphabetical)
            case .alphabetical, .turnover, .listing, .file:
                if let kind = mode.supplierReport {
                    filter.creationDate = filter.created.comparison == .any || (mode == .listing && !useCreationDate) ? nil : date
                    output = try ledger.supplierReport(kind, filter: filter)
                }
            case .analysisCodes, .allAnalysisCodes:
                output = try ledger.analysisCodeReport(allLedgers: mode == .allAnalysisCodes)
            case .analysis: output = try ledger.purchaseAnalysisReport()
            case .dayBook: output = try ledger.purchaseDayBook()
            }
            empty = output == nil
        } catch { notice = PurchaseNotice(error) }
    }
}

private struct PurchaseReportPreview: View {
    private struct Line: Identifiable {
        let id: Int
        let page: Int
        let text: String
    }

    let title: String
    private let lines: [Line]
    let close: () -> Void

    init(title: String, bytes: Data, close: @escaping () -> Void) {
        self.title = title
        self.close = close
        var lines: [Line] = []
        var page = 1
        var start = bytes.startIndex
        let raw = Array(bytes)
        for (index, byte) in raw.enumerated() where byte == 10 || byte == 12 {
            lines.append(Line(id: lines.count + 1, page: page, text: SJIS.decode(raw[start..<index])))
            if byte == 12 { page += 1 }
            start = index + 1
        }
        if start < raw.count {
            lines.append(Line(id: lines.count + 1, page: page, text: SJIS.decode(raw[start...])))
        }
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("action.close", action: close)
                    .accessibilityIdentifier("pl.report.preview.close")
            }
            .padding()
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    row(plString("purchase.report.preview.page"), plString("purchase.report.preview.line"),
                        plString("purchase.report.preview.content"))
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(lines) { line in
                        row(String(line.page), String(line.id), line.text, numbered: true)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.topLeading)
            .accessibilityIdentifier("pl.report.preview.lines")
        }
    }

    private func row(_ page: String, _ line: String, _ content: String, numbered: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(page).frame(minWidth: 60, alignment: .leading)
                .accessibilityIdentifier(numbered ? "pl.report.preview.page" : "pl.report.preview.page.heading")
            Text(line).frame(minWidth: 60, alignment: .leading)
            Text(content).font(.system(.body, design: .monospaced)).fixedSize()
        }
    }
}
