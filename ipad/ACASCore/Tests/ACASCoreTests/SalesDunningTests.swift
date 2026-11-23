import XCTest
@testable import ACASCore

final class SalesDunningTests: XCTestCase {
    func testMissingRegistrationMarksSortDirtyUnlessLegacySkipsSorting() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let files = SalesInvoices(context)
        let service = SalesDunning(context)
        let letter = SalesDunning.letterPaths[0]
        try store.writeRaw(letter, [0x61])
        try store.writeRaw(SalesOpenItemSort.path, [0x62])
        for (initial, expected) in [(" ", "Y"), ("N", "N")] {
            var system = Record(SystemLayout.layout)
            system["oi-3-flag"] = initial
            try files.systemFile.write(1, system.bytes)

            XCTAssertThrowsError(try service.prepare()) {
                XCTAssertEqual($0 as? SalesDunning.Error, .missingOpenItems)
            }
            system["oi-3-flag"] = expected
            XCTAssertEqual(try files.settings().bytes, system.bytes)
            XCTAssertEqual(store.readRaw(letter), [0x61])
            XCTAssertEqual(store.readRaw(SalesOpenItemSort.path), [0x62])
        }
    }

    func testPreparesSortedOpenItemsButRejectsEvenAValidDate() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let files = SalesInvoices(context)
        let service = SalesDunning(context)
        var system = Record(SystemLayout.layout)
        var flags = Array(repeating: UInt8(0x30), count: 32)
        flags[18] = 0x31
        system.setRaw("file-statuses", flags)
        let day = Maps04.integerOfDate(year: 2026, month: 11, day: 23)
        system.setInt("run-date", Int64(day))
        try files.systemFile.write(1, system.bytes)
        try store.writeRaw(SalesDunning.letterPaths[0], [0x61])

        XCTAssertThrowsError(try service.prepare()) {
            XCTAssertEqual($0 as? SalesDunning.Error, .missingOpenItems)
        }
        XCTAssertEqual(store.readRaw(SalesDunning.letterPaths[0]), [0x61])
        let items = SalesOpenItems.file(store)
        var early = Record(SalesOpenItems.layout)
        early["customer"] = "CUST011"
        early.setInt("invoice", 2)
        early.setInt("date", Int64(day) - 15)
        var late = early
        late.setInt("invoice", 1)
        late.setInt("date", Int64(day) - 5)
        XCTAssertEqual(items.write(late), "00")
        XCTAssertEqual(items.write(early), "00")

        let date = try service.prepare()
        XCTAssertEqual(context.calendar.component(.day, from: date), 23)
        XCTAssertEqual(store.readRaw(SalesOpenItemSort.path), early.bytes + late.bytes)
        XCTAssertEqual(try files.settings().str("oi-3-flag"), "N")
        XCTAssertEqual(try files.settings().int("date-form"), 1)
        for path in SalesDunning.letterPaths { XCTAssertEqual(store.readRaw(path), []) }
        let before = store.snapshot()
        XCTAssertThrowsError(try service.confirmDate(date)) {
            XCTAssertEqual($0 as? SalesDunning.Error, .dateNotAccepted)
        }
        XCTAssertEqual(store.snapshot(), before)
    }
}
