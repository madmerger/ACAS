import Foundation

/// 同一性テストの 1 ケース (シナリオ台帳の runner 部分)
public struct ReplayCase: Codable, Sendable, Identifiable {
    public struct Step: Codable, Sendable {
        public var text: String?
        public var key: String?
        public var expect: String?
    }
    public var id: String
    public var subsystem: String
    public var title: String
    public var baseline: String
    public var app: String
    public var irsPath: String?
    public var expectExit: Bool
    public var steps: [Step]
    public var menuPath: [String]?

    public static func load(_ data: Data) throws -> [ReplayCase] {
        try JSONDecoder().decode([ReplayCase].self, from: data)
    }
}

/// ケースを実行する (ヘッドレステストとアプリの自動操作の共通部)
public final class Replay: @unchecked Sendable {
    public let session: Session
    public let runner: ProgramRunner
    public let testCase: ReplayCase
    public private(set) var screens: [String] = []
    public private(set) var before: [String: [String: String]] = [:]

    public init(_ c: ReplayCase, seed: Data, l10n: L10n, now: Date? = nil, timeZone: TimeZone? = nil) throws {
        testCase = c
        session = Session(l10n: l10n)
        try session.store.load(seed: seed)
        if let now { session.now = { now } }
        if let timeZone { session.timeZone = timeZone }
        // レガシー実測 (INT-401): 単独 IRS は cwd (ledgers/irs) のファイルを使い、ACAS_IRS の値は参照先を変えない
        if let p = c.irsPath { session.environment["ACAS_IRS"] = p }
        runner = ProgramRunner(session: session)
        before = session.store.snapshot()
    }

    public static func key(_ name: String) -> Key? {
        switch name.uppercased() {
        case "ENTER": return .enter
        case "ESC": return .esc
        case "TAB": return .tab
        case "UP": return .up
        case "DOWN": return .down
        default:
            if name.uppercased().hasPrefix("F"), let n = Int(name.dropFirst()) { return .f(n) }
            return nil
        }
    }

    public func start() { runner.start(testCase.app) }

    /// 1 ステップ実行し、落ち着いた画面を返す
    @discardableResult
    public func step(_ i: Int, timeout: TimeInterval = 10) -> String {
        let st = testCase.steps[i]
        if let t = st.text { session.console.keys.send(text: t) }
        if let k = st.key, let key = Self.key(k) { session.console.keys.send(key) }
        let view = runner.settle(timeout: timeout)
        screens.append(view)
        return view
    }

    public func runAll() -> [String] {
        start()
        for i in testCase.steps.indices { step(i) }
        if testCase.steps.isEmpty { _ = runner.settle() }
        return screens
    }

    /// 実行前後のレコード差分 (file, key(hex), 操作, before(hex), after(hex))
    public func recordChanges() -> [(file: String, key: String, op: String, before: String?, after: String?)] {
        let after = session.store.snapshot()
        var out: [(String, String, String, String?, String?)] = []
        for file in Set(before.keys).union(after.keys).sorted() {
            let o = before[file] ?? [:], n = after[file] ?? [:]
            for k in Set(o.keys).union(n.keys).sorted() where o[k] != n[k] {
                out.append((file, k, o[k] == nil ? "追加" : n[k] == nil ? "削除" : "変更", o[k], n[k]))
            }
        }
        return out
    }
}
