import SwiftUI
import ACASCore

struct SalesPostingView: View {
    let workspace: Workspace
    @State private var result: SalesPosting.Result?
    @State private var document: SalesReportDocument?
    @State private var failure: String.LocalizationValue?
    @State private var confirm = false

    var body: some View {
        List {
            if let result {
                Text(slText("sales.post.finished"))
                    .accessibilityIdentifier("sales.post.finished")
                if result.unprinted { Text(slText("sales.post.unprinted")) }
                ForEach(Array(result.posted.enumerated()), id: \.offset) { entry in
                    LabeledContent(slText("sales.invoice.number"), value: String(entry.element))
                }
            } else if let failure {
                Text(slText(failure))
                    .accessibilityIdentifier("sales.post.unavailable")
            } else {
                Button(slText("sales.post.title"), role: .destructive) { confirm = true }
                    .accessibilityIdentifier("sales.post.start")
            }
        }
        .navigationTitle(slText("sales.post.title"))
        .alert(slText("sales.post.confirm"), isPresented: $confirm) {
            Button(slText("sales.post.title"), role: .destructive, action: post)
                .accessibilityIdentifier("sales.post.confirm")
            Button(slText("sales.action.cancel"), role: .cancel) {}
        }
        .onAppear {
            guard result == nil else { return }
            do {
                try SalesPosting(workspace.context).checkAvailability()
            } catch {
                setFailure(error)
                if case SalesPosting.Error.missingWorkFile = error {
                    workspace.completed("sales-posting-work-file-unavailable")
                }
            }
        }
        .toolbar {
            if let document {
                ToolbarItem(placement: .primaryAction) {
                    SalesReportExport(report: document, identifier: "sales.post.export", filename: slText("sales.post.filename"))
                }
            }
        }
    }

    private func post() {
        do {
            result = try SalesPosting(workspace.context).post()
            document = workspace.context.store.readRaw(SalesPosting.exportPath).map(SalesReportDocument.init)
            workspace.completed("sales-posting")
        } catch {
            setFailure(error)
        }
    }

    private func setFailure(_ error: Error) {
        switch error {
        case SalesPosting.Error.missingWorkFile: failure = "sales.post.workMissing"
        case SalesPosting.Error.missingAnalysis: failure = "sales.post.analysisMissing"
        case SalesPosting.Error.invalidAnalysisLayout: failure = "sales.post.analysisFormat"
        default: failure = "sales.post.failed"
        }
    }
}
