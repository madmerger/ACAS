import ACASCore
import SwiftUI

struct MasterSetupMenu: View {
    let workspace: Workspace

    var body: some View {
        List {
            ForEach(MasterKind.allCases) { kind in
                NavigationLink(systemSetting("master." + kind.rawValue)) {
                    MasterEntry(workspace: workspace, kind: kind)
                }
                .accessibilityIdentifier("system.master." + kind.rawValue)
            }
        }
        .navigationTitle(systemSetting("master.title"))
    }
}

private enum MasterKind: String, CaseIterable, Identifiable {
    case customer, supplier, stock
    var id: String { rawValue }
}

private struct MasterEntry: View {
    let workspace: Workspace
    let kind: MasterKind
    @State private var contact = MasterContact()
    @State private var stock = MasterStockItem()
    @State private var amounts: [String: String] = [:]
    @FocusState private var focused: String?
    @State private var status: String?

    var body: some View {
        Form {
            if kind == .stock {
                field("code", $stock.code)
                field("abbreviation", $stock.abbreviation)
                field("name", $stock.name)
                field("location", $stock.location)
                ForEach(["held", "on-order", "reorder-point", "reorder-quantity", "retail", "cost", "value"], id: \.self) { key in
                    field(key, Binding { amounts[key, default: ""] } set: { amounts[key] = $0 }, numeric: true)
                }
            } else {
                field("code", $contact.code)
                field("name", $contact.name)
                field("address", $contact.address)
                field("address2", $contact.address2)
                field("phone", $contact.phone)
                field("email", $contact.email)
            }
            if let status { Text(status).accessibilityIdentifier("system.master.status") }
        }
        .navigationTitle(systemSetting("master." + kind.rawValue))
        .toolbar {
            Button(String(localized: "system.action.save", table: "System"), action: save)
                .accessibilityIdentifier("system.master.save")
        }
    }

    private func field(_ name: String, _ value: Binding<String>, numeric: Bool = false) -> some View {
        TextField(systemSetting("master." + name), text: value)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(numeric ? .numbersAndPunctuation : .default)
            .focused($focused, equals: name)
            .submitLabel(.done)
            .onSubmit { focused = nil }
            .accessibilityIdentifier("system.master.field." + name)
    }

    private func save() {
        do {
            let service = MasterSetup(workspace.context)
            if kind == .stock {
                var item = stock
                item.held = try amount("held", scale: 0)
                item.onOrder = try amount("on-order", scale: 0)
                item.reorderPoint = try amount("reorder-point", scale: 0)
                item.reorderQuantity = try amount("reorder-quantity", scale: 0)
                item.retail = try amount("retail", scale: 2)
                item.cost = try amount("cost", scale: 4)
                item.value = try amount("value", scale: 2)
                try service.add(item)
                stock = MasterStockItem()
                amounts.removeAll()
            } else {
                try service.add(contact, as: kind == .customer ? .customer : .supplier)
                contact = MasterContact()
            }
            focused = nil
            status = systemSetting("master.saved")
            workspace.completed("company")
        } catch MasterSetup.Error.missingCompany {
            status = systemSetting("master.missing-company")
        } catch MasterSetup.Error.duplicate {
            status = systemSetting("master.duplicate")
        } catch MasterSetup.Error.invalidInput {
            status = systemSetting("master.invalid")
        } catch {
            status = systemSetting("master.failed")
        }
    }

    private func amount(_ key: String, scale: Int) throws -> Int64 {
        let raw = amounts[key, default: ""]
        if raw.isEmpty { return 0 }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= (scale == 0 ? 1 : 2),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let whole = Int64(parts[0]), whole < 1_000_000_000
        else { throw MasterSetup.Error.invalidInput }
        if parts.count == 1 { return whole * Cobol.pow10(scale) }
        guard parts[1].count <= scale, let fraction = Int64(parts[1]) else { throw MasterSetup.Error.invalidInput }
        return whole * Cobol.pow10(scale) + fraction * Cobol.pow10(scale - parts[1].count)
    }
}
