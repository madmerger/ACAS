import ACASCore
import SwiftUI

struct StockMenu: View {
    let workspace: Workspace
    @State private var processingDate: Date?
    @State private var proposedDate = Date()
    @State private var showDate = true

    private var stock: StockService { StockService(workspace.context) }

    var body: some View {
        List {
            Button("処理日を設定") {
                proposedDate = processingDate ?? stock.today
                showDate = true
            }
            .accessibilityIdentifier("stock.date")
            NavigationLink("在庫品目マスター管理") { master }
                .accessibilityIdentifier("stock.master")
            NavigationLink("入出庫・発注記録") { movements }
                .accessibilityIdentifier("stock.movements")
            NavigationLink("在庫帳票") { reports }
                .accessibilityIdentifier("stock.reports")
            NavigationLink("在庫期間締め") { StockMaintenance(stock: stock, closing: true) }
                .accessibilityIdentifier("stock.closePeriod")
            NavigationLink("在庫ファイル圧縮") { StockMaintenance(stock: stock, closing: false) }
                .accessibilityIdentifier("stock.rebuild")
            NavigationLink("共通設定") { SystemMenu(workspace: workspace) }
                .accessibilityIdentifier("stock.settings")
        }
        .onAppear { if processingDate == nil { proposedDate = stock.today } }
        .sheet(isPresented: $showDate) {
            NavigationStack {
                Form {
                    DatePicker("処理日", selection: $proposedDate, displayedComponents: .date)
                    Button("確定") {
                        processingDate = proposedDate
                        showDate = false
                        workspace.completed("stock.date")
                    }
                    .accessibilityIdentifier("stock.confirmDate")
                }
                .navigationTitle("在庫処理日")
            }
            .interactiveDismissDisabled(processingDate == nil)
        }
    }

    private var master: some View {
        List {
            itemForm(.create)
            itemForm(.edit)
            itemForm(.delete)
            itemForm(.renumber)
            itemForm(.lookup)
            report("品目帳票", id: "masterReport")
        }
        .navigationTitle("在庫品目マスター管理")
    }

    private var movements: some View {
        List {
            itemForm(.receive)
            itemForm(.issue)
            itemForm(.barcode)
            itemForm(.order)
            report("在庫監査帳票", id: "audit")
        }
        .navigationTitle("入出庫・発注記録")
    }

    private var reports: some View {
        List {
            report("在庫評価帳票", id: "valuation")
            report("在庫活動帳票", id: "activity")
            report("発注点帳票", id: "reorder")
            report("在庫履歴帳票", id: "history")
            report("在庫一覧帳票", id: "listing")
        }
        .navigationTitle("在庫帳票")
    }

    private func itemForm(_ operation: StockItemForm.Operation) -> some View {
        NavigationLink(operation.title) {
            StockItemForm(workspace: workspace, operation: operation, date: processingDate ?? stock.today)
        }
        .accessibilityIdentifier("stock." + operation.rawValue)
    }

    private func report(_ title: String, id: String) -> some View {
        NavigationLink(title) { StockItemTable(stock: stock, title: title, id: id) }
            .accessibilityIdentifier("stock." + id)
    }
}

private struct StockItemTable: View {
    let stock: StockService
    let title: String
    let id: String
    @State private var filter = ""

    var body: some View {
        Table(stock.items.filter { row in
            (filter.isEmpty || row.code.localizedStandardContains(filter) || row.name.localizedStandardContains(filter))
                && (id != "reorder" || row.held <= row.reorderPoint)
        }) {
            TableColumn("品目コード", value: \.code)
            TableColumn("品名", value: \.name)
            TableColumn("在庫数") { Text($0.held.formatted()) }
            TableColumn("入庫数") { Text($0.added.formatted()) }
            TableColumn("出庫数") { Text($0.deducted.formatted()) }
            TableColumn("在庫評価額") { Text((Decimal($0.value) / 100).formatted()) }
        }
        .searchable(text: $filter, prompt: "品目コード・品名")
        .navigationTitle(title)
    }
}

private struct StockMaintenance: View {
    let stock: StockService
    let closing: Bool
    @State private var current = false
    @State private var yearly = false
    @State private var recovery = false
    @State private var confirming = false
    @State private var message = ""

    var body: some View {
        Form {
            if closing {
                Toggle("当期間の累計を消去", isOn: $current)
                Toggle("年度累計を消去", isOn: $yearly)
            } else {
                Toggle("一時ファイルから復元", isOn: $recovery)
            }
            Button("実行", role: .destructive) { confirming = true }
                .disabled(closing && !current && !yearly)
            if !message.isEmpty { Text(message) }
        }
        .navigationTitle(closing ? "在庫期間締め" : "在庫ファイル圧縮")
        .confirmationDialog("実行しますか？", isPresented: $confirming, titleVisibility: .visible) {
            Button("実行する", role: .destructive) {
                do {
                    if closing { try stock.closePeriod(current: current, yearly: yearly) }
                    else { try stock.rebuild(recovery: recovery) }
                    message = "処理しました。"
                } catch { message = stockError(error) }
            }
        }
    }
}

func stockError(_ error: Error) -> String {
    switch error as? StockService.Failure {
    case .missing: "指定した在庫品目がありません。"
    case .duplicate: "品目コードまたは略号が既に使われています。"
    case .auditRequired: "在庫期間締めには在庫監査帳票の発行が必要です。"
    case .missingRecovery: "復元用の一時ファイルがありません。"
    default: "入力内容を確認してください。"
    }
}
