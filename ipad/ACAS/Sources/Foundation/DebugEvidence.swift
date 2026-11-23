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
        struct Report: Decodable {
            let count: Int
            let sha256: String
        }
        let reportDigests: [String: Report]
        let outOfScope: String?
        let unprintedReports: [String]?
        let pathFilter: [String]?
        let relativeRecordSizes: [String: Int]
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
        result = changesMatch && reportsMatch && actual == calculation ? "match" : "mismatch"
    }

    func snapshot(_ store: FileStore) -> EvidenceComparison.Snapshot {
        var snapshot = EvidenceComparison.snapshot(store, relativeRecordSizes: equivalence?.relativeRecordSizes ?? [:])
        if let paths = equivalence?.pathFilter {
            snapshot = snapshot.filter { paths.contains($0.key) }
        }
        return snapshot
    }

    func evaluateEquivalence(store: FileStore) {
        guard let equivalence else { return }
        if let reason = equivalence.outOfScope {
            details = reason
            result = "out_of_scope"
            return
        }
        var differences: [String] = []
        let actual = EvidenceComparison.diff(before: before, after: snapshot(store))
        let expected = changes.sorted()
        let unmatched = expected.filter { !actual.contains($0) } + actual.filter { !expected.contains($0) }
        for entry in Set(unmatched.map { "\($0.file):\($0.key)" }).sorted() {
            differences.append(entry)
        }
        for (path, report) in equivalence.reportDigests.sorted(by: { $0.key < $1.key }) {
            let originalBytes = store.readRaw(path)
            let comparesBeforePrinting = equivalence.unprintedReports?.contains(path) == true
            let bytes = originalBytes ?? (comparesBeforePrinting ? [] : nil)
            if let exportDirectory, let bytes {
                do {
                    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
                    try Data(bytes).write(to: exportDirectory.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent))
                } catch {
                    differences.append("\(path): 証跡の書き出し失敗")
                }
            }
            let digest = bytes.map { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
            if bytes?.count != report.count || digest != report.sha256 {
                differences.append("\(path): 期待 \(report.count) B / 実測 \(bytes.map { String($0.count) } ?? "なし")")
            }
        }
        details = differences.isEmpty && !(equivalence.unprintedReports ?? []).isEmpty
            ? "条件画面到達：帳票未作成、原本 0 B" : differences.joined(separator: "; ")
        result = differences.isEmpty ? "match" : "mismatch"
    }
}

struct CaseBanner: View {
    @ObservedObject var evidence: DebugEvidence
    var compare: (() -> Void)?

    var body: some View {
        HStack {
            Text(evidence.id).font(.headline).monospacedDigit()
            Text(evidence.title)
            Spacer()
            if evidence.equivalence != nil, let compare, evidence.result == nil {
                Button("case.compare", action: compare).accessibilityIdentifier("case.compare")
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
