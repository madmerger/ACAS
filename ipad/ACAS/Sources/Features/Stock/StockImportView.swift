import ACASCore
import SwiftUI
import UniformTypeIdentifiers

struct StockImportView: View {
    let workspace: Workspace
    @State private var source = ""
    @State private var choosingFile = false
    @State private var confirming = false
    @State private var message = ""

    var body: some View {
        Form {
            Text(stockText("import.columns"))
            TextEditor(text: $source)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 100)
                .accessibilityLabel(stockText("import.contents"))
                .accessibilityIdentifier("stock.importContents")
            Button(stockText("import.choose")) { choosingFile = true }
            Button(stockText("import.run")) { confirming = true }
                .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("stock.runImport")
            if !message.isEmpty { Text(message).accessibilityIdentifier("stock.importResult") }
        }
        .navigationTitle(stockText("import.title"))
        .onAppear { workspace.completed("stock.import.open") }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            do {
                let file = try result.get()
                let access = file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                let limit = 8 * 1024 * 1024
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: limit + 1) ?? Data()
                guard data.count <= limit else {
                    source = ""
                    message = stockText("error.importSize")
                    return
                }
                if data.count.isMultiple(of: 512), !data.contains(10), !data.contains(13) {
                    let bytes = Array(data)
                    source = stride(from: 0, to: bytes.count, by: 512)
                        .map { SJIS.decode(bytes[$0..<$0 + 512]) }.joined(separator: "\n")
                } else {
                    source = String(data: data, encoding: .utf8) ?? SJIS.decode(Array(data)[...])
                }
                message = ""
            } catch { message = stockError(error) }
        }
        .confirmationDialog(stockText("import.confirmation"), isPresented: $confirming, titleVisibility: .visible) {
            Button(stockText("import.run")) {
                do {
                    let count = try StockService(workspace.context).importItems(source)
                    message = String(format: stockText("import.result"), count)
                    workspace.completed("stock.import")
                } catch { message = stockError(error) }
            }
            .accessibilityIdentifier("stock.confirmImport")
        }
    }
}
