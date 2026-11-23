import ACASCore
import CryptoKit
import SwiftUI

#if DEBUG
final class DebugEvidence: Decodable, ObservableObject {
    let id: String
    let title: String
    let workflow: String
    let dateSeconds: TimeInterval
    let seed: Data?
    let changes: [RecordChange]
    let reports: [String: String]
    let calculation: DebugCalculation?
    let equivalence: Equivalence?

    struct Equivalence: Decodable {
        struct Checkpoint: Decodable {
            let detail: String
        }
        struct Report: Decodable {
            let count: Int
            let sha256: String
        }
        let reportDigests: [String: Report]
        let outOfScope: String?
        let unprintedReports: [String]?
        let excludedPaths: [String]?
        let relativeRecordSizes: [String: Int]
        let checkpoint: Checkpoint?
        let clearedFiles: [String]?
    }

    var before: EvidenceComparison.Snapshot = [:]
    var exportDirectory: URL?
    @Published private(set) var result: String?
    @Published private(set) var details = ""
    var date: Date { Date(timeIntervalSince1970: dateSeconds) }

    enum CodingKeys: String, CodingKey {
        case id, title, workflow, dateSeconds, seed, changes, reports, calculation, equivalence
    }

    static func load() throws -> DebugEvidence? {
        guard let fixture = ProcessInfo.processInfo.environment["ACAS_FIXTURE"] else { return nil }
        guard let bytes = Data(base64Encoded: fixture) else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(DebugEvidence.self, from: bytes)
    }

    func evaluate(store: FileStore, calculation actual: DebugCalculation?) {
        let changesMatch = EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(store)) == changes.sorted()
        let reportsMatch = EvidenceComparison.reportsAgree(reports, in: store)
        for path in reports.keys {
            if let bytes = store.readRaw(path) { try? exportReport(bytes, path: path) }
        }
        result = changesMatch && reportsMatch && actual == calculation ? "match" : "mismatch"
    }

    private func exportReport(_ bytes: [UInt8], path: String) throws {
        guard let exportDirectory else { return }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try Data(bytes).write(to: exportDirectory.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent))
    }

    func snapshot(_ store: FileStore) -> EvidenceComparison.Snapshot {
        var snapshot = EvidenceComparison.snapshot(store, relativeRecordSizes: equivalence?.relativeRecordSizes ?? [:],
                                                   includeRawLedgers: equivalence != nil)
        if let equivalence {
            for path in (equivalence.excludedPaths ?? []) + (equivalence.clearedFiles ?? []) {
                snapshot.removeValue(forKey: path)
            }
        }
        return snapshot
    }

    func evaluateEquivalence(store: FileStore, screenMatches: Bool) {
        guard let equivalence else { return }
        if let reason = equivalence.outOfScope {
            details = reason
            result = "out_of_scope"
            return
        }
        var differences: [String] = []
        if !screenMatches, let checkpoint = equivalence.checkpoint {
            differences.append("画面相違：" + checkpoint.detail)
        }
        if equivalence.checkpoint != nil && store.readRaw(PurchaseLedger.reportPath) != nil {
            differences.append("旧証跡にはない帳票を生成")
        }
        let after = snapshot(store)
        let actual = EvidenceComparison.diff(before: before, after: after)
        let expected = changes.sorted()
        let unmatched = expected.filter { !actual.contains($0) } + actual.filter { !expected.contains($0) }
        for entry in Set(unmatched.map { "\($0.file):\($0.key)" }).sorted() {
            differences.append(entry)
        }
        for file in equivalence.clearedFiles ?? [] {
            if store.readRaw(file) != [] { differences.append("\(file)：原本は空ファイル、移行版は空ファイルを確認できず") }
        }
        for (path, report) in equivalence.reportDigests.sorted(by: { $0.key < $1.key }) {
            let originalBytes = store.readRaw(path)
            let comparesBeforePrinting = equivalence.unprintedReports?.contains(path) == true
            let bytes = originalBytes ?? (comparesBeforePrinting ? [] : nil)
            if let bytes {
                do {
                    try exportReport(bytes, path: path)
                } catch {
                    differences.append("\(path): 証跡の書き出し失敗")
                }
            }
            let digest = bytes.map { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
            if bytes?.count != report.count || digest != report.sha256 {
                differences.append("\(path): 期待 \(report.count) B / 実測 \(bytes.map { String($0.count) } ?? "なし")")
            }
        }
        if differences.isEmpty {
            details = equivalence.checkpoint?.detail ?? ((equivalence.unprintedReports ?? []).isEmpty
                ? "" : "条件画面到達：帳票未作成、原本 0 B")
        } else {
            details = differences.joined(separator: "; ")
        }
        result = differences.isEmpty ? "match" : "mismatch"
    }
}

struct CaseBanner: View {
    @ObservedObject var evidence: DebugEvidence
    var compare: ((Bool) -> Void)?

    var body: some View {
        HStack {
            Text(evidence.id).font(.headline).monospacedDigit()
            Text(evidence.title)
            Spacer()
            if evidence.equivalence != nil, let compare, evidence.result == nil {
                Button("case.compare") { compare(true) }.accessibilityIdentifier("case.compare")
                if evidence.equivalence?.checkpoint != nil {
                    Button("画面相違を記録") { compare(false) }.accessibilityIdentifier("case.compare.screenMismatch")
                }
            }
            Text(LocalizedStringKey("case." + (evidence.result ?? "running")))
                .bold()
                .accessibilityIdentifier("case.verdict." + (evidence.result ?? "running"))
                .accessibilityValue(evidence.details)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
#endif
