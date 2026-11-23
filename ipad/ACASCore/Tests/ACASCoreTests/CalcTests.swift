import XCTest
@testable import ACASCore

/// CALC ケース: レガシー実測 (シナリオ台帳の legacy_result.actual) と突合する。
final class CalcTests: XCTestCase {
    func testCalcAgainstLegacy() throws {
        guard let ev = ReplayTests.evidence else { throw XCTSkip("証跡ディレクトリが無い (ACAS_EVIDENCE)") }
        let ledger = try JSONSerialization.jsonObject(with: Data(contentsOf: ev.appendingPathComponent("入力/シナリオ台帳.json"))) as! [String: Any]
        var results: [[String: Any]] = []
        var failed: [String] = []
        for c in ledger["cases"] as! [[String: Any]] where c["subsystem"] as? String == "CALC" {
            let id = c["id"] as! String
            let lr = c["legacy_result"] as! [String: Any]
            if lr["verdict"] as? String == "未実施" {
                results.append(["id": id, "status": "対象外", "reason": "レガシー未実施 (ブラウザ専用の期待値で端末版に比較対象が無い)"])
                continue
            }
            let program = (c["programs"] as? [String])?.first ?? ""
            let got = Calc.run(program: program, input: c["input_data"] as? [String: Any] ?? [:]) ?? [:]
            let want = lr["actual"] as? [String: Any] ?? [:]
            let same = NSDictionary(dictionary: got).isEqual(to: want)
            results.append(["id": id, "status": same ? "一致" : "不一致", "actual": got, "legacy": want])
            if !same { failed.append("\(id): ipad=\(got) legacy=\(want)") }
        }
        if let out = ProcessInfo.processInfo.environment["ACAS_CALC_RESULTS"] {
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: out))
        }
        print("CALC: 一致 \(results.filter { $0["status"] as? String == "一致" }.count) / 対象外 \(results.filter { $0["status"] as? String == "対象外" }.count) / 不一致 \(failed.count)")
        XCTAssertTrue(failed.isEmpty, failed.joined(separator: "\n"))
    }
}
