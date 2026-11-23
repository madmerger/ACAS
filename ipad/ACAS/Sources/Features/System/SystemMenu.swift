import ACASCore
import SwiftUI

struct SystemMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink("system.company") { CompanyForm(workspace: workspace) }
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
    @FocusState private var editingName: Bool

    var body: some View {
        Form {
            TextField("system.company.name", text: $name)
                .focused($editingName)
                .accessibilityIdentifier("system.company.name")
            Button("action.save") {
                do {
                    try CompanySetup(workspace.context).save(name: name)
                    editingName = false
                    saved = true
                    workspace.completed("company")
                } catch {
                    invalid = true
                }
            }
            .accessibilityIdentifier("action.save")
            if saved { Text("system.company.saved") }
        }
        .navigationTitle("system.company")
        .onAppear { name = CompanySetup(workspace.context).name }
        .alert("system.company.invalid", isPresented: $invalid) {
            Button("action.close", role: .cancel) {}
        }
    }
}
