import ACASCore
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
    @State private var stockAuditSaveFailed = false

    var body: some View {
        NavigationSplitView {
            List(SectionID.allCases, selection: Binding(get: { section }, set: selectSection)) { item in
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
        .alert(stockText("error.saveAuditStatus"), isPresented: $stockAuditSaveFailed) {
            Button("閉じる", role: .cancel) {}
        }
        #if DEBUG
        .safeAreaInset(edge: .top, spacing: 0) {
            if let evidence = workspace.evidence { CaseBanner(evidence: evidence) }
        }
        #endif
    }

    private func selectSection(_ next: SectionID?) {
        if section == .stock, next != .stock, !saveStockAuditStatus() { return }
        section = next
    }

    private func saveStockAuditStatus() -> Bool {
        do {
            try StockService(workspace.context).saveMovementAuditStatus()
            return true
        } catch {
            stockAuditSaveFailed = true
            return false
        }
    }

    @ViewBuilder private func functions(in section: SectionID) -> some View {
        switch section {
        case .system:
            SystemMenu(workspace: workspace)
        case .sales:
            SalesMenu(workspace: workspace)
        case .stock:
            StockMenu(workspace: workspace, saveAuditStatus: saveStockAuditStatus) {
                selectSection(nil)
                if self.section == nil { workspace.completed("stock.close") }
            }
        default:
            ContentUnavailableView("menu.pending", systemImage: section.symbol)
        }
    }
}
