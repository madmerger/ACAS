import SwiftUI
import ACASCore

@main
struct ACASApp: App {
    @StateObject private var app = AppModel()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(app)
                .environment(\.locale, Locale(identifier: app.language == .ja ? "ja" : "en"))
                .preferredColorScheme(.dark)
                .tint(Theme.blue)
        }
    }
}

enum Route: Hashable, Identifiable {
    case acas, irs, cases, calc
    var id: Self { self }
}

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var route: Route?
    @State private var resetDone = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.navy, Theme.deep], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("ui.home.title".localized).font(.system(size: 44, weight: .bold)).foregroundColor(.white)
                Text("ui.home.subtitle".localized).font(.title3).foregroundColor(Theme.sky)
                VStack(spacing: 14) {
                    menu("ui.home.start_acas", "building.columns", .acas, id: "start-acas")
                    menu("ui.home.start_irs", "book.closed", .irs, id: "start-irs")
                    menu("ui.home.cases", "checklist", .cases, id: "open-cases")
                    menu("ui.home.calc", "function", .calc, id: "open-calc")
                }
                .frame(maxWidth: 520)
                Button { app.resetData(); resetDone = true } label: { Text("ui.home.reset_data".localized) }
                    .foregroundColor(Theme.sky)
                    .accessibilityIdentifier("reset-data")
                if resetDone { Text("ui.home.reset_done".localized).foregroundColor(Theme.pale) }
            }
            .padding(40)
        }
        .fullScreenCover(item: $route) { r in
            switch r {
            case .acas: TerminalScreen(model: TerminalModel(session: app.productionSession()), program: "acas") { route = nil }
            case .irs: TerminalScreen(model: TerminalModel(session: app.productionSession()), program: "irs") { route = nil }
            case .cases: CaseListView(calcOnly: false) { route = nil }
            case .calc: CaseListView(calcOnly: true) { route = nil }
            }
        }
        .onAppear {
            if app.autoCase != nil || app.autoSuite != nil { route = app.autoSuite == "CALC" ? .calc : .cases }
        }
    }

    private func menu(_ key: String, _ icon: String, _ r: Route, id: String) -> some View {
        Button { route = r } label: {
            HStack {
                Image(systemName: icon).frame(width: 34)
                Text(key.localized).font(.title2.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(18)
            .background(Theme.blue).foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityIdentifier(id)
    }
}
