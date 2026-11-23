import ACASCore
import SwiftUI

struct StockItemForm: View {
    enum Operation: String {
        case create, edit, delete, renumber, lookup, receive, issue, barcode, order

        var title: String {
            switch self {
            case .create: "在庫品目登録"
            case .edit: "在庫品目変更"
            case .delete: "在庫品目削除"
            case .renumber: "在庫コード変更"
            case .lookup: "在庫品目照会"
            case .receive: "入庫入力"
            case .issue: "出庫入力"
            case .barcode: "バーコード入庫"
            case .order: "在庫発注記録"
            }
        }
    }

    let workspace: Workspace
    let operation: Operation
    let date: Date
    @State private var code = ""
    @State private var item = StockService.Item()
    @State private var replacement = ""
    @State private var quantity = ""
    @State private var price = ""
    @State private var valueOverride = ""
    @State private var backOrdered = ""
    @State private var ordered: Date?
    @State private var due: Date?
    @State private var selected: String?
    @State private var message = ""
    @State private var confirmingDelete = false

    private var stock: StockService { StockService(workspace.context) }
    private var isReceipt: Bool { operation == .receive || operation == .barcode }

    var body: some View {
        Form {
            TextField(operation == .barcode ? "バーコード" : "品目コード", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("stock.code")
                .onChange(of: code) { _, _ in
                    selected = nil
                    message = ""
                }
            switch operation {
            case .create:
                itemFields
            case .edit:
                Button("品目を読み込む", action: load)
                if selected != nil { itemFields }
            case .receive, .issue, .barcode, .order:
                TextField(operation == .order ? "発注数" : "数量", text: $quantity)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("stock.quantity")
                if isReceipt {
                    TextField("仕入単価", text: $price)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("stock.price")
                    TextField("評価額の上書き（任意）", text: $valueOverride)
                        .keyboardType(.decimalPad)
                }
                if operation == .order {
                    TextField("未入荷数", text: $backOrdered).keyboardType(.numbersAndPunctuation)
                    optionalDate("発注日", value: $ordered)
                    optionalDate("納入予定日", value: $due)
                }
            case .renumber:
                TextField("新しい品目コード", text: $replacement)
            case .delete, .lookup:
                if selected != nil {
                    LabeledContent("品名", value: item.name)
                    LabeledContent("在庫数", value: item.held.formatted())
                }
            }
            if operation != .edit || selected != nil {
                Button(operation == .lookup ? "照会" : operation == .delete ? "削除" : "確定",
                       role: operation == .delete ? .destructive : nil) {
                    if operation == .delete {
                        load()
                        if selected != nil { confirmingDelete = true }
                    } else {
                        submit()
                    }
                }
                .accessibilityIdentifier("stock.action")
            }
            if !message.isEmpty {
                Text(message).accessibilityIdentifier("stock.result")
            }
        }
        .navigationTitle(operation.title)
        .confirmationDialog("この品目を削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive, action: submit)
        }
    }

    private var itemFields: some View {
        Group {
            TextField("品目略号", text: $item.abbreviation).accessibilityIdentifier("stock.abbreviation")
            TextField("品名", text: $item.name).accessibilityIdentifier("stock.name")
            TextField("在庫数", value: $item.held, format: .number).keyboardType(.numbersAndPunctuation)
            TextField("単価", value: $item.cost, format: .number.scale(0.0001)).keyboardType(.decimalPad)
            TextField("発注点", value: $item.reorderPoint, format: .number).keyboardType(.numbersAndPunctuation)
        }
    }

    @ViewBuilder private func optionalDate(_ title: String, value: Binding<Date?>) -> some View {
        Toggle(title + "を指定", isOn: Binding(
            get: { value.wrappedValue != nil },
            set: { value.wrappedValue = $0 ? date : nil }
        ))
        if value.wrappedValue != nil {
            DatePicker(title, selection: Binding(
                get: { value.wrappedValue ?? date },
                set: { value.wrappedValue = $0 }
            ), displayedComponents: .date)
        }
    }

    private func load() {
        do {
            item = try stock.find(code)
            selected = code
            message = ""
        } catch { message = stockError(error) }
    }

    private func money(_ text: String) throws -> Int64 {
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "ja_JP")),
              (0...99_999_999).contains(decimal) else { throw StockService.Failure.invalidInput }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }

    private func submit() {
        do {
            switch operation {
            case .create, .edit:
                item.code = code
                try stock.save(item, editing: operation == .edit ? selected : nil)
                message = "品目を保存しました。"
            case .delete:
                try stock.remove(code)
                selected = nil
                message = "品目を削除しました。"
            case .renumber:
                try stock.renumber(code, to: replacement)
                message = "品目コードを変更しました。"
            case .lookup:
                load()
            case .receive, .issue, .barcode:
                if quantity.isEmpty {
                    _ = try stock.find(code)
                }
                guard let count = Int64(quantity) else { throw StockService.Failure.invalidInput }
                let row = try stock.move(isReceipt ? .receipt : .issue, code: code, quantity: count,
                    price: isReceipt ? money(price) : 0,
                    valueOverride: valueOverride.isEmpty ? nil : money(valueOverride), date: date)
                message = "在庫数：\(row.held.formatted())"
            case .order:
                guard let count = Int64(quantity), let back = Int64(backOrdered)
                else { throw StockService.Failure.invalidInput }
                try stock.order(code, quantity: count, backOrdered: back, ordered: ordered, due: due)
                message = "発注を記録しました。"
            }
        } catch { message = stockError(error) }
        workspace.completed("stock." + operation.rawValue)
    }
}
