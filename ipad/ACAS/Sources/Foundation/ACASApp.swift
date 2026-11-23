import ACASCore
import SwiftUI

@main
struct ACASApp: App {
    private let workspace = Workspace.open()

    var body: some Scene {
        WindowGroup {
            switch workspace {
            case .success(let workspace):
                MainMenu(workspace: workspace)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            case .failure:
                ContentUnavailableView("database.failed", systemImage: "externaldrive.badge.exclamationmark")
            }
        }
    }
}

@MainActor
final class Workspace: ObservableObject {
    let context: BusinessContext
    #if DEBUG
    let evidence: DebugEvidence?
    #endif

    static func open() -> Result<Workspace, Error> {
        Result { try Workspace() }
    }

    private init() throws {
        var root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        #if DEBUG
        evidence = try DebugEvidence.load()
        if evidence != nil {
            root = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            if let evidence, evidence.equivalence != nil {
                guard evidence.id.range(of: #"\APL-[0-9]{3}\z"#, options: .regularExpression) != nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let exports = root.resolvingSymlinksInPath().appendingPathComponent("pl-evidence")
                var run = exports
                if let token = ProcessInfo.processInfo.environment["ACAS_PL_RUN_ID"] {
                    guard let id = UUID(uuidString: token) else { throw CocoaError(.fileReadCorruptFile) }
                    run = exports.appendingPathComponent(id.uuidString)
                }
                let export = run.appendingPathComponent(evidence.id)
                guard exports.resolvingSymlinksInPath().path == exports.path,
                      run.resolvingSymlinksInPath().path == run.path,
                      export.resolvingSymlinksInPath().path == export.path else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if FileManager.default.fileExists(atPath: export.path) { try FileManager.default.removeItem(at: export) }
                evidence.exportDirectory = export
            }
            root = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        #endif
        let store = try FileStore(path: root.appendingPathComponent("ACAS.sqlite").path)
        #if DEBUG
        if let evidence {
            if let seed = evidence.seed { try store.load(seed: seed) }
            context = BusinessContext(store: store, timeZone: .gmt, now: { evidence.date })
            evidence.before = evidence.snapshot(store)
            return
        }
        #endif
        context = BusinessContext(store: store)
    }

    func completed(_ workflow: String, calculation: DebugCalculation? = nil) {
        #if DEBUG
        guard let evidence, evidence.workflow == workflow else { return }
        evidence.evaluate(store: context.store, calculation: calculation)
        #endif
    }
}

struct DebugCalculation: Codable, Equatable {
    let check: Int
    let valid: Bool
}
