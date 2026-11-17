import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Applewood Computers Accounting System")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                }

                Section("Modules") {
                    ForEach(AccountingModule.allCases) { module in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.title)
                                .font(.headline)
                            Text("Coming soon")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("ACAS")
        }
    }
}
