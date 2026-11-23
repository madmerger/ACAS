import Foundation

/// 業務プログラム (レガシーの 1 COBOL プログラムに対応)
public typealias Program = (Session) throws -> Void

/// 実行中の ACAS セッション。端末・DB・文言・日付と、CALL されるプログラムの登録表を持つ。
public final class Session: @unchecked Sendable {
    public let console: Console
    public let store: FileStore
    public let l10n: L10n
    /// 現在日時 (テストでは固定値を注入)
    public var now: () -> Date = { Date() }
    public var timeZone = TimeZone.current
    /// レガシーの ACAS_LEDGERS / ACAS_IRS に相当するデータ領域
    public var ledgers = "ledgers/acas/"
    public var irsDir = "ledgers/irs/"
    /// 環境変数相当 (未設定エラー SY008/SY009 の再現用)
    public var environment: [String: String] = ["ACAS_LEDGERS": "ledgers/acas", "ACAS_IRS": "ledgers/irs", "ACAS_BIN": "bin"]
    /// 起動引数 (レガシーの command-line 引数)
    public var arguments: [String] = []
    /// プログラム間で受け渡す共有領域 (LINKAGE 相当)
    public var shared: [String: Any] = [:]
    public var programs: [String: Program] = [:]
    /// 帳票が出力された時に UI へ知らせる
    public var onReport: (@Sendable (String) -> Void)?

    public init(console: Console = Console(), store: FileStore = FileStore(), l10n: L10n) {
        self.console = console; self.store = store; self.l10n = l10n
        Registry.registerAll(self)
    }

    public var term: Terminal { console.term }
    public func t(_ key: String) -> String { l10n.t(key) }

    /// CALL "name"。未登録は false (レガシーの ON EXCEPTION 相当)
    @discardableResult
    public func call(_ name: String) throws -> Bool {
        guard let p = programs[name.lowercased()] else { return false }
        try p(self)
        return true
    }

    // MARK: 日付・時刻 (accept from date / time)

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
    public var today: (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        return (c.year!, c.month!, c.day!)
    }
    public var time: (hour: Int, minute: Int, second: Int) {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now())
        return (c.hour!, c.minute!, c.second!)
    }
    /// dd/mm/yyyy (UK 形式。レガシー既定)
    public var todayUK: String {
        let d = today
        return "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/\(Cobol.z(d.year, 4))"
    }
    public var timeHHMMSS: String {
        let t = time
        return "\(Cobol.z(t.hour, 2)):\(Cobol.z(t.minute, 2)):\(Cobol.z(t.second, 2))"
    }

    // MARK: 帳票 (行順編成ファイル)

    public func printLine(_ file: String, _ line: String) {
        store.appendRaw(file, Array(Cobol.rtrim(line).utf8) + [0x0a])
    }
}

/// サブシステムごとのプログラム登録 (各サブシステムは自分の `register` だけを編集する)。
public enum Registry {
    static func registerAll(_ s: Session) {
        SystemPrograms.register(s)
        GLPrograms.register(s)
        SLPrograms.register(s)
        PLPrograms.register(s)
        StockPrograms.register(s)
        IRSPrograms.register(s)
    }
}

/// プログラムを専用スレッドで実行する (入力待ちでブロックするため)。
public final class ProgramRunner: @unchecked Sendable {
    public let session: Session
    private let lock = NSLock()
    private var _finished = false
    private var _exitCode = 0
    public var onFinish: (@Sendable (Int) -> Void)?
    public init(session: Session) { self.session = session }

    public var finished: Bool { lock.lock(); defer { lock.unlock() }; return _finished }
    public var exitCode: Int { lock.lock(); defer { lock.unlock() }; return _exitCode }

    public func start(_ name: String) {
        let t = Thread { [self] in
            var code = 0
            do {
                if try !session.call(name) { code = 127 }
            } catch let s as StopRun { code = s.code } catch { code = 1 }
            lock.lock(); _finished = true; _exitCode = code; lock.unlock()
            session.term.notify()
            onFinish?(code)
        }
        t.stackSize = 8 << 20
        t.start()
    }

    /// 文字列を送り、入力待ちで落ち着くまで待って画面を返す (テスト・自動操作用)
    @discardableResult
    public func feed(_ text: String, timeout: TimeInterval = 10) -> String {
        session.console.keys.send(text: text)
        return settle(timeout: timeout)
    }

    @discardableResult
    public func feed(key: Key, timeout: TimeInterval = 10) -> String {
        session.console.keys.send(key)
        return settle(timeout: timeout)
    }

    public func settle(timeout: TimeInterval = 10) -> String {
        session.console.keys.waitUntilIdle(timeout: timeout) { self.finished }
        return session.term.text()
    }

    public func stop() { session.console.keys.cancel() }
}
