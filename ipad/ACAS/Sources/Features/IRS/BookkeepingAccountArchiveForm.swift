import ACASCore
import SwiftUI
import UniformTypeIdentifiers

struct BookkeepingAccountArchiveForm: View {
    let workspace: Workspace
    let importing: Bool
    @State private var source = ""
    @State private var fileContents: Data?
    @State private var document: BookkeepingReportDocument?
    @State private var picking = false
    @State private var exporting = false
    @State private var confirming = false
    @State private var message = ""

    private var title: String { irsText(importing ? "accounts.import" : "accounts.export") }

    var body: some View {
        Form {
            if importing {
                Button(irsText("archive.choose")) { picking = true }
                if fileContents == nil {
                    TextEditor(text: $source)
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .accessibilityLabel(irsText("archive.contents"))
                        .accessibilityIdentifier("irs.archiveContents")
                }
            }
            Button(title) {
                if importing { confirming = true } else { export() }
            }
            .disabled(importing && fileContents == nil && source.isEmpty)
            .accessibilityIdentifier("irs.runArchive")
            if document != nil {
                Button(irsText("archive.saveFile")) { exporting = true }
                    .accessibilityIdentifier("irs.saveArchive")
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("irs.archiveResult") }
        }
        .navigationTitle(title)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.plainText, .data]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                fileContents = try Data(contentsOf: url)
                message = irsText("archive.fileReady")
            } catch { message = bookkeepingError(error) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .data,
                      defaultFilename: BookkeepingService.accountArchiveName) {
            if case .failure = $0 { message = irsText("error.exportReport") }
        }
        .confirmationDialog(irsText("archive.replaceWarning"), isPresented: $confirming, titleVisibility: .visible) {
            Button(title, role: .destructive, action: importArchive)
                .accessibilityIdentifier("irs.confirmArchiveImport")
        }
    }

    private func export() {
        do {
            let archive = try BookkeepingService(workspace.context).exportAccountArchive()
            document = BookkeepingReportDocument(data: archive.data)
            message = String(format: irsText("archive.exported"), archive.count)
            workspace.completed("irs.accountExport")
        } catch { message = bookkeepingError(error) }
    }

    private func importArchive() {
        do {
            let data: Data
            if let fileContents {
                data = fileContents
            } else if let encoded = source.data(using: .shiftJIS) {
                data = encoded
            } else {
                message = irsText("archive.invalid")
                return
            }
            let count = try BookkeepingService(workspace.context).importAccountArchive(data)
            message = String(format: irsText("archive.imported"), count)
            workspace.completed("irs.accountImport")
        } catch { message = bookkeepingError(error) }
    }
}
