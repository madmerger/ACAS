import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class StockServiceTests: XCTestCase {
    func testItemEditRejectsWrongAnalysisRecordLengthWithoutUpdatingStock() throws {
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store))
        let analysis = "ledgers/acas/analysis.dat"
        let key = Array("Pa1".utf8)
        XCTAssertTrue(store.write(analysis, key: key, data: key + Array(repeating: 0x20, count: 63)))
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "元の品目"
        try service.save(item)
        let before = store.all("ledgers/acas/stockctl.dat").map(\.data)
        item.name = "変更後の品目"
        XCTAssertThrowsError(try service.save(item, editing: item.code)) {
            XCTAssertEqual($0 as? StockService.Failure, .invalidAnalysisRecordLength)
        }
        XCTAssertEqual(store.all("ledgers/acas/stockctl.dat").map(\.data), before)
        XCTAssertTrue(store.rewrite(analysis, key: key, data: key + Array(repeating: 0x20, count: 33)))
        try service.save(item, editing: item.code)
        XCTAssertEqual(try service.find(item.code).name, item.name)
    }

    func testAuditReportEnablesPeriodClosingAndIncludesMovements() throws {
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store))
        var settings = Record(SystemLayout.layout)
        settings.setInt("stk-audit-used", 1)
        try service.settings.write(1, settings.bytes)
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "品目"
        try service.save(item)
        _ = try service.move(.receipt, code: "ITEM", quantity: 2, price: 123, date: service.today)
        XCTAssertThrowsError(try service.closePeriod(current: true, yearly: false))
        let result = try service.generateAuditReport(date: service.today)
        XCTAssertEqual(result.additions, 1)
        XCTAssertEqual(result.deductions, 0)
        let additions = try XCTUnwrap(store.readRaw("ledgers/acas/audit-additions.prt"))
        XCTAssertTrue(String(decoding: additions, as: UTF8.self).contains("ITEM001"))
        XCTAssertEqual(store.readRaw("ledgers/acas/prt-1"), store.readRaw("ledgers/acas/audit-deductions.prt"))
        try service.closePeriod(current: true, yearly: false)
        XCTAssertEqual(try service.find("ITEM001").added, 0)
    }

    func testEmptyAuditReportMatchesLegacyBytes() throws {
        guard let path = ProcessInfo.processInfo.environment["ACAS_LEGACY_EVIDENCE"] else {
            throw XCTSkip("ACAS_LEGACY_EVIDENCE にレガシー証跡の展開先を指定してください。")
        }
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-23T04:12:00Z"))
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store, timeZone: .gmt))
        var system = Record(SystemLayout.layout)
        system["usera"] = "EQUIVALENCE BUSINESS"
        system.setInt("stk-audit-used", 1)
        try service.settings.write(1, system.bytes)
        _ = try service.generateAuditReport(date: date)
        let run = URL(fileURLWithPath: path).appending(path: "runs/ST-214-breadth/files")
        for (output, evidence) in [
            ("audit-additions.prt", "spool/1795407133946126964/prt-1"),
            ("audit-deductions.prt", "ledgers/acas/prt-1"),
        ] {
            XCTAssertEqual(store.readRaw("ledgers/acas/" + output).map(Data.init(_:)),
                           try Data(contentsOf: run.appending(path: evidence)))
        }
    }

    func testPostingReportFailureRollsBackStockAndAudit() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try FileStore(path: path)
        let service = StockService(BusinessContext(store: store))
        var settings = Record(SystemLayout.layout)
        settings.setInt("stk-audit-used", 1)
        try service.settings.write(1, settings.bytes)
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "品目"
        try service.save(item)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = "CREATE TRIGGER reject_report BEFORE UPDATE ON files WHEN NEW.name LIKE '%/prt-1' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let insert = "CREATE TRIGGER reject_new_report BEFORE INSERT ON files WHEN NEW.name LIKE '%/prt-1' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, insert, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try service.move(.receipt, code: "ITEM001", quantity: 2, date: service.today))
        XCTAssertEqual(try service.find("ITEM001").held, 0)
        XCTAssertNil(store.readRaw("ledgers/acas/staudit.dat"))
        XCTAssertNil(store.readRaw("ledgers/acas/prt-1"))
    }

    func testOpeningMovementClearsTheReportAndPreservesExistingAudit() throws {
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store))
        var settings = Record(SystemLayout.layout)
        settings.setInt("stk-audit-used", 1)
        try service.settings.write(1, settings.bytes)
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "品目"
        try service.save(item)
        let original = EvidenceComparison.snapshot(store)
        try store.writeRaw("ledgers/acas/prt-1", [0x20])

        try service.prepareMovementEntry()

        XCTAssertEqual(store.readRaw("ledgers/acas/prt-1"), [])
        XCTAssertEqual(store.readRaw("ledgers/acas/staudit.dat"), [])
        try store.writeRaw("ledgers/acas/staudit.dat", [0x20])
        try service.prepareMovementEntry()
        XCTAssertEqual(store.readRaw("ledgers/acas/staudit.dat"), [0x20])
        XCTAssertEqual(EvidenceComparison.snapshot(store), original)
    }

    func testOrderPreservesAuditWrittenByMovement() throws {
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store))
        var settings = Record(SystemLayout.layout)
        settings.setInt("stk-audit-used", 1)
        try service.settings.write(1, settings.bytes)
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "品目"
        try service.save(item)
        _ = try service.move(.receipt, code: item.code, quantity: 2, date: service.today)
        let audit = try XCTUnwrap(store.readRaw("ledgers/acas/staudit.dat"))
        XCTAssertFalse(audit.isEmpty)
        try service.confirmOrder(item.code, quantity: 1, backOrdered: 0, ordered: nil, due: nil, date: service.today)
        XCTAssertEqual(store.readRaw("ledgers/acas/staudit.dat"), audit)
    }

    func testMissingMovementItemPreservesCurrentReportWithoutChangingStock() throws {
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store))
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "品目"
        try service.save(item)
        let original = EvidenceComparison.snapshot(store)
        for direction in [StockService.Direction.receipt, .issue] {
            try service.prepareMovementEntry()
            let reportPath = "ledgers/acas/prt-1"
            XCTAssertEqual(store.readRaw(reportPath), [])
            try store.writeRaw(reportPath, [0x20])
            XCTAssertThrowsError(try service.move(direction, code: "MISSING", quantity: 1, date: service.today)) {
                guard case StockService.Failure.missing = $0 else { return XCTFail("\($0)") }
            }
            XCTAssertEqual(store.readRaw(reportPath), [0x20])
            XCTAssertEqual(EvidenceComparison.snapshot(store), original)
        }
    }

    func testStockReportStopsAtFullEndCode() throws {
        let service = StockService(BusinessContext(store: try FileStore()))
        var item = StockService.Item()
        item.name = "Included item"
        item.code = "A100"
        item.abbreviation = item.code
        try service.save(item)
        item.name = "Excluded item"
        item.code = "A1001"
        item.abbreviation = item.code
        try service.save(item)
        let report = try service.printReport(.listing, date: service.today, through: "A100")
        XCTAssertNotNil(report.range(of: Data("Included item".utf8)))
        XCTAssertNil(report.range(of: Data("Excluded item".utf8)))
    }

    func testStockImportAcceptsQuotedLegacyDates() throws {
        let store = try FileStore()
        let service = StockService(BusinessContext(store: store))
        XCTAssertEqual(try service.importItems(#"A100,Item,0,0,0,0,0,0,0,0,0,"01/10/2026","03/10/2026""#), 1)
        let row = try service.record("A100")
        XCTAssertEqual(row.int("stock-order-date"), Int64(Maps04.integerOfDate(year: 2026, month: 10, day: 1)))
        XCTAssertEqual(row.int("stock-order-due"), Int64(Maps04.integerOfDate(year: 2026, month: 10, day: 3)))
    }

    func testManualMovementPrefersAbbreviationAndBarcodeUsesPrimaryCode() throws {
        let service = StockService(BusinessContext(store: try FileStore()))
        var item = StockService.Item()
        item.code = "ITEM001"
        item.abbreviation = "ITEM"
        item.name = "品目"
        try service.save(item)
        item.code = "ITEM"
        item.abbreviation = "OTHER"
        try service.save(item)
        let updated = try service.move(.receipt, code: "ITEM", quantity: 2, date: service.today)
        XCTAssertEqual(updated.code, "ITEM001")
        let scanned = try service.move(.receipt, code: "ITEM", quantity: 1, date: service.today, codeOnly: true)
        XCTAssertEqual(scanned.code, "ITEM")
        XCTAssertEqual(try service.find("ITEM001").held, 2)
        XCTAssertThrowsError(try service.move(.receipt, code: "OTHER", quantity: 1, date: service.today, codeOnly: true))
    }

    func testItemValidationAndPreservesEnteredValuation() throws {
        let service = StockService(BusinessContext(store: try FileStore()))
        var item = StockService.Item()
        item.code = "item001"
        item.abbreviation = "item"
        item.name = "品目"
        item.held = 1
        item.value = 500
        try service.save(item)
        XCTAssertEqual(try service.find("ITEM001").code, "ITEM001")
        item.abbreviation = "OTHER"
        XCTAssertThrowsError(try service.save(item))
        item.held = 2
        try service.save(item, editing: "item001")
        XCTAssertEqual(try service.find("ITEM001").value, 500)
        XCTAssertThrowsError(try service.remove("ITEM001"))
        XCTAssertThrowsError(try service.order("OTHER", quantity: -1, backOrdered: 0, ordered: nil, due: nil))
        item.held = 0
        try service.save(item, editing: "ITEM001")
        try service.order("other", quantity: 0, backOrdered: 1, ordered: nil, due: nil)
        XCTAssertThrowsError(try service.remove("ITEM001"))
        try service.order("other", quantity: 0, backOrdered: 0, ordered: nil, due: nil)
        try service.remove("ITEM001")
        XCTAssertTrue(service.items.isEmpty)
    }

    func testReceiptUsesCalendarMonthIndependentlyOfDisplayFormat() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-24T12:00:00Z"))
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for format in [1, 2, 3] as [Int64] {
            let service = StockService(BusinessContext(store: try FileStore(), timeZone: timeZone, now: { date }))
            var settings = Record(SystemLayout.layout)
            settings.setInt("date-form", format)
            try service.settings.write(1, settings.bytes)
            var item = StockService.Item()
            item.code = "ITEM001"
            item.abbreviation = "ITEM"
            item.name = "品目"
            try service.save(item)
            _ = try service.move(.receipt, code: "item", quantity: 2, date: date)
            let stored = try service.record("ITEM001")
            XCTAssertEqual(stored.int("stock-td-adds-3"), 2)
            XCTAssertEqual(stored.int("stock-td-adds-2"), 0)
        }
    }
}
