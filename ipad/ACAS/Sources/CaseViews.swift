import SwiftUI
import ACASCore

/// ケースの自動操作 (実際の端末へ 1 キーずつ入力する)
@MainActor
final class CaseRunModel: ObservableObject {
    let testCase: ReplayCase
    let terminal: TerminalModel
    let replay: Replay
    @Published var stepIndex = 0
    @Published var state = "ui.cases.running"
    @Published var changes = 0
    @Published var done = false
    private var task: Task<Void, Never>?

    init?(_ c: ReplayCase, app: AppModel) {
        guard let seed = app.seed(c.baseline), let r = try? Replay(c, seed: seed, l10n: app.l10n()) else { return nil }
        testCase = c; replay = r
        terminal = TerminalModel(session: r.session)
    }

    func run(keyDelay: UInt64 = 120_000_000, stepDelay: UInt64 = 900_000_000) {
        task = Task { [weak self] in
            guard let self else { return }
            terminal.start(testCase.app)
            try? await Task.sleep(nanoseconds: stepDelay)
            for (i, st) in testCase.steps.enumerated() {
                if Task.isCancelled { return }
                stepIndex = i + 1
                for ch in st.text ?? "" {
                    terminal.send(text: String(ch))
                    try? await Task.sleep(nanoseconds: keyDelay)
                }
                if let k = st.key, let key = Replay.key(k) { terminal.send(key) }
                try? await Task.sleep(nanoseconds: stepDelay)
            }
            changes = replay.recordChanges().filter { $0.file.hasSuffix(".dat") }.count
            state = "ui.cases.completed"
            done = true
        }
    }

    func stop() { task?.cancel(); terminal.stop() }
}

/// ケース実行画面: ケース ID と名称を常時表示する
struct CaseRunView: View {
    @StateObject var model: CaseRunModel
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            CaseBanner(id: model.testCase.id, title: model.testCase.title,
                       detail: "\("ui.cases.step".localizedString) \(model.stepIndex)/\(model.testCase.steps.count)   \(model.state.localizedString)" +
                           (model.done ? "   \("ui.cases.record_changes".localizedString): \(model.changes)" : ""))
            TerminalCanvas(cells: model.terminal.cells, cursor: model.terminal.cursor, showCursor: !model.terminal.finished)
            HStack {
                Button { model.stop(); onFinish() } label: { Label("ui.common.back".localized, systemImage: "chevron.left") }
                    .accessibilityIdentifier("case-back")
                Spacer()
                KeyBar { model.terminal.send($0) }
            }
            .foregroundColor(Theme.pale)
        }
        .padding(14)
        .background(Theme.navy.ignoresSafeArea())
        .onAppear { model.run() }
        .onChange(of: model.done) { _, d in
            if d { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.stop(); onFinish() } }
        }
    }
}

struct CaseBanner: View {
    let id: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: id).font(.system(size: 24, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.blue).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("case-id")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.title3.weight(.semibold)).foregroundColor(.white).lineLimit(1)
                Text(verbatim: detail).font(.subheadline).foregroundColor(Theme.sky).lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.deep)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// CALC ケース: 入力と計算結果を表示する
struct CalcRunView: View {
    let testCase: ReplayCase
    let program: String
    let input: [String: Any]
    let onFinish: () -> Void
    @State private var result = ""

    var body: some View {
        VStack(spacing: 18) {
            CaseBanner(id: testCase.id, title: testCase.title, detail: program)
            VStack(alignment: .leading, spacing: 16) {
                row("ui.cases.input", input.keys.sorted().map { "\($0) = \(input[$0]!)" }.joined(separator: "   "))
                row("ui.cases.result", result)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24).background(Theme.deep).clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
            Button { onFinish() } label: { Label("ui.common.back".localized, systemImage: "chevron.left") }
                .accessibilityIdentifier("case-back")
        }
        .padding(14)
        .background(Theme.navy.ignoresSafeArea())
        .onAppear {
            if program.isEmpty {
                result = "ui.cases.out_of_scope".localizedString
            } else if let r = Calc.run(program: program, input: input) {
                result = r.keys.sorted().map { "\($0) = \(r[$0]! is NSNull ? "null" : "\(r[$0]!)")" }.joined(separator: "   ")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onFinish() }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.localized).font(.headline).foregroundColor(Theme.sky)
            Text(verbatim: value).font(.system(size: 28, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                .accessibilityIdentifier(key)
        }
    }
}

/// ケース一覧 (サブシステム別)。1 件実行と連続実行。
struct CaseListView: View {
    @EnvironmentObject var app: AppModel
    let calcOnly: Bool
    let onClose: () -> Void
    @State private var subsystem = ""
    @State private var queue: [ReplayCase] = []
    @State private var current: ReplayCase?
    @State private var finished: Set<String> = []

    private var subsystems: [String] { calcOnly ? ["CALC"] : ["SYS", "GL", "SL", "PL", "ST", "IRS", "INT"] }
    private var visible: [ReplayCase] {
        app.cases.filter { calcOnly ? $0.subsystem == "CALC" : ($0.subsystem != "CALC" && (subsystem.isEmpty || $0.subsystem == subsystem)) }
    }

    var body: some View {
        NavigationStack {
            List(visible) { c in
                Button { queue = []; current = c } label: {
                    HStack {
                        Text(verbatim: c.id).font(.system(.body, design: .monospaced).weight(.bold)).foregroundColor(Theme.sky).frame(width: 110, alignment: .leading)
                        Text(verbatim: c.title).foregroundColor(.white).lineLimit(1)
                        Spacer()
                        if finished.contains(c.id) { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.blue) }
                    }
                }
                .accessibilityIdentifier("case-\(c.id)")
                .listRowBackground(Theme.deep)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.navy)
            .navigationTitle(Text((calcOnly ? "ui.calc.title" : "ui.cases.title").localized))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ui.common.back".localized) { onClose() }.accessibilityIdentifier("cases-back")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !calcOnly {
                        Picker("", selection: $subsystem) {
                            Text("ui.cases.filter_all".localized).tag("")
                            ForEach(subsystems, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 460)
                    }
                    Button("ui.cases.run_all".localized) { queue = visible; next() }.accessibilityIdentifier("run-all")
                }
            }
        }
        .fullScreenCover(item: $current) { c in
            Group {
                if c.subsystem == "CALC" {
                    let meta = calcMeta(c.id)
                    CalcRunView(testCase: c, program: meta.program, input: meta.input) { done(c) }
                } else if let m = CaseRunModel(c, app: app) {
                    CaseRunView(model: m) { done(c) }
                } else {
                    Color.clear.onAppear { done(c) }
                }
            }
            .id(c.id)
        }
        .onAppear {
            if let id = app.autoCase, let c = app.cases.first(where: { $0.id == id }) { current = c }
            else if let s = app.autoSuite { subsystem = s == "CALC" ? "" : s; queue = app.cases.filter { $0.subsystem == s }; next() }
        }
    }

    private func done(_ c: ReplayCase) {
        finished.insert(c.id)
        current = nil
        if !queue.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { next() } }
    }

    private func next() {
        guard !queue.isEmpty else { return }
        current = queue.removeFirst()
    }

    private func calcMeta(_ id: String) -> (program: String, input: [String: Any]) {
        guard let url = Bundle.main.url(forResource: "calc", withExtension: "json", subdirectory: "Cases"),
              let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]],
              let m = o[id] else { return ("", [:]) }
        return (m["program"] as? String ?? "", m["input"] as? [String: Any] ?? [:])
    }
}
