import SwiftUI

enum SectionID: String, CaseIterable, Identifiable {
    case general, sales, purchases, stock, orders, payroll, retail, incomplete, system

    var id: String { rawValue }
    var title: LocalizedStringKey { LocalizedStringKey("section." + rawValue) }
    var symbol: String {
        switch self {
        case .general: "book.closed"
        case .sales: "arrow.up.right"
        case .purchases: "arrow.down.left"
        case .stock: "shippingbox"
        case .orders: "cart"
        case .payroll: "person.2"
        case .retail: "storefront"
        case .incomplete: "tray"
        case .system: "gear"
        }
    }
}

struct MainMenu: View {
    @ObservedObject var workspace: Workspace
    @State private var section: SectionID? = .system

    var body: some View {
        NavigationSplitView {
            List(SectionID.allCases, selection: $section) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.symbol)
                }
                .accessibilityIdentifier("section." + item.rawValue)
            }
            .navigationTitle("app.title")
        } detail: {
            NavigationStack {
                if let section {
                    functions(in: section)
                        .navigationTitle(section.title)
                } else {
                    ContentUnavailableView("menu.select", systemImage: "sidebar.left")
                }
            }
            .id(section)
        }
        #if DEBUG
        .safeAreaInset(edge: .top, spacing: 0) {
            if let evidence = workspace.evidence { CaseBanner(evidence: evidence) }
        }
        #endif
    }

    @ViewBuilder private func functions(in section: SectionID) -> some View {
        switch section {
        case .system:
            SystemMenu(workspace: workspace)
        case .sales:
            SalesMenu(workspace: workspace)
        default:
            ContentUnavailableView("menu.pending", systemImage: section.symbol)
        }
    }
}
