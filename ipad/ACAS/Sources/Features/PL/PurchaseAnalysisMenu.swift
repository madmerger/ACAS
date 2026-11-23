import ACASCore
import SwiftUI

struct PurchaseAnalysisMenu: View {
    let workspace: Workspace
    @State private var codes: [PurchaseLedger.AnalysisCode] = []
    @State private var failed = false

    private var ledger: PurchaseLedger { PurchaseLedger(workspace.context) }

    var body: some View {
        List {
            NavigationLink(plString("purchase.analysis.add")) {
                PurchaseAnalysisEditor(workspace: workspace, value: .init(), creating: true)
            }
            .accessibilityIdentifier("pl.analysis.add")
            if failed {
                ContentUnavailableView(plString("purchase.error.analysis.format"), systemImage: "exclamationmark.circle")
            }
            Section(plString("purchase.analysis.list")) {
                ForEach(codes) { code in
                    NavigationLink {
                        PurchaseAnalysisEditor(workspace: workspace, value: code, creating: false)
                    } label: {
                        LabeledContent(code.code, value: code.name)
                    }
                }
            }
        }
        .navigationTitle(plString("purchase.analysis.menu"))
        .onAppear {
            do { codes = try ledger.analysisCodes(); failed = false }
            catch { failed = true }
            workspace.completed("pl.analysis")
        }
    }
}

private struct PurchaseAnalysisEditor: View {
    let workspace: Workspace
    @State var value: PurchaseLedger.AnalysisCode
    let creating: Bool
    @State private var error: PurchaseNotice?
    @State private var confirm = false
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, value: PurchaseLedger.AnalysisCode, creating: Bool) {
        self.workspace = workspace
        self._value = State(initialValue: value)
        self.creating = creating
    }

    var body: some View {
        Form {
            if creating { TextField(plString("purchase.analysis.code"), text: $value.code) }
            else { LabeledContent(plString("purchase.analysis.code"), value: value.code) }
            TextField(plString("purchase.analysis.account"), value: $value.account, format: .number.grouping(.never))
            TextField(plString("purchase.analysis.name"), text: $value.name)
            TextField(plString("purchase.analysis.print"), text: $value.printGroup)
            Button(plString("purchase.action.save")) { commit(remove: false) }
            if !creating {
                Button(plString("purchase.action.delete"), role: .destructive) { confirm = true }
            }
        }
        .navigationTitle(creating ? plString("purchase.analysis.add") : plString("purchase.analysis.edit"))
        .confirmationDialog(plString("purchase.analysis.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(plString("purchase.action.delete"), role: .destructive) { commit(remove: true) }
            Button(plString("purchase.action.cancel"), role: .cancel) {}
        }
        .purchaseAlert($error)
    }

    private func commit(remove: Bool) {
        let ledger = PurchaseLedger(workspace.context)
        do {
            if remove { try ledger.removeAnalysisCode(value.code) }
            else { try ledger.saveAnalysisCode(value, creating: creating) }
            workspace.completed("pl.analysis.save")
            dismiss()
        } catch {
            self.error = PurchaseNotice(error)
            if case PurchaseLedger.Error.analysisFileIncompatible = error { workspace.completed("pl.analysis.reject") }
        }
    }
}
