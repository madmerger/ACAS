import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class PeriodClosingTests: XCTestCase {
    func testBalanceWriteFailureDoesNotAdvancePeriod() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try FileStore(path: path)
        let settings = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var system = Record(SystemLayout.layout)
        var status = system.raw("file-statuses")
        status[14] = 0x31
        status[28] = 0x31
        system.setRaw("file-statuses", status)
        system.setInt("level-2", 1)
        system.setInt("scycle", 1)
        try settings.write(1, system.bytes)
        let service = PeriodClosing(BusinessContext(store: store))
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = "CREATE TRIGGER reject_balances BEFORE UPDATE ON files WHEN NEW.name LIKE '%/system.dat' AND length(NEW.data) > 1032 BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let date = Date(timeIntervalSince1970: 1_795_408_126)
        XCTAssertThrowsError(try service.close([.purchases], date: date, password: "", proceedWithUnposted: false,
                                               endOfQuarter: false))
        XCTAssertEqual(settings.read(1), system.bytes)
        XCTAssertFalse(store.exists("ledgers/acas/oisort.wrk"))
        XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_balances", nil, nil, nil), SQLITE_OK)
        try service.close([.purchases], date: date, password: "", proceedWithUnposted: false, endOfQuarter: false)
        let updated = Record(SystemLayout.layout, bytes: try XCTUnwrap(settings.read(1)))
        XCTAssertEqual(updated.int("scycle"), 2)
    }
}
