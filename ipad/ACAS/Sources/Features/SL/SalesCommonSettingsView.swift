import ACASCore
import SwiftUI

struct SalesCommonSettingsView: View {
    let workspace: Workspace
    @State private var settings: SalesCommonSettings?
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let settings {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 10) {
                    ForEach(settings.fields) { field in
                        let key = "sales.common." + field.id
                        LabeledContent(slText(String.LocalizationValue(key))) {
                            Text(displayValue(for: field))
                                .foregroundStyle(.primary)
                                .accessibilityIdentifier(key)
                        }
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            } else if failed {
                Text(slText("sales.common.unavailable")).padding()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(slText("sales.common.title"))
        .task {
            guard settings == nil, !failed else { return }
            do {
                settings = try SalesCommonSettings(workspace.context)
                workspace.completed("sales-common-settings-view")
            } catch {
                failed = true
            }
        }
    }

    private func displayValue(for field: SalesCommonSettings.Field) -> String {
        if field.id == "password" { return slText("sales.common.password.hidden") }
        return field.value.isEmpty ? slText("sales.common.unset") : field.value
    }
}
