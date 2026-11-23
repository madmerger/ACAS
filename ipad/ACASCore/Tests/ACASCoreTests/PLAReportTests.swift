import XCTest
@testable import ACASCore

/// 買掛元帳 前半: 帳票 (prt-1) をレガシー実測の帳票ファイルとバイト単位で突き合わせる。
/// 環境変数は ReplayTests と同じ (ACAS_EVIDENCE, ACAS_CASES)。ACAS_REPORT_DUMP=ディレクトリ で iPad 側の帳票を書き出す。
final class PLAReportTests: XCTestCase {
    func testReportsAgainstLegacy() throws {
        guard let ev = ReplayTests.evidence else { throw XCTSkip("証跡ディレクトリが無い (ACAS_EVIDENCE)") }
        let env = ProcessInfo.processInfo.environment
        let cases = try ReplayCase.load(Data(contentsOf: ReplayTests.resources.appendingPathComponent("Cases/cases.json")))
        let filter = env["ACAS_CASES"].flatMap { try? NSRegularExpression(pattern: $0) }
        let ledger = try JSONSerialization.jsonObject(with: Data(contentsOf: ev.appendingPathComponent("入力/シナリオ台帳.json"))) as! [String: Any]
        var legacy: [String: [String: Any]] = [:]
        for c in ledger["cases"] as! [[String: Any]] { legacy[c["id"] as! String] = c["legacy_result"] as? [String: Any] }
        var failed: [String] = [], n = 0
        for c in cases where c.subsystem == "PL" {
            if let f = filter, f.firstMatch(in: c.id, range: NSRange(c.id.startIndex..., in: c.id)) == nil { continue }
            guard let lr = legacy[c.id], let targets = lr["comparison_targets"] as? [String: Any],
                  let report = (targets["report_files"] as? [String] ?? []).first(where: { $0.hasSuffix("ledgers/acas/prt-1") }),
                  let want = try? Data(contentsOf: ev.appendingPathComponent(report)) else { continue }
            var now = Date()
            let cast = ev.appendingPathComponent(report).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("terminal.cast")
            if let head = try? String(contentsOf: cast, encoding: .utf8).components(separatedBy: "\n").first,
               let o = try? JSONSerialization.jsonObject(with: Data(head.utf8)) as? [String: Any], let ts = o["timestamp"] as? Double {
                now = Date(timeIntervalSince1970: ts)
            }
            let seedName = c.baseline == "pure-function" ? "empty" : c.baseline
            let seed = try Data(contentsOf: ReplayTests.resources.appendingPathComponent("Seeds/\(seedName).json"))
            let l10n = try L10n(directory: ReplayTests.resources.appendingPathComponent("Localization"), language: .en)
            let r = try Replay(c, seed: seed, l10n: l10n, now: now, timeZone: TimeZone(identifier: "UTC"))
            _ = r.runAll()
            let got = Data(r.session.store.readRaw("ledgers/acas/prt-1") ?? [])
            r.runner.stop()
            n += 1
            if let dir = env["ACAS_REPORT_DUMP"] { try? got.write(to: URL(fileURLWithPath: dir + "/\(c.id)-prt-1")) }
            if got != want {
                failed.append(c.id)
                let a = [UInt8](want), b = [UInt8](got)
                let at = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(a.count, b.count)
                print("== REPORT \(c.id): 相違 (legacy \(a.count) バイト / ipad \(b.count) バイト、最初の相違位置 \(at))")
            }
        }
        print("REPORT: 一致 \(n - failed.count) / 実行 \(n) / 不一致 \(failed.count): \(failed.joined(separator: " "))")
    }
}
