import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class BookkeepingPostingTests: XCTestCase {
    func testAnnualStatementUsesWorkFileOrderForDetailsAndClassificationForTotals() throws {
        let service = BookkeepingService(BusinessContext(store: try FileStore()))
        var settings = service.system
        settings["end-date"] = "31/12/26"
        try service.writeLine(service.systemPath, settings.bytes)
        try service.saveAccount(code: 10001, name: "Sales", category: .income, editing: false)
        try service.saveAccount(code: 10001, child: 10002, name: "Sub", category: .expense, editing: false)
        try service.saveAccount(code: 20001, name: "Expenses", category: .expense, editing: false)
        try service.saveAccount(code: 30001, name: "Liabilities", category: .liabilities, editing: false)
        var child = try service.accountRecord(10001, 10002)
        child.setInt("dr", 12_300)
        XCTAssertTrue(service.store.rewrite(service.accountsPath, key: child.raw("key"), data: child.bytes))
        try service.prepareStatementAccounts()
        let statement = try service.printAnnualStatement(title: "")
        let lines = String(decoding: statement.data, as: UTF8.self).components(separatedBy: "\n")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Sales ") && $0.filter { $0 != " " }.hasSuffix("(123)") })
        XCTAssertTrue(lines.contains { $0.contains("Less Total Direct Costs") && $0.hasSuffix("123") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("Expenses ") })
    }

    func testPasswordCanBeRegisteredAndChanged() throws {
        let service = BookkeepingService(BusinessContext(store: try FileStore()))
        var configuration = service.configuration
        configuration.client = "会社"
        try service.store.writeRaw(service.postPath, [])
        try service.save(configuration, password: "", newPassword: "1234")
        XCTAssertThrowsError(try service.recalculate(password: ""))
        XCTAssertThrowsError(try service.save(configuration, password: "", newPassword: "5678"))
        try service.save(configuration, password: "1234", newPassword: "5678")
        XCTAssertThrowsError(try service.recalculate(password: "1234")) {
            guard case BookkeepingService.Failure.wrongPassword = $0 else { return XCTFail("\($0)") }
        }
        try service.recalculate(password: "5678")
    }

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
        try service.saveDefault(slot: 1, account: 10001, label: "BK", tax: .none)
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
        try service.saveDefault(slot: 1, account: 10001, label: "BK", tax: .none)
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

    func testDefaultTaxCodesRoundTripInTheFixedLengthRecord() throws {
        let store = try FileStore()
        let service = BookkeepingService(BusinessContext(store: store))
        try service.saveAccount(code: 10001, name: "既定", category: .assets, editing: false)
        try service.saveDefault(slot: 1, account: 10001, label: "BK", tax: .input)
        try service.saveDefault(slot: 2, account: 10001, label: "BK", tax: .none)
        try service.saveDefault(slot: 3, account: 10001, label: "BK", tax: .output)
        try service.saveDefault(slot: 31, account: 10001, label: "", tax: .output)
        let saved = try XCTUnwrap(store.readRaw(service.defaultsPath))
        XCTAssertEqual(Array(saved[224..<227]), Array("INO".utf8))
        XCTAssertEqual(saved[254], UInt8(ascii: "N"))
        let reopened = BookkeepingService(BusinessContext(store: store))
        XCTAssertEqual(reopened.defaults.prefix(3).map(\.tax), [.input, .none, .output])
        XCTAssertEqual(reopened.defaults[30].tax, .none)
    }
}
