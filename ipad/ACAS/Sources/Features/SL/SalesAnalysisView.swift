import SwiftUI
import ACASCore

struct SalesAnalysisMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(slText("sales.analysis.add")) { SalesAnalysisEditor(workspace: workspace, original: nil) }
                .accessibilityIdentifier("sales.analysis.add")
            NavigationLink(slText("sales.analysis.edit")) { SalesAnalysisCodeList(workspace: workspace, editable: true) }
                .accessibilityIdentifier("sales.analysis.edit")
            NavigationLink(slText("sales.analysis.print")) { SalesAnalysisReportView(workspace: workspace, kind: .codes) }
                .accessibilityIdentifier("sales.analysis.print")
            NavigationLink(slText("sales.analysis.printAll")) { SalesAnalysisReportView(workspace: workspace, kind: .allCodes) }
                .accessibilityIdentifier("sales.analysis.printAll")
            NavigationLink(slText("sales.analysis.display")) { SalesAnalysisCodeList(workspace: workspace, editable: false) }
                .accessibilityIdentifier("sales.analysis.display")
        }
        .navigationTitle(slText("sales.analysis.codes"))
    }
}

private struct SalesAnalysisCodeList: View {
    let workspace: Workspace
    let editable: Bool
    @State private var codes: [SalesAnalysis.Code] = []
    @State private var failure: String.LocalizationValue?

    var body: some View {
        List {
            if let failure { Text(slText(failure)).accessibilityIdentifier("sales.analysis.error") }
            ForEach(codes) { code in
                if editable {
                    NavigationLink { SalesAnalysisEditor(workspace: workspace, original: code) } label: {
                        SalesAnalysisCodeRow(code: code)
                    }
                } else {
                    SalesAnalysisCodeRow(code: code)
                }
            }
        }
        .navigationTitle(slText(editable ? "sales.analysis.edit" : "sales.analysis.display"))
        .onAppear {
            let service = SalesAnalysis(workspace.context)
            do {
                try service.prepare()
                codes = try service.codes()
                failure = nil
            } catch {
                failure = analysisFailure(error)
            }
        }
    }
}

private struct SalesAnalysisCodeRow: View {
    let code: SalesAnalysis.Code
    private var account: String { String(format: "%06lld", code.account) }

    var body: some View {
        VStack(alignment: .leading) {
            Text(code.group + "　" + analysisDescription(code))
            Text(slText(code.isGroup ? "sales.analysis.groupType" : "sales.analysis.detailType"))
                .foregroundStyle(.secondary)
            if code.account != 0 {
                Text(slText("sales.analysis.account") + "　" + account)
            }
            if !code.printCode.isEmpty { Text(slText("sales.analysis.printCode") + "　" + code.printCode) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(code.account == 0 ? "" : account)
        .accessibilityIdentifier("sales.analysis.code." + code.id)
    }
}

private struct SalesAnalysisEditor: View {
    let workspace: Workspace
    let original: SalesAnalysis.Code?
    @Environment(\.dismiss) private var dismiss
    @State private var group = ""
    @State private var account = ""
    @State private var description = ""
    @State private var printCode = ""
    @State private var printCodeEdited = false
    @State private var failed = false
    @State private var failure: String.LocalizationValue = "sales.analysis.failed"
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let original {
                LabeledContent(slText("sales.analysis.group"), value: original.group)
            } else {
                TextField(slText("sales.analysis.group"), text: $group)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("sales.analysis.group")
                    .onChange(of: group) { _, value in
                        if !printCodeEdited { printCode = value }
                    }
            }
            TextField(slText("sales.analysis.account"), text: $account)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("sales.analysis.account")
            TextField(slText("sales.analysis.description"), text: $description)
                .accessibilityIdentifier("sales.analysis.description")
            TextField(slText("sales.analysis.printCode"), text: Binding(get: { printCode }, set: {
                printCodeEdited = true
                printCode = $0
            }))
                .accessibilityIdentifier("sales.analysis.printCode")
            Button(slText("sales.analysis.save"), action: save)
                .accessibilityIdentifier("sales.analysis.save")
            if original != nil {
                Button(slText("sales.analysis.delete"), role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(slText(original == nil ? "sales.analysis.add" : "sales.analysis.edit"))
        .onAppear {
            if let original {
                group = original.group
                account = String(format: "%06lld", original.account)
                description = original.description
                printCode = original.printCode
            }
        }
        .alert(slText(failure), isPresented: $failed) {
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
        .alert(slText("sales.analysis.confirmDelete"), isPresented: $confirmDelete) {
            Button(slText("sales.analysis.delete"), role: .destructive, action: delete)
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
    }

    private func save() {
        let service = SalesAnalysis(workspace.context)
        do {
            guard let value = Int64(account.isEmpty ? "0" : account) else { throw SalesAnalysis.Error.invalidInput }
            try service.prepare()
            try service.save(group: group, account: value, description: description,
                             printCode: printCode, replacing: original != nil)
            workspace.completed("sales-analysis-code")
            dismiss()
        } catch {
            failure = analysisFailure(error)
            failed = true
        }
    }

    private func delete() {
        do {
            try SalesAnalysis(workspace.context).delete(group: group)
            dismiss()
        } catch {
            failure = analysisFailure(error)
            failed = true
        }
    }
}

struct SalesAnalysisReportView: View {
    enum Kind {
        case codes, allCodes, totals

        var title: String.LocalizationValue {
            switch self {
            case .codes: "sales.analysis.print"
            case .allCodes: "sales.analysis.printAll"
            case .totals: "sales.analysis.totals"
            }
        }
    }

    let workspace: Workspace
    let kind: Kind
    @State private var codes: [SalesAnalysis.Code] = []
    @State private var totals: [SalesAnalysis.Totals] = []
    @State private var document: SalesReportDocument?
    @State private var failure: String.LocalizationValue?

    var body: some View {
        List {
            if let failure { Text(slText(failure)).accessibilityIdentifier("sales.analysis.error") }
            Button(slText("sales.action.generate"), action: generate)
                .accessibilityIdentifier("sales.analysis.generate")
            ForEach(codes) { SalesAnalysisCodeRow(code: $0) }
            ForEach(totals) { entry in
                Section {
                    ForEach(Array(["sales.analysis.current", "sales.analysis.previous", "sales.analysis.year"].enumerated()), id: \.offset) { item in
                        let amount = (Decimal(entry.values[item.offset]) / 100).formatted(.number.precision(.fractionLength(2)))
                        LabeledContent(slText(String.LocalizationValue(item.element)), value: amount)
                    }
                } header: {
                    Text(entry.code.group + "　" + analysisDescription(entry.code))
                }
            }
        }
        .navigationTitle(slText(kind.title))
        .toolbar {
            if let document {
                ToolbarItem(placement: .primaryAction) {
                    SalesReportExport(report: document, identifier: "sales.analysis.export", filename: slText("sales.analysis.filename"))
                }
            }
        }
    }

    private func generate() {
        let service = SalesAnalysis(workspace.context)
        do {
            failure = nil
            if kind == .totals {
                guard let entries = try service.printTotals() else {
                    failure = "sales.analysis.noTotals"
                    return
                }
                totals = entries
            } else {
                try service.prepare()
                codes = try service.printCodes(allLedgers: kind == .allCodes)
            }
            document = workspace.context.store.readRaw(SalesAnalysis.exportPath).map(SalesReportDocument.init)
            workspace.completed("sales-analysis-report")
        } catch {
            failure = analysisFailure(error)
        }
    }
}

private func analysisDescription(_ code: SalesAnalysis.Code) -> String {
    switch (code.id, code.description) {
    case ("Sv", "VAT Control"), ("Pv", "VAT Control"): slText("sales.analysis.default.tax")
    case ("Pvi", "VAT Input Invoices/CN's"): slText("sales.analysis.default.purchaseInvoiceTax")
    case ("Pvj", "VAT Input Receipts"): slText("sales.analysis.default.purchaseReceiptTax")
    case ("Sz", "Computer Control"), ("Pz", "Computer Control"): slText("sales.analysis.default.system")
    case ("Pza", "Purchase Carriage Charge"): slText("sales.analysis.default.purchaseCarriage")
    case ("Pzb", "Purchase Late Charges"): slText("sales.analysis.default.purchaseLate")
    case ("Szc", "Sales Carriage Charges"): slText("sales.analysis.default.salesCarriage")
    case ("Szd", "Sales Late Charges"): slText("sales.analysis.default.salesLate")
    case ("Svo", "VAT Output Invoices/CN's"): slText("sales.analysis.default.salesInvoiceTax")
    case ("Svp", "VAT Output Receipts"): slText("sales.analysis.default.salesReceiptTax")
    case ("Pa", "Default Group"), ("Sa", "Default Group"): slText("sales.analysis.default.group")
    case ("Pa1", "Default Purchases"): slText("sales.analysis.default.purchases")
    case ("Sa1", "Default Sales"): slText("sales.analysis.default.sales")
    default: code.description
    }
}

private func analysisFailure(_ error: Error) -> String.LocalizationValue {
    switch error {
    case SalesAnalysis.Error.invalidLayout: "sales.analysis.invalidLayout"
    case SalesAnalysis.Error.invalidInput: "sales.analysis.invalidInput"
    case SalesAnalysis.Error.duplicate: "sales.analysis.duplicate"
    case SalesAnalysis.Error.missingGroup: "sales.analysis.missingGroup"
    case SalesAnalysis.Error.groupUsed: "sales.analysis.groupUsed"
    default: "sales.analysis.failed"
    }
}
