import ACASCore
import SwiftUI

struct SystemMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink("system.company") { CompanyForm(workspace: workspace) }
                .accessibilityIdentifier("system.company")
            #if DEBUG
            if workspace.evidence != nil {
                NavigationLink("calculation.title") { CheckDigitForm(workspace: workspace) }
                    .accessibilityIdentifier("calculation.title")
            }
            #endif
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

#if DEBUG
private struct CheckDigitForm: View {
    let workspace: Workspace
    @State private var code = ""
    @State private var check: Int?
    @State private var calculated = false
    @FocusState private var editingCode: Bool

    var body: some View {
        Form {
            TextField("calculation.code", text: $code)
                .focused($editingCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("calculation.code")
            Button("action.calculate") {
                editingCode = false
                check = Maps09.checkDigit(code)
                calculated = true
                workspace.completed("check-digit", calculation: DebugCalculation(check: check ?? 0, valid: check != nil))
            }
            .accessibilityIdentifier("action.calculate")
            if let check {
                Text(verbatim: String(check))
                    .accessibilityIdentifier("calculation.result")
                Text("calculation.valid")
                    .accessibilityIdentifier("calculation.valid")
            } else if calculated {
                Text("calculation.invalid")
            }
        }
        .navigationTitle("calculation.title")
    }
}
#endif
