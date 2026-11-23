import ACASCore
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

    var before: EvidenceComparison.Snapshot = [:]
    @Published private(set) var result: String?
    var date: Date { Date(timeIntervalSince1970: dateSeconds) }

    enum CodingKeys: String, CodingKey {
        case id, title, workflow, dateSeconds, seed, changes, reports, calculation
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
}

struct CaseBanner: View {
    @ObservedObject var evidence: DebugEvidence
    private var verdict: String {
        if evidence.workflow == "legacy-not-run" { return "notApplicable" }
        return evidence.result ?? "running"
    }

    var body: some View {
        HStack {
            Text(evidence.id).font(.headline).monospacedDigit()
            Text(evidence.title)
            Spacer()
            Text(LocalizedStringKey("case." + verdict))
                .bold()
                .accessibilityIdentifier("case.verdict." + verdict)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
#endif
