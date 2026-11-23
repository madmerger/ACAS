import Foundation

public enum Key: Equatable, Sendable {
    case char(Character)
    case enter, esc, tab, backTab, up, down, left, right, home, end
    case backspace, delete, insert, pageUp, pageDown
    case f(Int)
}

/// プログラム終了 (STOP RUN / 利用者による中断)
public struct StopRun: Error { public let code: Int; public init(code: Int = 0) { self.code = code } }

/// キー入力キュー。業務ロジックのスレッドは `next()` でブロックし、UI またはテストが `send` する。
public final class KeyQueue: @unchecked Sendable {
    private let cond = NSCondition()
    private var queue: [Key] = []
    private var waiting = false
    private var cancelled = false
    public init() {}

    public func send(_ key: Key) {
        cond.lock(); queue.append(key); cond.broadcast(); cond.unlock()
    }

    /// 文字列を 1 文字ずつ送る。"\r"=Enter, "\t"=Tab, ESC=0x1b。
    public func send(text: String) {
        // 端末のエスケープシーケンス (ESC O x / ESC [ x) はカーソルキーとして送る
        let seq: [Character: Key] = ["A": .up, "B": .down, "C": .right, "D": .left, "H": .home, "F": .end]
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            i += 1
            if ch == "\u{1b}", i + 1 < chars.count, chars[i] == "O" || chars[i] == "[", let k = seq[chars[i + 1]] {
                send(k); i += 2; continue
            }
            switch ch {
            case "\r", "\n": send(.enter)
            case "\t": send(.tab)
            case "\u{1b}": send(.esc)
            case "\u{7f}", "\u{08}": send(.backspace)
            default: send(.char(ch))
            }
        }
    }

    public func cancel() {
        cond.lock(); cancelled = true; cond.broadcast(); cond.unlock()
    }

    func next() throws -> Key {
        cond.lock(); defer { cond.unlock() }
        while queue.isEmpty {
            if cancelled { throw StopRun(code: -1) }
            waiting = true
            cond.broadcast()
            cond.wait()
        }
        waiting = false
        return queue.removeFirst()
    }

    /// 入力が尽き、プログラムが入力待ちで停止するまで待つ (テスト・自動操作用)。
    @discardableResult
    public func waitUntilIdle(timeout: TimeInterval = 10, finished: () -> Bool = { false }) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock(); defer { cond.unlock() }
        while !(waiting && queue.isEmpty) {
            if finished() { return true }
            if !cond.wait(until: min(deadline, Date().addingTimeInterval(0.02))) && Date() >= deadline { return false }
        }
        return true
    }

    public var isWaiting: Bool { cond.lock(); defer { cond.unlock() }; return waiting && queue.isEmpty }
}

public struct AcceptOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let update = AcceptOptions(rawValue: 1)
    public static let auto = AcceptOptions(rawValue: 2)
    public static let upper = AcceptOptions(rawValue: 4)
    public static let lower = AcceptOptions(rawValue: 8)
    public static let secure = AcceptOptions(rawValue: 16)
    public static let noEcho = AcceptOptions(rawValue: 32)
    public static let prompt = AcceptOptions(rawValue: 64)
}

public enum FieldKind: Sendable { case alpha, numeric, numericEdited }

/// 現在入力待ちの項目 (UI がタップ入力・日本語入力欄を重ねるために参照する)
public struct ActiveField: Equatable, Sendable {
    public var line: Int
    public var col: Int
    public var size: Int
    public var kind: FieldKind
    public var secure: Bool
}

/// SCREEN SECTION の入力項目
public final class ScreenField {
    public let line: Int
    public let col: Int
    public let size: Int
    public let kind: FieldKind
    public let pic: String?
    public let secure: Bool
    public var value: String
    public let color: UInt8
    public init(line: Int, col: Int, size: Int, kind: FieldKind = .alpha, pic: String? = nil, secure: Bool = false, value: String = "", color: UInt8 = 0) {
        self.line = line; self.col = col; self.size = size; self.kind = kind; self.pic = pic
        self.secure = secure; self.color = color
        self.value = CellWidth.fit(value, size)
    }
}

/// レガシーの DISPLAY ... AT / ACCEPT ... AT (GnuCOBOL 3.1.2 screenio.c) と同じ振る舞いをする入出力。
public final class Console: @unchecked Sendable {
    public let term: Terminal
    public let keys: KeyQueue
    /// COB-CRT-STATUS 相当 (0=Enter, 1001..=F キー, 2005=Esc ...)
    public var crtStatus = 0
    public private(set) var activeField: ActiveField?
    public var onBeep: (@Sendable () -> Void)?
    static let tailMark: Character = "\u{FFFF}"

    public init(term: Terminal = Terminal(), keys: KeyQueue = KeyQueue()) {
        self.term = term; self.keys = keys
    }

    func beep() { onBeep?() }

    // MARK: DISPLAY

    public func display(_ text: String, at line: Int, _ col: Int, color: UInt8 = 0, highlight: Bool = false,
                        reverse: Bool = false, eraseEOS: Bool = false, eraseEOL: Bool = false) {
        if eraseEOS { term.eraseEOS(line: line, col: col) }
        if eraseEOL { term.eraseEOL(line: line, col: col) }
        term.put(text, line: line, col: col, color: color, highlight: highlight, reverse: reverse)
        term.notify()
    }

    /// `display "x" at llcc` 形式 (llcc = 行*100+桁)
    public func display(_ text: String, at llcc: Int, color: UInt8 = 0, highlight: Bool = false,
                        reverse: Bool = false, eraseEOS: Bool = false, eraseEOL: Bool = false) {
        display(text, at: llcc / 100, llcc % 100, color: color, highlight: highlight, reverse: reverse,
                eraseEOS: eraseEOS, eraseEOL: eraseEOL)
    }

    public func eraseScreen() { term.eraseScreen(); term.notify() }

    // MARK: ACCEPT (単項目)

    private func cells(of s: String, size: Int) -> [Character] {
        var out: [Character] = []
        for ch in s {
            let w = CellWidth.of(ch)
            if out.count + w > size { break }
            out.append(ch)
            if w == 2 { out.append(Self.tailMark) }
        }
        while out.count < size { out.append(" ") }
        return out
    }

    private func string(of cells: [Character]) -> String { String(cells.filter { $0 != Self.tailMark }) }

    private func show(_ ch: Character, _ opts: AcceptOptions) -> Character {
        if opts.contains(.secure) { return "*" }
        if opts.contains(.noEcho) { return " " }
        return ch
    }

    private func put(_ ch: Character, _ line: Int, _ col: Int, _ color: UInt8) {
        if ch == Self.tailMark { return }
        term.put(String(ch), line: line, col: col, color: color)
    }

    /// 単項目 ACCEPT。戻り値は項目サイズ (セル数) に揃えた文字列。`crtStatus` を設定する。
    public func accept(at line: Int, _ col: Int, size: Int, kind: FieldKind = .alpha, initial: String = "",
                       options: AcceptOptions = [], color: UInt8 = 0) throws -> String {
        var buf = [Character](repeating: " ", count: size)
        if options.contains(.update) { buf = cells(of: initial, size: size) }
        // 初期表示
        for i in 0..<size {
            let ch: Character
            if options.contains(.secure) { ch = "*" }
            else if options.contains(.noEcho) { ch = " " }
            else if options.contains(.update) { ch = buf[i] }
            else if kind == .numeric { ch = "0" }
            else if options.contains(.prompt) { ch = "_" }
            else { ch = " " }
            put(ch, line, col + i, color)
        }
        var pos = 0
        var atEOF = false
        var fret = 0
        activeField = ActiveField(line: line, col: col, size: size, kind: kind, secure: options.contains(.secure))
        defer { activeField = nil }
        loop: while true {
            // 末尾のプロンプト文字
            var promptChar: Character = options.contains(.noEcho) ? " " : (kind == .numeric ? "0" : (options.contains(.prompt) ? "_" : " "))
            let blank: Character = kind == .numeric ? "0" : " "
            var i = size - 1
            while i >= 0 {
                if buf[i] == blank { put(promptChar, line, col + i, color) }
                else { promptChar = options.contains(.noEcho) ? " " : (options.contains(.secure) ? "*" : (kind == .numeric ? "0" : " ")) }
                i -= 1
            }
            term.moveCursor(line, col + pos)
            term.notify()
            let key = try keys.next()
            switch key {
            case .f(let n): fret = 1000 + n; break loop
            case .enter: break loop
            case .pageUp: fret = 2001; break loop
            case .pageDown: fret = 2002; break loop
            case .up: fret = 2003; break loop
            case .down: fret = 2004; break loop
            case .esc: fret = 2005; break loop
            case .tab: fret = 2007; break loop
            case .backTab: fret = 2008; break loop
            case .backspace:
                if pos > 0 {
                    var n = 1
                    if buf[pos - 1] == Self.tailMark { n = 2 }
                    for _ in 0..<n {
                        buf.remove(at: pos - 1)
                        buf.append(options.contains(.noEcho) ? " " : blank)
                        pos -= 1
                    }
                    for j in pos..<size { put(show(buf[j], options), line, col + j, color) }
                } else { beep() }
                atEOF = false
            case .home:
                let first = buf.firstIndex { $0 != " " } ?? pos
                pos = first != pos ? first : 0
                atEOF = false
            case .end:
                var target = pos
                if let last = buf.lastIndex(where: { $0 != " " }) { target = last == size - 1 ? last : last + 1 }
                pos = target != pos ? target : size - 1
                atEOF = false
            case .left:
                atEOF = false
                if pos > 0 { pos -= 1; if buf[pos] == Self.tailMark, pos > 0 { pos -= 1 } }
                else if options.contains(.auto) { fret = 2009; break loop }
                else { beep() }
            case .right:
                if pos < size - 1 { pos += 1; if buf[pos] == Self.tailMark, pos < size - 1 { pos += 1 } }
                else if options.contains(.auto) { fret = 2010; break loop }
                else { beep() }
            case .insert: break
            case .delete:
                var n = 1
                if pos + 1 < size, buf[pos + 1] == Self.tailMark { n = 2 }
                for _ in 0..<n { buf.remove(at: pos); buf.append(options.contains(.noEcho) ? " " : blank) }
                for j in pos..<size { put(show(buf[j], options), line, col + j, color) }
            case .char(var ch):
                if kind != .alpha, !("0"..."9").contains(ch) { beep(); continue }
                if options.contains(.upper) { ch = Character(String(ch).uppercased()) }
                else if options.contains(.lower) { ch = Character(String(ch).lowercased()) }
                let w = CellWidth.of(ch)
                if w == 2 {
                    if pos + 1 >= size { beep(); continue }
                    // 上書きされる全角文字の残り半分を消す
                    if pos + 2 < size, buf[pos + 2] == Self.tailMark { buf[pos + 2] = " " }
                    buf[pos] = ch; buf[pos + 1] = Self.tailMark
                    term.put(String(show(ch, options)), line: line, col: col + pos, color: color)
                    if pos + 1 == size - 1 {
                        if options.contains(.auto) { break loop }
                        atEOF = true
                    } else { pos += 2 }
                    continue
                }
                if buf[pos] == Self.tailMark, pos > 0 { buf[pos - 1] = " " }
                if pos + 1 < size, buf[pos + 1] == Self.tailMark { buf[pos + 1] = " " }
                buf[pos] = ch
                put(show(ch, options), line, col + pos, color)
                if pos == size - 1 {
                    if options.contains(.auto) { break loop }
                    if atEOF { beep() } else { atEOF = true }
                } else { pos += 1 }
            }
        }
        crtStatus = fret
        term.moveCursor(line, col + size)
        term.notify()
        return string(of: buf)
    }

    public func accept(at llcc: Int, size: Int, kind: FieldKind = .alpha, initial: String = "",
                       options: AcceptOptions = [], color: UInt8 = 0) throws -> String {
        try accept(at: llcc / 100, llcc % 100, size: size, kind: kind, initial: initial, options: options, color: color)
    }

    /// 任意キー待ち (accept omitted / 1 文字応答)
    public func waitKey() throws -> Key { term.notify(); return try keys.next() }

    // MARK: ACCEPT (SCREEN SECTION)

    private func redraw(_ f: ScreenField, accepting: Bool) {
        var c = f.col
        for ch in f.value {
            let shown: Character = f.secure ? "*" : ((accepting && (ch == " ")) ? "_" : ch)
            term.put(String(shown), line: f.line, col: c, color: f.color)
            c += CellWidth.of(ch)
        }
    }

    /// SCREEN SECTION の DISPLAY 相当 (入力項目は値そのまま)
    public func displayFields(_ fields: [ScreenField]) {
        for f in fields { redraw(f, accepting: false) }
        term.notify()
    }

    /// SCREEN SECTION の ACCEPT 相当。Tab/上下で項目移動、Enter で確定、Esc 等は `crtStatus` に設定。
    public func acceptScreen(_ fields: [ScreenField]) throws {
        guard !fields.isEmpty else { return }
        for f in fields { redraw(f, accepting: true) }
        var idx = 0
        var buf = cells(of: fields[0].value, size: fields[0].size)
        var pos = 0
        var atEOF = false
        var fret = 0
        func enter(_ i: Int) {
            fields[idx].value = string(of: buf)
            finalize(fields[idx])
            redraw(fields[idx], accepting: true)
            idx = (i + fields.count) % fields.count
            buf = cells(of: fields[idx].value, size: fields[idx].size)
            pos = 0; atEOF = false
        }
        defer { activeField = nil }
        loop: while true {
            let f = fields[idx]
            activeField = ActiveField(line: f.line, col: f.col, size: f.size, kind: f.kind, secure: f.secure)
            term.moveCursor(f.line, f.col + pos)
            term.notify()
            let key = try keys.next()
            switch key {
            case .f(let n): fret = 1000 + n; break loop
            case .enter: break loop
            case .pageUp: fret = 2001; break loop
            case .pageDown: fret = 2002; break loop
            case .esc: fret = 2005; break loop
            case .tab, .down: enter(idx + 1)
            case .backTab, .up: enter(idx - 1)
            case .home: enter(0)
            case .end: enter(fields.count - 1)
            case .left: if pos > 0 { pos -= 1 } else { enter(idx - 1) }
            case .right: if pos < f.size - 1 { pos += 1 } else { enter(idx + 1) }
            case .insert: break
            case .backspace:
                if pos > 0 {
                    buf.remove(at: pos - 1); buf.append(" "); pos -= 1
                    fields[idx].value = string(of: buf); redraw(f, accepting: true)
                } else { beep() }
                atEOF = false
            case .delete:
                buf.remove(at: pos); buf.append(" ")
                fields[idx].value = string(of: buf); redraw(f, accepting: true)
            case .char(let ch):
                if f.kind != .alpha, !("0"..."9").contains(ch), ch != ".", ch != "-", ch != "+" { beep(); continue }
                let w = CellWidth.of(ch)
                if pos + w > f.size { beep(); continue }
                buf[pos] = ch
                if w == 2 { buf[pos + 1] = Self.tailMark }
                fields[idx].value = string(of: buf)
                redraw(f, accepting: true)
                if pos + w - 1 == f.size - 1 {
                    if atEOF { beep() } else { atEOF = true }
                    if w == 2 { pos = f.size - 2 }
                } else { pos += w }
            }
        }
        fields[idx].value = string(of: buf)
        if fret == 0 { for f in fields { finalize(f) } }
        // ACCEPT 終了後もプロンプト文字は画面に残る (レガシーと同じ)
        crtStatus = fret
        term.notify()
    }

    private func finalize(_ f: ScreenField) {
        guard f.kind != .alpha, let pic = f.pic else { f.value = CellWidth.fit(f.value, f.size); return }
        let (v, scale) = Cobol.numval(f.value)
        f.value = Pic.edit(pic, value: v, scale: scale)
    }
}
