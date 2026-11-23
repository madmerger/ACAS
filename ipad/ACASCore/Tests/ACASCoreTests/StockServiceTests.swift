import Foundation
import XCTest
@testable import ACASCore

final class StockServiceTests: XCTestCase {
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
