import Foundation

/// 80x24 の文字セル端末。レガシー (GnuCOBOL + ncurses) の画面と同じ座標系で描画する。
/// 全角文字は 2 セルを占有する。
public struct Cell: Equatable, Sendable {
    public var ch: Character = " "
    /// 全角文字の右半分 (描画しない)
    public var tail = false
    public var color: UInt8 = 0
    public var highlight = false
    public var reverse = false
}

public enum CellWidth {
    public static func of(_ c: Character) -> Int {
        guard let s = c.unicodeScalars.first else { return 1 }
        let v = s.value
        if v < 0x1100 { return 1 }
        if (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v) { return 2 }
        return 1
    }
    public static func of(_ s: String) -> Int { s.reduce(0) { $0 + of($1) } }

    /// セル幅 `width` に切り詰め/空白埋めする。
    public static func fit(_ s: String, _ width: Int) -> String {
        var out = ""
        var w = 0
        for c in s {
            let cw = of(c)
            if w + cw > width { break }
            out.append(c)
            w += cw
        }
        if w < width { out += String(repeating: " ", count: width - w) }
        return out
    }
}

public final class Terminal: @unchecked Sendable {
    public static let rows = 24
    public static let cols = 80
    private let lock = NSLock()
    private var cells = [Cell](repeating: Cell(), count: rows * cols)
    public private(set) var cursorLine = 1
    public private(set) var cursorCol = 1
    public private(set) var generation = 0
    public var onChange: (@Sendable () -> Void)?

    public init() {}

    private func touch() {
        generation &+= 1
    }

    public func notify() { onChange?() }

    public func moveCursor(_ line: Int, _ col: Int) {
        lock.lock(); defer { lock.unlock() }
        cursorLine = min(max(line, 1), Self.rows)
        cursorCol = min(max(col, 1), Self.cols)
        touch()
    }

    /// 1 始まりの行・桁へ文字列を書く。行末を越える分は捨てる。
    public func put(_ text: String, line: Int, col: Int, color: UInt8 = 0, highlight: Bool = false, reverse: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        guard (1...Self.rows).contains(line) else { return }
        var c = col
        for ch in text {
            let w = CellWidth.of(ch)
            if c < 1 { c += w; continue }
            if c + w - 1 > Self.cols { break }
            let i = (line - 1) * Self.cols + (c - 1)
            // 全角文字の片側を上書きする場合は残り半分を空白へ戻す
            if cells[i].tail, c > 1 { cells[i - 1] = Cell() }
            if w == 1, c < Self.cols, !cells[i].tail, cells[i + 1].tail { cells[i + 1] = Cell() }
            cells[i] = Cell(ch: ch, tail: false, color: color, highlight: highlight, reverse: reverse)
            if w == 2 {
                if c + 1 < Self.cols, cells[i + 2].tail { cells[i + 2] = Cell() }
                cells[i + 1] = Cell(ch: " ", tail: true, color: color, highlight: highlight, reverse: reverse)
            }
            c += w
        }
        cursorLine = line
        cursorCol = min(c, Self.cols)
        touch()
    }

    public func eraseScreen() {
        lock.lock(); defer { lock.unlock() }
        cells = [Cell](repeating: Cell(), count: Self.rows * Self.cols)
        touch()
    }

    /// 指定位置から画面末尾まで消去 (erase eos)
    public func eraseEOS(line: Int, col: Int) {
        lock.lock(); defer { lock.unlock() }
        guard (1...Self.rows).contains(line) else { return }
        let start = (line - 1) * Self.cols + max(col - 1, 0)
        for i in start..<cells.count { cells[i] = Cell() }
        touch()
    }

    /// 指定位置から行末まで消去 (erase eol)
    public func eraseEOL(line: Int, col: Int) {
        lock.lock(); defer { lock.unlock() }
        guard (1...Self.rows).contains(line) else { return }
        let start = (line - 1) * Self.cols + max(col - 1, 0)
        for i in start..<(line * Self.cols) { cells[i] = Cell() }
        touch()
    }

    public func snapshotCells() -> [Cell] {
        lock.lock(); defer { lock.unlock() }
        return cells
    }

    /// 行ごとの文字列 (全角の右半分は出力しない)
    public func lines() -> [String] {
        let snap = snapshotCells()
        return (0..<Self.rows).map { r in
            var s = ""
            for c in 0..<Self.cols {
                let cell = snap[r * Self.cols + c]
                if !cell.tail { s.append(cell.ch) }
            }
            return s
        }
    }

    public func text() -> String { lines().joined(separator: "\n") + "\n" }

    public func cellText(line: Int, col: Int, count: Int) -> String {
        let snap = snapshotCells()
        var s = ""
        for c in col..<min(col + count, Self.cols + 1) {
            let cell = snap[(line - 1) * Self.cols + c - 1]
            if !cell.tail { s.append(cell.ch) }
        }
        return s
    }
}
