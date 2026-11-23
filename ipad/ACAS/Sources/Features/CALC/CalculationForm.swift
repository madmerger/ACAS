import ACASCore
import SwiftUI

struct CalculationForm: View {
    let workspace: Workspace
    @State private var function = Function.checkDigit
    @State private var inputs: [String: String] = [:]
    @State private var result: Result?
    @FocusState private var focus: String?
    #if DEBUG
    @State private var evidence = CalculationEvidence.load()
    @State private var evidenceIndex = 0
    #endif

    private enum Function: String, CaseIterable {
        case checkDigit, date, vat, age, average

        var fields: [String] {
            switch self {
            case .checkDigit: ["code"]
            case .date: ["date"]
            case .vat: ["net", "rate"]
            case .age: ["days"]
            case .average: ["value", "qty"]
            }
        }
    }

    private enum Result {
        case digit(Int?)
        case date(serial: Int, normalized: String)
        case invalidDate
        case value(String, String)
        case invalidNumber, divisionByZero

        #if DEBUG
        var oracleValues: [String: String] {
            switch self {
            case .digit(let digit):
                ["check": String(digit ?? 0), "valid": String(digit != nil)]
            case .date(let serial, let normalized):
                ["integer": String(serial), "normalized": normalized, "valid": "true"]
            case .invalidDate:
                ["integer": "0", "normalized": "", "valid": "false"]
            case .value(let name, let value):
                [name: value]
            case .invalidNumber, .divisionByZero:
                [:]
            }
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            #if DEBUG
            if let evidence, evidence.indices.contains(evidenceIndex) {
                evidenceBar(evidence[evidenceIndex], canAdvance: evidenceIndex + 1 < evidence.count)
            }
            #endif
            Form {
                Section {
                    Picker(selection: $function) {
                        ForEach(Function.allCases, id: \.self) { function in
                            Text(key(function.rawValue), tableName: "CALC")
                                .accessibilityIdentifier("calc.function." + function.rawValue)
                                .tag(function)
                        }
                    } label: {
                        Text("calc.function", tableName: "CALC")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: function) { reset() }
                }
                Section {
                    ForEach(function.fields, id: \.self) { field in
                        TextField(text: Binding(
                            get: { inputs[field, default: ""] },
                            set: { text in
                                guard text != inputs[field, default: ""] else { return }
                                inputs[field] = text
                                result = nil
                            }
                        )) {
                            Text(key("field." + field), tableName: "CALC")
                        }
                        .focused($focus, equals: field)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(field == "code" ? "calculation.code" : "calc.input." + field)
                    }
                    Button(action: calculate) {
                        Text("calc.execute", tableName: "CALC")
                    }
                    .accessibilityIdentifier("action.calculate")
                } header: {
                    Text("calc.input", tableName: "CALC")
                } footer: {
                    if function == .date {
                        Text("calc.date.hint", tableName: "CALC")
                    }
                }
                if let result {
                    Section {
                        output(result)
                    } header: {
                        Text("calc.output", tableName: "CALC")
                    }
                }
            }
        }
        .navigationTitle(String(localized: "calc.title", table: "CALC"))
    }

    private func key(_ name: String) -> LocalizedStringKey { LocalizedStringKey("calc." + name) }

    private func reset() {
        focus = nil
        inputs = [:]
        result = nil
    }

    private func calculate() {
        result = evaluate()
        focus = nil
        #if DEBUG
        if case .some(.digit(let digit)) = result {
            workspace.completed("check-digit", calculation: DebugCalculation(check: digit ?? 0, valid: digit != nil))
        }
        #endif
    }

    private func evaluate() -> Result {
        func amount(_ name: String, scale: Int = 2) -> Int64? {
            Calc.amount(inputs[name, default: ""], scale: scale)
        }
        switch function {
        case .checkDigit:
            return .digit(Maps09.checkDigit(inputs["code", default: ""]))
        case .date:
            guard let date = Calc.convertDate(inputs["date", default: ""]) else { return .invalidDate }
            return .date(serial: date.serial, normalized: date.normalized)
        case .vat:
            guard let net = amount("net"), let rate = amount("rate") else { return .invalidNumber }
            return .value("tax", fixed(Calc.vat(net: net, rate: rate), scale: 2))
        case .age:
            guard let days = amount("days", scale: 0) else { return .invalidNumber }
            return .value("bucket", String(Calc.ageBucket(days: days % 10_000_000)))
        case .average:
            guard let value = amount("value"), let qty = amount("qty", scale: 0) else { return .invalidNumber }
            guard let cost = Calc.averageCost(value: value, qty: qty) else { return .divisionByZero }
            return .value("cost", fixed(cost, scale: 4))
        }
    }

    private func fixed(_ value: Int64, scale: Int) -> String {
        let base = Cobol.pow10(scale)
        return (value < 0 ? "-" : "") + String(abs(value) / base) + "." + Cobol.z(value, scale)
    }

    @ViewBuilder private func output(_ result: Result) -> some View {
        switch result {
        case .digit(let digit):
            if let digit {
                row("checkDigit", String(digit), identifier: "calculation.result")
                Text("calc.validCode", tableName: "CALC").accessibilityIdentifier("calculation.valid")
            } else {
                Text("calc.invalidCode", tableName: "CALC").accessibilityIdentifier("calc.invalidCode")
            }
        case .date(let serial, let normalized):
            let parts = normalized.split(separator: "/")
            if parts.count == 3 {
                row("normalized", "\(parts[2])年\(parts[1])月\(parts[0])日")
            }
            row("serial", String(serial))
        case .invalidDate:
            Text("calc.invalidDate", tableName: "CALC").accessibilityIdentifier("calc.invalidDate")
        case .value(let name, let value):
            row(name, name == "bucket" ? value + "日" : value)
        case .invalidNumber:
            Text("calc.invalidNumber", tableName: "CALC")
        case .divisionByZero:
            Text("calc.divisionByZero", tableName: "CALC")
        }
    }

    private func row(_ name: String, _ value: String, identifier: String? = nil) -> some View {
        HStack {
            Text(key(name), tableName: "CALC")
            Spacer()
            Text(verbatim: value)
                .monospacedDigit()
                .accessibilityIdentifier(identifier ?? "calc.result." + name)
        }
    }

    #if DEBUG
    private func evidenceBar(_ item: CalculationEvidence, canAdvance: Bool) -> some View {
        let state: String = if item.expected == nil {
            "excluded"
        } else if let result {
            result.oracleValues == item.expected && workspace.context.store.fileNames().isEmpty ? "match" : "mismatch"
        } else {
            "running"
        }
        return HStack {
            Text(item.id).font(.headline).monospacedDigit()
            Text(item.title)
            Spacer()
            Text(key(state), tableName: "CALC")
                .bold()
                .accessibilityIdentifier("case.verdict." + state)
            Button {
                reset()
                evidenceIndex += 1
            } label: {
                Text("calc.next", tableName: "CALC")
            }
            .disabled(!canAdvance)
            .accessibilityIdentifier("calc.evidence.next")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
    #endif
}

#if DEBUG
private struct CalculationEvidence: Decodable {
    let id: String
    let title: String
    let expected: [String: String]?

    static func load() -> [Self]? {
        guard let environment = ProcessInfo.processInfo.environment["ACAS_CALC_EVIDENCE"],
              let data = Data(base64Encoded: environment) else { return nil }
        return try? JSONDecoder().decode([Self].self, from: data)
    }
}
#endif
