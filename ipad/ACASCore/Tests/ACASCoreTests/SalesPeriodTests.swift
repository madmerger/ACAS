import XCTest
@testable import ACASCore

final class SalesPeriodTests: XCTestCase {
    func testDayBookAndCloseRollForwardSalesRecords() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let files = SalesInvoices(context)
        var system = Record(SystemLayout.layout)
        var flags = Array(repeating: UInt8(0x30), count: 32)
        flags[14] = 0x31
        flags[18] = 0x31
        system.setRaw("file-statuses", flags)
        system.setInt("period", 3)
        system.setInt("scycle", 3)
        system.setInt("current-quarter", 1)
        system.setInt("page-lines", 60)
        system.setInt("run-date", Int64(Maps04.integerOfDate(year: 2026, month: 3, day: 31)))
        system.setInt("s-flag-p", 1)
        try files.systemFile.write(1, system.bytes)
        let service = SalesPeriodClose(context)
        XCTAssertThrowsError(try service.options()) { XCTAssertEqual($0 as? SalesPeriodClose.Error, .pendingPayments) }
        system.setInt("s-flag-p", 0)
        try files.systemFile.write(1, system.bytes)
        var customer = Record(SalesProofRecords.salesLayout)
        customer["sales-key"] = "CUST011"
        customer.setInt("sales-current", 1_100)
        customer.setInt("turnover-q2", 900)
        let customers = SalesProofRecords.salesFile(store)
        XCTAssertEqual(customers.write(customer), "00")
        var item = Record(SalesOpenItems.layout)
        item["customer"] = "CUST011"
        item.setInt("invoice", 10)
        item.setInt("type", 2)
        item.setInt("paid-current", 500)
        let items = SalesOpenItems.file(store)
        XCTAssertEqual(items.write(item), "00")
        var header = Record(SalesProofRecords.ihLayout)
        header["ih-customer"] = "CUST011"
        header["ih-status"] = "Z"
        header["ih-update"] = "Z"
        header.setInt("ih-type", 2)
        header.setInt("ih-invoice", 10)
        header.setInt("ih-net", 1_000)
        header.setInt("ih-vat", 100)
        header.setInt("ih-lines", 1)
        XCTAssertEqual(files.file.write(header), "00")
        let number = SalesInvoices.Number(value: 10)
        let lineKey = files.key(number, line: 1)
        XCTAssertTrue(store.write(files.file.path, key: lineKey, data: lineKey + Array(repeating: 0x20, count: 124)))

        let entries = try XCTUnwrap(SalesDayBook(context).generate())
        XCTAssertEqual(entries.map(\.gross), [1100])
        XCTAssertEqual(files.header(number)?.str("ih-day-book-flag"), " ")
        let report = try XCTUnwrap(store.readRaw(SalesDayBook.exportPath))
        XCTAssertEqual(String(decoding: report[62..<70], as: UTF8.self), "Day Book")
        let rows = report.split(separator: 0x0a, omittingEmptySubsequences: false)
        let heading = try XCTUnwrap(rows.firstIndex { String(decoding: $0, as: UTF8.self).contains("Prompt Pay") })
        let totals = ["Receipts", "Invoices", "Credit Notes", "    Totals"]
        for (index, title) in totals.enumerated() {
            let row = try XCTUnwrap(rows.firstIndex { $0.starts(with: title.utf8) })
            XCTAssertEqual(row, heading + 3 + 2 * index)
            XCTAssertEqual(rows[row].count, 132)
        }
        XCTAssertFalse(try service.options().manualQuarter)

        let before = store.snapshot()
        XCTAssertThrowsError(try service.close(password: "AB", acceptingPendingInvoices: false, endQuarter: false)) {
            XCTAssertEqual($0 as? SalesPeriodClose.Error, .invalidPassword)
        }
        XCTAssertEqual(store.snapshot(), before)
        try service.close(password: "", acceptingPendingInvoices: false, endQuarter: false)
        XCTAssertEqual(try files.settings().int("scycle"), 4)
        XCTAssertEqual(try files.settings().int("current-quarter"), 2)
        XCTAssertEqual(customers.read(key: "CUST011")?.int("sales-last"), 1_100)
        XCTAssertEqual(customers.read(key: "CUST011")?.int("turnover-q2"), 0)
        XCTAssertEqual(items.allRecords().first?.str("applied"), "z")
        XCTAssertEqual(items.allRecords().first?.int("paid-current"), 0)
        XCTAssertNil(store.read(files.file.path, key: lineKey))
        let compacted = try XCTUnwrap(store.read(files.file.path, key: files.key(number)))
        XCTAssertEqual(compacted.count, 134)
        XCTAssertEqual(Array(compacted.suffix(5)), [0x20, 0x20, 0x20, 0x20, 0x20])
        XCTAssertEqual(files.header(number)?.int("ih-lines"), 0)
        XCTAssertEqual(files.header(number)?.str("ih-update"), " ")
    }
}
