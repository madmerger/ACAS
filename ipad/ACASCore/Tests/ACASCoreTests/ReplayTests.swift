import XCTest
@testable import ACASCore

/// レガシー実測 (証跡 zip を展開したディレクトリ) と突き合わせるヘッドレス同一性テスト。
/// 環境変数: ACAS_EVIDENCE=証跡ディレクトリ, ACAS_CASES=ケース ID の正規表現 (省略時は全件),
///           ACAS_RESULTS=結果 JSON の出力先, ACAS_LANG=en|ja (既定 en: レガシー画面と文字単位で比較)
final class ReplayTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var resources: URL { root.appendingPathComponent("ACAS/Resources") }
    static var evidence: URL? {
        let p = ProcessInfo.processInfo.environment["ACAS_EVIDENCE"] ?? NSHomeDirectory() + "/work/evidence"
        return FileManager.default.fileExists(atPath: p + "/入力/シナリオ台帳.json") ? URL(fileURLWithPath: p) : nil
    }

    static func normalize(_ s: String) -> [String] {
        var lines = s.replacingOccurrences(of: #"\d\d:\d\d:\d\d"#, with: "HH:MM:SS", options: .regularExpression)
            .components(separatedBy: "\n").map { Cobol.rtrim($0) }
        while let l = lines.last, l.isEmpty { lines.removeLast() }
        return lines
    }

    /// system.dat (相対編成) と IRS の行順編成ファイルをレコード単位へ分解して比較用の集合にする
    static func split(_ file: String, _ key: String, _ hex: String?) -> [String: String] {
        guard let hex else { return [:] }
        if file.hasSuffix("acas/system.dat") {
            var out: [String: String] = [:]
            let chars = Array(hex)
            var i = 0, n = 1
            while i + 2064 <= chars.count {
                out[String(format: "%08d", n)] = String(chars[(i + 16)..<(i + 2064)])
                i += 2064; n += 1
            }
            return out
        }
        // 相対編成 (posting.dat 等): 8 バイトのレコード長 + レコード の並びを RRN ごとに分解
        if key.isEmpty, hex.count >= 16, let len = Int(String(hex.prefix(2)), radix: 16), len > 0,
           hex.dropFirst(2).prefix(14) == "00000000000000", hex.count % ((len + 8) * 2) == 0 {
            var out: [String: String] = [:]
            let chars = Array(hex), slot = (len + 8) * 2
            var i = 0, n = 1
            while i + slot <= chars.count {
                if String(chars[i..<(i + 16)]) != "0000000000000000" { out[String(format: "%08d", n)] = String(chars[(i + 16)..<(i + slot)]) }
                i += slot; n += 1
            }
            return out
        }
        if key.isEmpty {
            var h = hex
            while h.hasSuffix("0a") { h.removeLast(2) }
            return ["1": h]
        }
        return [key: hex]
    }

    func testReplayAgainstLegacy() throws {
        guard let ev = Self.evidence else { throw XCTSkip("証跡ディレクトリが無い (ACAS_EVIDENCE)") }
        let env = ProcessInfo.processInfo.environment
        let cases = try ReplayCase.load(Data(contentsOf: Self.resources.appendingPathComponent("Cases/cases.json")))
        let filter = env["ACAS_CASES"].flatMap { try? NSRegularExpression(pattern: $0) }
        let ledger = try JSONSerialization.jsonObject(with: Data(contentsOf: ev.appendingPathComponent("入力/シナリオ台帳.json"))) as! [String: Any]
        var legacy: [String: [String: Any]] = [:]
        for c in ledger["cases"] as! [[String: Any]] { legacy[c["id"] as! String] = c["legacy_result"] as? [String: Any] }
        let lang = L10n.Language(rawValue: env["ACAS_LANG"] ?? "en") ?? .en
        var results: [[String: Any]] = []
        var failed: [String] = []

        for c in cases where c.subsystem != "CALC" {
            if let f = filter, f.firstMatch(in: c.id, range: NSRange(c.id.startIndex..., in: c.id)) == nil { continue }
            guard let lr = legacy[c.id], let targets = lr["comparison_targets"] as? [String: Any] else { continue }
            let verdict = lr["verdict"] as? String ?? ""
            if verdict == "未実施" { results.append(["id": c.id, "status": "対象外", "reason": "レガシー未実施"]); continue }
            let screenFiles = targets["screen_text"] as? [String] ?? []
            // レガシー実行時刻 (terminal.cast の timestamp) を現在日時として注入
            var now = Date()
            if let first = screenFiles.first {
                let cast = ev.appendingPathComponent(first).deletingLastPathComponent().appendingPathComponent("terminal.cast")
                if let head = try? String(contentsOf: cast, encoding: .utf8).components(separatedBy: "\n").first,
                   let o = try? JSONSerialization.jsonObject(with: Data(head.utf8)) as? [String: Any], let ts = o["timestamp"] as? Double {
                    now = Date(timeIntervalSince1970: ts)
                }
            }
            let seedName = c.baseline == "pure-function" ? "empty" : c.baseline
            let seed = try Data(contentsOf: Self.resources.appendingPathComponent("Seeds/\(seedName).json"))
            let l10n = try L10n(directory: Self.resources.appendingPathComponent("Localization"), language: lang)
            let r = try Replay(c, seed: seed, l10n: l10n, now: now, timeZone: TimeZone(identifier: "UTC"))
            let screens = r.runAll()
            var diffs: [String] = []
            if lang == .en {
                for (i, f) in screenFiles.enumerated() {
                    guard let want = try? String(contentsOf: ev.appendingPathComponent(f), encoding: .utf8) else { continue }
                    let a = Self.normalize(want), b = i < screens.count ? Self.normalize(screens[i]) : ["<画面なし>"]
                    if a != b {
                        var d = "画面\(i) 相違:"
                        for l in 0..<max(a.count, b.count) {
                            let x = l < a.count ? a[l] : "", y = l < b.count ? b[l] : ""
                            if x != y { d += "\n  L\(l + 1) legacy|\(x)\n  L\(l + 1) ipad  |\(y)" }
                        }
                        diffs.append(d)
                    }
                }
            } else {
                for (i, st) in c.steps.enumerated() where st.expect != nil && i >= screens.count { diffs.append("画面\(i) なし") }
                // 日本語画面: 入力欄の括弧 [ ] の行・桁がレガシー画面と同じセル位置にあること
                if env["ACAS_BRACKETS"] != nil {
                    func cols(_ line: String) -> [String] {
                        var out: [String] = [], col = 0
                        for ch in line {
                            if ch == "[" || ch == "]" { out.append("\(ch)\(col)") }
                            col += CellWidth.of(ch)
                        }
                        return out
                    }
                    for (i, f) in screenFiles.enumerated() where i < screens.count {
                        guard let want = try? String(contentsOf: ev.appendingPathComponent(f), encoding: .utf8) else { continue }
                        let a = Self.normalize(want), b = Self.normalize(screens[i])
                        for l in 0..<max(a.count, b.count) {
                            let x = l < a.count ? a[l] : "", y = l < b.count ? b[l] : ""
                            if x.contains("nohup") || (l > 0 && a[l - 1].contains("nohup")) { continue }
                            if cols(x) != cols(y) { diffs.append("画面\(i) L\(l + 1) 括弧位置相違\n  legacy|\(x)\n  ipad  |\(y)") }
                        }
                    }
                }
            }
            // レコード差分
            if let rd = targets["keyed_record_diff"] as? String,
               let o = try? JSONSerialization.jsonObject(with: Data(contentsOf: ev.appendingPathComponent(rd))) as? [String: Any] {
                var want = Set<String>()
                for ch in o["changes"] as? [[String: Any]] ?? [] {
                    let after = (ch["after"] as? [String: Any])?["hex"] as? String
                    want.insert("\(ch["file"] ?? "")|\(ch["operation"] ?? "")|\(after ?? "")")
                }
                var got = Set<String>()
                for ch in r.recordChanges() {
                    let o = Self.split(ch.file, ch.key, ch.before), n = Self.split(ch.file, ch.key, ch.after)
                    for k in Set(o.keys).union(n.keys) where o[k] != n[k] {
                        got.insert("\(ch.file)|\(o[k] == nil ? "追加" : n[k] == nil ? "削除" : "変更")|\(n[k] ?? "")")
                    }
                }
                // 帳票・一時ファイルは別途比較
                // 空ファイルの新規作成はレガシーの論理レコード差分に現れない (例: gl050 が作る 0 バイトの posting.dat)
                got = got.filter { $0.contains(".dat|") && !$0.hasSuffix("|追加|") }
                // レガシー側でレコード展開できなかったファイル (unsupported_files。例: gl120 が作る final.dat) は突合対象外
                let unsupported = Set(o["unsupported_files"] as? [String] ?? [])
                got = got.filter { !unsupported.contains(String($0.prefix { $0 != "|" })) }
                                // レガシー実測がレコード単位に読めなかったファイル (after-records の unsupported_files) は実測側に差分が無いので比較対象外
                let recs = ev.appendingPathComponent(rd).deletingLastPathComponent().appendingPathComponent("after-records/records.json")
                if let ro = try? JSONSerialization.jsonObject(with: Data(contentsOf: recs)) as? [String: Any],
                   let unsupported = ro["unsupported_files"] as? [String], !unsupported.isEmpty {
                    got = got.filter { g in !unsupported.contains { g.hasPrefix($0 + "|") } }
                }
                if want != got {
                    diffs.append("レコード差分 相違: legacyのみ \(want.subtracting(got).sorted().map { String($0.prefix(160)) }) / ipadのみ \(got.subtracting(want).sorted().map { String($0.prefix(160)) })")
                }
            }
            r.runner.stop()
            results.append(["id": c.id, "subsystem": c.subsystem, "status": diffs.isEmpty ? "一致" : "不一致",
                            "legacy_verdict": verdict, "diffs": diffs, "screens": screens.count])
            if !diffs.isEmpty { failed.append(c.id); if env["ACAS_VERBOSE"] != nil { print("== \(c.id)\n" + diffs.joined(separator: "\n")) } }
        }
        if let out = env["ACAS_RESULTS"] {
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: out))
        }
        let ok = results.filter { $0["status"] as? String == "一致" }.count
        print("REPLAY: 一致 \(ok) / 実行 \(results.count) / 不一致 \(failed.count): \(failed.prefix(40).joined(separator: " "))")
        if env["ACAS_STRICT"] != nil { XCTAssertTrue(failed.isEmpty, "不一致: \(failed)") }
    }
}
