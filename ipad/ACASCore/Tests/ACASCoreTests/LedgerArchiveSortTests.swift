import XCTest
@testable import ACASCore

final class LedgerArchiveSortTests: XCTestCase {
    func testArchiveIsSortedWithoutModifyingOriginal() throws {
        let store = try FileStore()
        let sorter = LedgerArchiveSort(BusinessContext(store: store))
        let path = LedgerCycleClose.archivePath
        XCTAssertThrowsError(try sorter.prepare())
        XCTAssertNil(store.readRaw(LedgerArchiveSort.sortedPath))

        func row(_ account: Int64, _ branch: Int64, _ batch: Int64, _ sequence: Int64) -> [UInt8] {
            var record = Record(LedgerCycleClose.archiveLayout)
            record.setInt("account", account)
            record.setInt("branch", branch)
            record.setInt("batch", batch)
            record.setInt("sequence", sequence)
            return record.bytes + [10]
        }

        let ordered = [row(300001, 0, 1, 1), row(300001, 0, 1, 2), row(300001, 1, 1, 1), row(400001, 0, 1, 1)]
        let original = ordered.reversed().flatMap { $0 }
        try store.writeRaw(path, original)
        try sorter.prepare()
        XCTAssertEqual(store.readRaw(LedgerArchiveSort.sortedPath), ordered.flatMap { $0 })
        XCTAssertEqual(store.readRaw(path), original)
    }
}
