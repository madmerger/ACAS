import ACASCore
import SwiftUI

struct StockItemForm: View {
    enum Operation: String {
        case create, edit, delete, renumber, lookup, receive, issue, barcode, order

        var title: String {
            switch self {
            case .create: stockText("master.create")
            case .edit: stockText("master.edit")
            case .delete: stockText("master.delete")
            case .renumber: stockText("master.renumber")
            case .lookup: stockText("master.lookup")
            case .receive: stockText("movement.receive")
            case .issue: stockText("movement.issue")
            case .barcode: stockText("movement.barcode")
            case .order: stockText("movement.order")
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
    @State private var opened = false

    private var stock: StockService { StockService(workspace.context) }
    private var isReceipt: Bool { operation == .receive || operation == .barcode }

    var body: some View {
        Form {
            TextField(operation == .barcode ? stockText("field.barcode") : stockText("field.code"), text: $code)
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
                Button(stockText("action.load"), action: load)
                if selected != nil { itemFields }
            case .receive, .issue, .barcode, .order:
                TextField(operation == .order ? stockText("field.ordered") : stockText("field.quantity"), text: $quantity)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("stock.quantity")
                if isReceipt {
                    TextField(stockText("field.purchasePrice"), text: $price)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("stock.price")
                    TextField(stockText("field.valueOverride"), text: $valueOverride)
                        .keyboardType(.decimalPad)
                }
                if operation == .order {
                    TextField(stockText("field.backordered"), text: $backOrdered).keyboardType(.numbersAndPunctuation)
                    optionalDate(stockText("field.orderedDate"), value: $ordered)
                    optionalDate(stockText("field.due"), value: $due)
                }
            case .renumber:
                TextField(stockText("field.newCode"), text: $replacement)
            case .delete, .lookup:
                if selected != nil {
                    LabeledContent(stockText("field.name"), value: item.name)
                    LabeledContent(stockText("field.held"), value: item.held.formatted())
                }
            }
            if operation != .edit || selected != nil {
                Button(operation == .lookup ? stockText("action.lookup") : operation == .delete ? stockText("action.delete") : stockText("action.commit"),
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
        .onAppear {
            guard !opened else { return }
            opened = true
            if isReceipt || operation == .issue {
                do { try stock.prepareMovementEntry() }
                catch { message = stockError(error) }
            }
            workspace.completed("stock." + operation.rawValue + ".open")
        }
        .confirmationDialog(stockText("delete.confirm"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(stockText("action.confirmDelete"), role: .destructive, action: submit)
        }
    }

    private var itemFields: some View {
        Group {
            TextField(stockText("field.abbreviation"), text: $item.abbreviation).accessibilityIdentifier("stock.abbreviation")
            TextField(stockText("field.name"), text: $item.name).accessibilityIdentifier("stock.name")
            TextField(stockText("field.held"), value: $item.held, format: .number).keyboardType(.numbersAndPunctuation)
            TextField(stockText("field.price"), value: $item.cost, format: .number.scale(0.0001)).keyboardType(.decimalPad)
            TextField(stockText("field.value"), value: $item.value, format: .number.scale(0.01)).keyboardType(.decimalPad)
            TextField(stockText("field.reorder"), value: $item.reorderPoint, format: .number).keyboardType(.numbersAndPunctuation)
        }
    }

    @ViewBuilder private func optionalDate(_ title: String, value: Binding<Date?>) -> some View {
        Toggle(title + stockText("required"), isOn: Binding(
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
                message = stockText("result.saved")
            case .delete:
                try stock.remove(code)
                selected = nil
                message = stockText("result.deleted")
            case .renumber:
                try stock.renumber(code, to: replacement)
                message = stockText("result.renumbered")
            case .lookup:
                load()
            case .receive, .issue, .barcode:
                guard let count = Int64(quantity) else { throw StockService.Failure.invalidInput }
                let row = try stock.move(isReceipt ? .receipt : .issue, code: code, quantity: count,
                    price: isReceipt ? money(price) : 0,
                    valueOverride: valueOverride.isEmpty ? nil : money(valueOverride), date: date, codeOnly: operation == .barcode)
                message = String(format: stockText("result.held"), row.held.formatted())
            case .order:
                guard let count = Int64(quantity), let back = Int64(backOrdered)
                else { throw StockService.Failure.invalidInput }
                try stock.order(code, quantity: count, backOrdered: back, ordered: ordered, due: due)
                message = stockText("result.ordered")
            }
        } catch { message = stockError(error) }
        workspace.completed("stock." + operation.rawValue)
    }
}
