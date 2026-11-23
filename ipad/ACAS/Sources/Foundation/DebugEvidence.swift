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
    let rawFiles: [String: String]?
    let reports: [String: String]
    let reportSHA256: [String: String]?
    let calculation: DebugCalculation?

    var before: EvidenceComparison.Snapshot = [:]
    @Published private(set) var result: String?
    var date: Date { Date(timeIntervalSince1970: dateSeconds) }

    enum CodingKeys: String, CodingKey {
        case id, title, workflow, dateSeconds, seed, changes, rawFiles, reports, reportSHA256, calculation
    }

    static func load() throws -> DebugEvidence? {
        guard let fixture = ProcessInfo.processInfo.environment["ACAS_FIXTURE"] else { return nil }
        guard let bytes = Data(base64Encoded: fixture) else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(DebugEvidence.self, from: bytes)
    }

    func evaluate(store: FileStore, calculation actual: DebugCalculation?) {
        let changesMatch = EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(store)) == changes.sorted()
        let reportsMatch = EvidenceComparison.reportsAgree(reports, in: store) &&
            (reportSHA256 ?? [:]).allSatisfy { path, digest in
                guard let bytes = store.readRaw(path) else { return false }
                return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined() == digest
            }
        let rawFilesMatch = (rawFiles ?? [:]).allSatisfy { path, expected in
            store.readRaw(path).map(FileStore.hex) == expected
        }
        result = changesMatch && rawFilesMatch && reportsMatch && actual == calculation ? "match" : "mismatch"
    }
}

struct CaseBanner: View {
    @ObservedObject var evidence: DebugEvidence

    var body: some View {
        HStack {
            Text(evidence.id).font(.headline).monospacedDigit()
            Text(evidence.title)
            Spacer()
            Text(LocalizedStringKey("case." + (evidence.result ?? "running")))
                .bold()
                .accessibilityIdentifier("case.verdict." + (evidence.result ?? "running"))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
#endif
