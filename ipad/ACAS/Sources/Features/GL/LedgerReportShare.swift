import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private struct LedgerReportFile: Transferable {
    let bytes: [UInt8]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { Data($0.bytes) }
            .suggestedFileName("prt-1")
    }
}

struct LedgerReportShare: View {
    let bytes: [UInt8]

    var body: some View {
        ShareLink(item: LedgerReportFile(bytes: bytes), preview: SharePreview(ledgerText("report.share"))) {
            Label(ledgerText("report.share"), systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("gl.report.share")
    }
}
