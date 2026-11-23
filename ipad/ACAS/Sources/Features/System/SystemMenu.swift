import ACASCore
import SwiftUI

struct SystemMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(String(localized: "system.company", table: "System")) { CompanyForm(workspace: workspace) }
                .accessibilityIdentifier("system.company")
            NavigationLink(systemSetting("master.title")) { MasterSetupMenu(workspace: workspace) }
                .accessibilityIdentifier("system.master")
            #if DEBUG
            if workspace.evidence != nil {
                NavigationLink(String(localized: "calculation.title", table: "CALC")) { CheckDigitForm(workspace: workspace) }
                    .accessibilityIdentifier("calculation.title")
            }
            #endif
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
            TextField(String(localized: "calculation.code", table: "CALC"), text: $code)
                .focused($editingCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("calculation.code")
            Button(String(localized: "calculation.action.calculate", table: "CALC")) {
                editingCode = false
                check = Maps09.checkDigit(code)
                calculated = true
                workspace.completed("check-digit", calculation: DebugCalculation(check: check ?? 0, valid: check != nil))
            }
            .accessibilityIdentifier("action.calculate")
            if let check {
                Text(verbatim: String(check))
                    .accessibilityIdentifier("calculation.result")
                Text(String(localized: "calculation.valid", table: "CALC"))
                    .accessibilityIdentifier("calculation.valid")
            } else if calculated {
                Text(String(localized: "calculation.invalid", table: "CALC"))
            }
        }
        .navigationTitle(String(localized: "calculation.title", table: "CALC"))
    }
}
#endif
