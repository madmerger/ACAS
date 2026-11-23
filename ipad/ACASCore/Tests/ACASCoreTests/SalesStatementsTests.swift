import XCTest
@testable import ACASCore

final class SalesStatementsTests: XCTestCase {
    func testStatementWritesInvoiceAndAgeingAndClearsSortFile() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let files = SalesInvoices(context)
        var system = Record(SystemLayout.layout)
        var flags = Array(repeating: UInt8(0x30), count: 32)
        flags[18] = 0x31
        system.setRaw("file-statuses", flags)
        system["usera"] = "ACAS"
        let day = Maps04.integerOfDate(year: 2026, month: 11, day: 23)
        system.setInt("run-date", Int64(day))
        try files.systemFile.write(1, system.bytes)
        let service = SalesStatements(context)
        XCTAssertThrowsError(try service.prepare()) {
            XCTAssertEqual($0 as? SalesStatements.Error, .missingOpenItems)
        }
        var customer = Record(SalesProofRecords.salesLayout)
        customer["sales-key"] = "CUST011"
        customer["sales-name"] = "Test Account"
        customer.setInt("sales-current", 975)
        XCTAssertEqual(SalesProofRecords.salesFile(store).write(customer), "00")
        var item = Record(SalesOpenItems.layout)
        item["customer"] = "CUST011"
        item.setInt("type", 2)
        item.setInt("invoice", 8)
        item.setInt("date", Int64(day - 30))
        item.setInt("net", 1_000)
        item.setInt("paid", 25)
        item.setInt("paid-current", 25)
        XCTAssertEqual(SalesOpenItems.file(store).write(item), "00")

        let date = try service.prepare()
        XCTAssertEqual(store.readRaw(SalesOpenItemSort.path), item.bytes)
        let entries = try service.generate(date: date, customer: "cust011", minimum: 900, message1: "Test", message2: "")
        XCTAssertEqual(entries.map(\.balance), [975])
        let report = try XCTUnwrap(store.readRaw(SalesStatements.exportPath))
        let text = String(decoding: report, as: UTF8.self)
        XCTAssertTrue(text.contains("Goods"))
        XCTAssertTrue(text.contains("Test Account"))
        XCTAssertTrue(text.contains("10.00"))
        XCTAssertTrue(text.contains("9.75"))
        XCTAssertTrue(report.split(separator: 0x0a).allSatisfy { $0.count == 132 })
        XCTAssertEqual(store.readRaw(SalesOpenItemSort.path), [])
    }
}
