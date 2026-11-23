import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class BookkeepingPostingTests: XCTestCase {
    func testPasswordRequiredForConfigurationAndRecalculation() throws {
        let service = BookkeepingService(BusinessContext(store: try FileStore()))
        var system = service.system
        system["pass-word"] = "1234"
        try service.writeLine(service.systemPath, system.bytes)
        var configuration = service.configuration
        configuration.client = "会社"
        XCTAssertThrowsError(try service.save(configuration, password: "0000"))
        XCTAssertThrowsError(try service.recalculate(password: "0000")) {
            guard case BookkeepingService.Failure.wrongPassword = $0 else { return XCTFail("\($0)") }
        }
        try service.save(configuration, password: "1234")
        XCTAssertEqual(service.configuration.client, "会社")
    }

    func testPostingRollsBackIfSequenceCannotBeSaved() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try FileStore(path: path)
        let service = BookkeepingService(BusinessContext(store: store))
        try service.saveAccount(code: 10001, name: "既定", category: .assets, editing: false)
        try service.saveAccount(code: 20001, name: "相手", category: .expense, editing: false)
        try service.saveDefault(slot: 1, account: 10001, label: "BK", usesTax: false)
        try service.writeLine(service.systemPath, service.system.bytes)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = "CREATE TRIGGER reject_sequence BEFORE UPDATE ON files WHEN NEW.name LIKE '%/system.dat' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try service.post(defaultSlot: 1, side: .debit, account: 20001, date: service.today,
                                              amount: 100, description: "転記"))
        XCTAssertTrue(service.postings.isEmpty)
        XCTAssertEqual(try service.accountRecord(10001).int("dr"), 0)
        XCTAssertEqual(try service.accountRecord(20001).int("cr"), 0)
    }

    func testDefaultBalanceCarriesForwardAndRecalculationResolvesSubaccount() throws {
        let store = try FileStore()
        let service = BookkeepingService(BusinessContext(store: store))
        try service.saveAccount(code: 10001, name: "既定", category: .assets, editing: false)
        try service.saveAccount(code: 20001, name: "親", category: .expense, editing: false)
        try service.saveAccount(code: 20001, child: 20002, name: "補助", category: .expense, editing: false)
        try service.saveDefault(slot: 1, account: 10001, label: "BK", usesTax: false)
        for amount: Int64 in [100, 200] {
            try service.post(defaultSlot: 1, side: .debit, account: 20002, date: service.today,
                             amount: amount, description: "転記")
        }
        XCTAssertEqual(try service.accountRecord(10001).int("dr"), 300)
        XCTAssertEqual(try service.accountRecord(20001, 20002).int("cr"), 300)
        try service.recalculate(password: "")
        XCTAssertEqual(try service.accountRecord(20001, 20002).int("cr"), 300)
        XCTAssertEqual(try service.accountRecord(20002).int("cr"), 0)
    }
}
