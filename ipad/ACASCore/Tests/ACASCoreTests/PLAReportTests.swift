import XCTest
@testable import ACASCore

/// 買掛元帳 前半の追加突合 (ReplayTests が比較しないもの):
/// - 帳票 (prt-1) をレガシー実測の帳票ファイルとバイト単位で比較する
/// - iPad 側で追加・変更した索引ファイルのレコードが、レガシー実測後のファイル (runs/<ケース>/files/...) の中に
///   同じバイト列で存在するかを確認する (record-diff.json が unsupported とした value.dat / openitm5.dat 等も対象)
/// 環境変数は ReplayTests と同じ (ACAS_EVIDENCE, ACAS_CASES)。ACAS_REPORT_DUMP=ディレクトリ で iPad 側の帳票を書き出す。
final class PLAReportTests: XCTestCase {
    func testReportsAndFilesAgainstLegacy() throws {
        guard let ev = ReplayTests.evidence else { throw XCTSkip("証跡ディレクトリが無い (ACAS_EVIDENCE)") }
        let env = ProcessInfo.processInfo.environment
        let cases = try ReplayCase.load(Data(contentsOf: ReplayTests.resources.appendingPathComponent("Cases/cases.json")))
        let filter = env["ACAS_CASES"].flatMap { try? NSRegularExpression(pattern: $0) }
        let ledger = try JSONSerialization.jsonObject(with: Data(contentsOf: ev.appendingPathComponent("入力/シナリオ台帳.json"))) as! [String: Any]
        var legacy: [String: [String: Any]] = [:]
        for c in ledger["cases"] as! [[String: Any]] { legacy[c["id"] as! String] = c["legacy_result"] as? [String: Any] }
        var reportFailed: [String] = [], reports = 0
        var fileFailed: [String] = [], fileCases = 0, records = 0
        for c in cases where c.subsystem == "PL" {
            if let f = filter, f.firstMatch(in: c.id, range: NSRange(c.id.startIndex..., in: c.id)) == nil { continue }
            guard let lr = legacy[c.id], let targets = lr["comparison_targets"] as? [String: Any],
                  let first = (targets["screen_text"] as? [String] ?? []).first else { continue }
            let runDir = ev.appendingPathComponent(first).deletingLastPathComponent()
            let filesDir = runDir.appendingPathComponent("files")
            guard FileManager.default.fileExists(atPath: filesDir.path) else { continue }
            var now = Date()
            if let head = try? String(contentsOf: runDir.appendingPathComponent("terminal.cast"), encoding: .utf8).components(separatedBy: "\n").first,
               let o = try? JSONSerialization.jsonObject(with: Data(head.utf8)) as? [String: Any], let ts = o["timestamp"] as? Double {
                now = Date(timeIntervalSince1970: ts)
            }
            let seedName = c.baseline == "pure-function" ? "empty" : c.baseline
            let seed = try Data(contentsOf: ReplayTests.resources.appendingPathComponent("Seeds/\(seedName).json"))
            let l10n = try L10n(directory: ReplayTests.resources.appendingPathComponent("Localization"), language: .en)
            let r = try Replay(c, seed: seed, l10n: l10n, now: now, timeZone: TimeZone(identifier: "UTC"))
            _ = r.runAll()
            // 帳票
            if let want = try? Data(contentsOf: filesDir.appendingPathComponent("ledgers/acas/prt-1")) {
                let got = Data(r.session.store.readRaw("ledgers/acas/prt-1") ?? [])
                reports += 1
                if let dir = env["ACAS_REPORT_DUMP"] { try? got.write(to: URL(fileURLWithPath: dir + "/\(c.id)-prt-1")) }
                if got != want {
                    reportFailed.append(c.id)
                    let a = [UInt8](want), b = [UInt8](got)
                    let at = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(a.count, b.count)
                    print("== REPORT \(c.id): 相違 (legacy \(a.count) バイト / ipad \(b.count) バイト、最初の相違位置 \(at))")
                }
            }
            // 索引ファイルのレコード
            var bad: [String] = [], any = false
            for ch in r.recordChanges() where !ch.key.isEmpty && ch.after != nil {
                guard let data = try? Data(contentsOf: filesDir.appendingPathComponent(ch.file)) else { continue }
                any = true; records += 1
                if data.range(of: Data(FileStore.bytes(hex: ch.after!))) == nil { bad.append("\(ch.file) [\(ch.key)]") }
            }
            if any { fileCases += 1 }
            if !bad.isEmpty { fileFailed.append(c.id); print("== FILES \(c.id): レガシーのファイルに無いレコード: \(bad)") }
            r.runner.stop()
        }
        print("REPORT: 一致 \(reports - reportFailed.count) / 実行 \(reports) / 不一致 \(reportFailed.count): \(reportFailed.joined(separator: " "))")
        print("FILES: 一致 \(fileCases - fileFailed.count) / 実行 \(fileCases) (レコード \(records) 件) / 不一致 \(fileFailed.count): \(fileFailed.joined(separator: " "))")
    }
}
