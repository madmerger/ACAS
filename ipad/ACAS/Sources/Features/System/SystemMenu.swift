import ACASCore
import SwiftUI

struct SystemMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            NavigationLink(String(localized: "system.company", table: "System")) { CompanyForm(workspace: workspace) }
                .accessibilityIdentifier("system.company")
            NavigationLink(initialCustomerText("title")) { InitialCustomerForm(workspace: workspace) }
                .accessibilityIdentifier("system.master.customer")
            #if DEBUG
            if workspace.evidence != nil {
                NavigationLink(String(localized: "calculation.title", table: "CALC")) { CheckDigitForm(workspace: workspace) }
                    .accessibilityIdentifier("calculation.title")
            }
            #endif
        }
    }
}

private func initialCustomerText(_ key: String) -> String {
    NSLocalizedString("system.master.customer." + key, tableName: "System", comment: "")
}

private struct InitialCustomerForm: View {
    let workspace: Workspace
    @State private var contact = InitialCustomerSetup.Contact()
    @State private var status: String?
    @FocusState private var focused: String?

    var body: some View {
        Form {
            field("code", $contact.code)
            field("name", $contact.name)
            field("address", $contact.address)
            field("address2", $contact.address2)
            field("phone", $contact.phone)
            field("email", $contact.email)
            if let status { Text(status).accessibilityIdentifier("system.master.status") }
            Button(String(localized: "system.action.save", table: "System"), action: save)
                .accessibilityIdentifier("system.master.save")
        }
        .navigationTitle(initialCustomerText("title"))
    }

    private func field(_ name: String, _ value: Binding<String>) -> some View {
        TextField(initialCustomerText(name), text: value)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: name)
            .submitLabel(.done)
            .onSubmit { focused = nil }
            .accessibilityIdentifier("system.master.field." + name)
    }

    private func save() {
        do {
            try InitialCustomerSetup(workspace.context).add(contact)
            contact = InitialCustomerSetup.Contact()
            focused = nil
            status = initialCustomerText("saved")
        } catch SalesLedger.Error.missingCompany {
            status = initialCustomerText("missingCompany")
        } catch InitialCustomerSetup.Error.duplicate {
            status = initialCustomerText("duplicate")
        } catch InitialCustomerSetup.Error.invalidInput {
            status = initialCustomerText("invalid")
        } catch InitialCustomerSetup.Error.invalidAddress {
            status = String(localized: "system.master.customer.invalidAddress", table: "System")
        } catch {
            status = initialCustomerText("failed")
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
            Button(String(localized: "system.action.save", table: "System")) {
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
