import SwiftUI
import UIKit
import ACASCore

/// 端末の表示状態 (Terminal の変更通知を SwiftUI へ橋渡しする)
@MainActor
final class TerminalModel: ObservableObject {
    let session: Session
    let runner: ProgramRunner
    @Published var cells: [Cell] = []
    @Published var cursor: (line: Int, col: Int) = (1, 1)
    @Published var finished = false
    @Published var reportNames: [String] = []

    init(session: Session) {
        self.session = session
        runner = ProgramRunner(session: session)
        cells = session.term.snapshotCells()
        session.term.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        runner.onFinish = { [weak self] _ in
            DispatchQueue.main.async { self?.finished = true; self?.refresh() }
        }
    }

    func refresh() {
        cells = session.term.snapshotCells()
        cursor = (session.term.cursorLine, session.term.cursorCol)
        reportNames = session.store.fileNames().filter {
            let n = ($0 as NSString).lastPathComponent
            return n.hasPrefix("prt-") || n.hasPrefix("final-") || $0.contains("spool/")
        }
    }

    func start(_ program: String) { runner.start(program) }
    func send(_ key: Key) { session.console.keys.send(key) }
    func send(text: String) { session.console.keys.send(text: text) }
    func stop() { runner.stop() }

    func report(_ name: String) -> String {
        guard let b = session.store.readRaw(name) else { return "" }
        // 帳票はレガシーと同じ桁位置を保つため Shift_JIS (CP932) で保存している
        return SJIS.decode(b[...])
    }
}

/// 80x24 セルの描画
struct TerminalCanvas: View {
    let cells: [Cell]
    let cursor: (line: Int, col: Int)
    let showCursor: Bool

    var body: some View {
        Canvas { ctx, size in
            let cw = size.width / CGFloat(Terminal.cols), ch = size.height / CGFloat(Terminal.rows)
            let fontSize = min(ch * 0.78, cw * 1.55)
            guard cells.count == Terminal.rows * Terminal.cols else { return }
            for r in 0..<Terminal.rows {
                for c in 0..<Terminal.cols {
                    let cell = cells[r * Terminal.cols + c]
                    if cell.tail { continue }
                    let wide = CellWidth.of(cell.ch) == 2
                    let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw * (wide ? 2 : 1), height: ch)
                    if cell.reverse { ctx.fill(Path(rect), with: .color(Theme.blue)) }
                    if cell.ch == " " { continue }
                    let t = Text(String(cell.ch))
                        .font(.system(size: fontSize, weight: cell.highlight ? .bold : .regular, design: .monospaced))
                        .foregroundColor(cell.reverse ? .white : Theme.color(cell.color, highlight: cell.highlight))
                    ctx.draw(t, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                }
            }
            if showCursor {
                let rect = CGRect(x: CGFloat(cursor.col - 1) * cw, y: CGFloat(cursor.line) * ch - 3, width: cw, height: 3)
                ctx.fill(Path(rect), with: .color(.white))
            }
        }
        .aspectRatio(CGFloat(Terminal.cols) * 0.6 / CGFloat(Terminal.rows), contentMode: .fit)
        .padding(10)
        .background(Theme.navy)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.blue, lineWidth: 2))
        .accessibilityIdentifier("terminal")
    }
}

/// ハードウェアキーボード・ソフトウェアキーボード入力を Key へ変換する
struct KeyCapture: UIViewRepresentable {
    let onKey: (Key) -> Void
    @Binding var focused: Bool

    func makeUIView(context: Context) -> KeyInputView {
        let v = KeyInputView()
        v.onKey = onKey
        return v
    }
    func updateUIView(_ v: KeyInputView, context: Context) {
        v.onKey = onKey
        if focused, !v.isFirstResponder { DispatchQueue.main.async { _ = v.becomeFirstResponder() } }
        if !focused, v.isFirstResponder { DispatchQueue.main.async { _ = v.resignFirstResponder() } }
    }

    final class KeyInputView: UIView, UIKeyInput {
        var onKey: ((Key) -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var autocorrectionType: UITextAutocorrectionType = .no
        var keyboardType: UIKeyboardType = .asciiCapable
        func insertText(_ text: String) {
            for ch in text {
                if ch == "\n" || ch == "\r" { onKey?(.enter) } else if ch == "\t" { onKey?(.tab) } else { onKey?(.char(ch)) }
            }
        }
        func deleteBackward() { onKey?(.backspace) }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for p in presses {
                guard let k = p.key else { continue }
                switch k.keyCode {
                case .keyboardEscape: onKey?(.esc); handled = true
                case .keyboardUpArrow: onKey?(.up); handled = true
                case .keyboardDownArrow: onKey?(.down); handled = true
                case .keyboardLeftArrow: onKey?(.left); handled = true
                case .keyboardRightArrow: onKey?(.right); handled = true
                case .keyboardPageUp: onKey?(.pageUp); handled = true
                case .keyboardPageDown: onKey?(.pageDown); handled = true
                case .keyboardHome: onKey?(.home); handled = true
                case .keyboardEnd: onKey?(.end); handled = true
                case .keyboardF1: onKey?(.f(1)); handled = true
                case .keyboardF2: onKey?(.f(2)); handled = true
                case .keyboardF3: onKey?(.f(3)); handled = true
                case .keyboardF4: onKey?(.f(4)); handled = true
                default: break
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }
    }
}

/// 画面下のキーバー (ソフトキーボードに無いキー)
struct KeyBar: View {
    let send: (Key) -> Void
    var body: some View {
        HStack(spacing: 8) {
            key("ui.key.esc".localizedString, .esc, id: "key-esc")
            key("ui.key.tab".localizedString, .tab, id: "key-tab")
            key("↑", .up, id: "key-up"); key("↓", .down, id: "key-down")
            key("←", .left, id: "key-left"); key("→", .right, id: "key-right")
            key("PgUp", .pageUp, id: "key-pgup"); key("PgDn", .pageDown, id: "key-pgdn")
            ForEach([1, 2, 3, 4], id: \.self) { n in key("F\(n)", .f(n), id: "key-f\(n)") }
            key("ui.key.backspace".localizedString, .backspace, id: "key-bs")
            key("ui.key.enter".localizedString, .enter, id: "key-enter")
        }
    }
    private func key(_ label: String, _ k: Key, id: String) -> some View {
        Button { send(k) } label: {
            Text(verbatim: label).font(.system(size: 15, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(minWidth: 44)
                .background(Theme.deep).foregroundColor(Theme.pale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.blue, lineWidth: 1))
        }
        .accessibilityIdentifier(id)
    }
}

/// 端末 + キーバー + 帳票ビューア (対話利用)
struct TerminalScreen: View {
    @StateObject var model: TerminalModel
    let program: String
    let onClose: () -> Void
    @State private var focused = true
    @State private var showReports = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { model.stop(); onClose() } label: { Label("ui.common.back".localized, systemImage: "chevron.left") }
                    .accessibilityIdentifier("back")
                Spacer()
                if model.finished { Text("ui.terminal.finished".localized).foregroundColor(Theme.sky) }
                Spacer()
                Button { showReports = true } label: { Label("ui.terminal.reports".localized, systemImage: "doc.text") }
                    .accessibilityIdentifier("reports")
            }
            .foregroundColor(Theme.pale)
            TerminalCanvas(cells: model.cells, cursor: model.cursor, showCursor: !model.finished)
                .onTapGesture { focused = true }
            KeyBar { model.send($0) }
            KeyCapture(onKey: { model.send($0) }, focused: $focused).frame(width: 1, height: 1).opacity(0.01)
        }
        .padding(14)
        .background(Theme.navy.ignoresSafeArea())
        .onAppear { model.start(program) }
        .sheet(isPresented: $showReports) { ReportList(model: model) }
    }
}

/// 帳票 (印刷ファイル) の一覧と内容
struct ReportList: View {
    @ObservedObject var model: TerminalModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.reportNames.isEmpty { Text("ui.terminal.no_reports".localized) }
                ForEach(model.reportNames, id: \.self) { name in
                    NavigationLink(name) {
                        ScrollView([.horizontal, .vertical]) {
                            ReportGrid(text: model.report(name))
                                .padding()
                        }
                        .background(Theme.navy)
                        .navigationTitle(name)
                    }
                }
            }
            .navigationTitle(Text("ui.terminal.reports".localized))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ui.common.close".localized) { dismiss() } } }
        }
        .tint(Theme.blue)
    }
}

/// 帳票を桁グリッドで描く。全角文字は 2 桁ぶんを占め、半角との桁位置がずれない。
struct ReportGrid: View {
    let text: String
    private static let cw: CGFloat = 8, ch: CGFloat = 17

    private static func isWide(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return v >= 0x1100 && !(0xFF61...0xFF9F).contains(v)
    }

    var body: some View {
        let lines = text.replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: "\u{0C}", omittingEmptySubsequences: false) }
        let cols = lines.map { $0.reduce(0) { $0 + (Self.isWide($1) ? 2 : 1) } }.max() ?? 0
        Canvas { ctx, _ in
            for (row, line) in lines.enumerated() {
                var col = 0
                for c in line {
                    let w = Self.isWide(c) ? 2 : 1
                    if c != " " {
                        let t = Text(verbatim: String(c))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Theme.pale)
                        ctx.draw(t, at: CGPoint(x: (CGFloat(col) + CGFloat(w) / 2) * Self.cw,
                                                y: (CGFloat(row) + 0.5) * Self.ch))
                    }
                    col += w
                }
            }
        }
        .frame(width: CGFloat(max(cols, 1)) * Self.cw, height: CGFloat(max(lines.count, 1)) * Self.ch)
    }
}
