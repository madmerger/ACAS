import ACASCore
import SwiftUI

struct SystemMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(String(localized: "system.company", table: "System")) { CompanyForm(workspace: workspace) }
                .accessibilityIdentifier("system.company")
            NavigationLink {
                CalculationForm(workspace: workspace)
            } label: {
                Text("calc.title", tableName: "CALC")
            }
            .accessibilityIdentifier("calculation.title")
        }
    }
}

private struct CompanyForm: View {
    let workspace: Workspace
    @State private var name = ""
    @State private var saved = false
    @State private var invalid = false
    @State private var storageFailed = false
    @FocusState private var editingName: Bool

    var body: some View {
        Form {
            TextField(String(localized: "system.company.name", table: "System"), text: $name)
                .focused($editingName)
                .accessibilityIdentifier("system.company.name")
            Button(String(localized: "action.save", table: "System")) {
                saved = false
                do {
                    try CompanySetup(workspace.context).save(name: name)
                    editingName = false
                    saved = true
                    workspace.completed("company")
                } catch CompanySetup.Error.invalidName {
                    invalid = true
                } catch {
                    storageFailed = true
                }
            }
            .accessibilityIdentifier("action.save")
            if saved { Text(String(localized: "system.company.saved", table: "System")) }
        }
        .navigationTitle(String(localized: "system.company", table: "System"))
        .onAppear { name = CompanySetup(workspace.context).name }
        .alert(String(localized: "system.company.invalid", table: "System"), isPresented: $invalid) {
            Button("action.close", role: .cancel) {}
        }
        .alert(String(localized: "system.company.storageFailed", table: "System"), isPresented: $storageFailed) {
            Button("action.close", role: .cancel) {}
        }
    }
}
