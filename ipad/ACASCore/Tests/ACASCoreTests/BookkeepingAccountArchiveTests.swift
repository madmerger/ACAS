import Foundation
import XCTest
@testable import ACASCore

final class BookkeepingAccountArchiveTests: XCTestCase {
    func testArchiveFileReadsOnlyWithinSizeLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = Data("T1000200000O現金".utf8)
        try contents.write(to: url)
        XCTAssertEqual(try BookkeepingService.readAccountArchive(at: url), contents)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(BookkeepingService.accountArchiveSizeLimit + 1))
        XCTAssertThrowsError(try BookkeepingService.readAccountArchive(at: url)) {
            guard case BookkeepingService.Failure.accountArchiveTooLarge = $0 else { return XCTFail("\($0)") }
        }
    }

    func testArchiveRejectsInvalidEncodingWithoutReplacingTheLedger() throws {
        let service = BookkeepingService(BusinessContext(store: try FileStore()))
        try service.saveAccount(code: 10001, name: "旧科目", category: .assets, editing: false)
        let original = EvidenceComparison.snapshot(service.store)
        func archive(_ name: [UInt8]) -> Data {
            Data(Array("T1000200000O".utf8) + name + Array(repeating: 0x20, count: 24 - name.count) + [0x52, 0x0a])
        }
        for invalid in [Array("é".utf8), [0x82, 0x20]] {
            XCTAssertThrowsError(try service.importAccountArchive(archive(invalid)))
            XCTAssertEqual(EvidenceComparison.snapshot(service.store), original)
        }
        XCTAssertEqual(try service.importAccountArchive(archive(SJIS.encode("現金", size: 24))), 1)
        XCTAssertEqual(service.accounts.map(\.name), ["現金"])
    }
}
