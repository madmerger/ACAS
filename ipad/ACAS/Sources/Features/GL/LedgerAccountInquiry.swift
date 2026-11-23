import ACASCore
import SwiftUI

struct LedgerAccountInquiry: View {
    let workspace: Workspace
    @State private var code = ""
    @State private var branch = ""
    @State private var accounts: [LedgerAccount]?
    @FocusState private var enteringCode: Bool

    private var hasBranches: Bool {
        ["P", "B"].contains(CompanySetup(workspace.context).settings.text("p-c"))
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField(ledgerText("account-start-code"), text: $code)
                    .keyboardType(.numberPad)
                    .focused($enteringCode)
                    .accessibilityIdentifier("gl.accounts.start")
                if hasBranches {
                    TextField(ledgerText("account-branch"), text: $branch)
                        .keyboardType(.numberPad)
                }
                Button(ledgerText("account-search"), action: search)
                    .disabled(!Self.valid(code, width: 6) || (hasBranches && !Self.valid(branch, width: 2)))
                    .accessibilityIdentifier("gl.accounts.search")
            }
            .padding()
            if let accounts {
                if accounts.isEmpty {
                    ContentUnavailableView(ledgerText("account-no-match"), systemImage: "magnifyingglass")
                } else {
                    Table(accounts) {
                        TableColumn(ledgerText("account-code")) { account in
                            Text(hasBranches ? "\(account.code)／\(account.branch)" : account.code)
                        }
                        TableColumn(ledgerText("account-name"), value: \.name)
                        TableColumn(ledgerText("account-type")) { account in
                            let kind = [0, 1, 2, 3, 9].contains(account.type) ? String(account.type) : "unknown"
                            Text(ledgerText("account-kind." + kind))
                        }
                        TableColumn(ledgerText("account-level")) { account in
                            Text(account.level == 0 ? "" : String(account.level))
                        }
                        TableColumn(ledgerText("account-balance")) { account in
                            Text((Decimal(account.balance) / 100).formatted(.number.precision(.fractionLength(2))))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .navigationTitle(ledgerText("account-list"))
        .onAppear { workspace.completed("gl-chart-inquiry-menu") }
    }

    private func search() {
        enteringCode = false
        accounts = ChartOfAccounts(workspace.context).accounts(startingAt: Int(code) ?? 0, branch: hasBranches ? Int(branch) ?? 0 : 0)
        workspace.completed("gl-chart-inquiry")
    }

    private static func valid(_ value: String, width: Int) -> Bool {
        value.utf8.count <= width && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}
