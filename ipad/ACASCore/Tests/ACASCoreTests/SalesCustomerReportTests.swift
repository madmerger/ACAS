import XCTest
@testable import ACASCore

final class SalesCustomerReportTests: XCTestCase {
    func testAlphabeticalAndTurnoverUseDistinctOrderAndReportHeaders() throws {
        let store = try FileStore()
        let service = SalesCustomerReport(BusinessContext(store: store))
        var system = Record(SystemLayout.layout)
        system.setInt("page-lines", 60)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        for (code, name) in [("CUST011", "ZULU"), ("CUST022", "ALPHA")] {
            var row = Record(SalesProofRecords.salesLayout)
            row["sales-key"] = code
            row["sales-name"] = name
            row["sales-phone"] = "0123456789"
            row["sales-ext"] = "123"
            row.setInt("turnover-q1", 123_456)
            XCTAssertEqual(SalesProofRecords.salesFile(store).write(row), "00")
        }
        let filter = SalesCustomerReport.Filter()
        XCTAssertEqual(try service.generate(filter, kind: .alphabetical).map(\.code), ["CUST022", "CUST011"])
        let alpha = try XCTUnwrap(store.readRaw(SalesCustomerReport.exportPath))
        XCTAssertEqual(String(decoding: alpha[51..<80], as: UTF8.self), "Customer Alphabetical Listing")
        XCTAssertEqual(store.readRaw("custsort.tmp"), [])
        let alphaRow = try XCTUnwrap(alpha.split(separator: 0x0a).first { $0.starts(with: "CUST011".utf8) })
        XCTAssertEqual(String(decoding: alphaRow.dropFirst(70).prefix(18), as: UTF8.self), "0123456789 x123   ")
        try service.prepareTurnover()
        XCTAssertEqual(store.readRaw(SalesCustomerReport.exportPath), [])
        XCTAssertEqual(try service.generate(filter, kind: .turnover).map(\.code), ["CUST011", "CUST022"])
        let turnover = try XCTUnwrap(store.readRaw(SalesCustomerReport.exportPath))
        XCTAssertEqual(String(decoding: turnover[51..<79], as: UTF8.self), "Sales Ledger Turnover Report")
        let row = try XCTUnwrap(turnover.split(separator: 0x0a).first { $0.starts(with: "CUST011".utf8) })
        XCTAssertEqual(String(decoding: row.dropFirst(64).prefix(8), as: UTF8.self), "    1234")
    }

    func testUnappliedSalesReportUsesProcessingDateInHeading() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        var system = Record(SystemLayout.layout)
        system.setInt("run-date", Int64(Maps04.integerOfDate(year: 2024, month: 9, day: 18)))
        var statuses = system.raw("file-statuses")
        statuses[15] = 0x31
        system.setRaw("file-statuses", statuses)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        store.createIndexed("ledgers/acas/invoice.dat")

        _ = try SalesProofReport.generate(in: context)
        let report = try XCTUnwrap(store.readRaw(SalesProofReport.exportPath))
        XCTAssertTrue(String(decoding: report, as: UTF8.self).contains("18/09/2024"))
    }

    func testUnconfiguredPageLengthUsesLegacyDefault() throws {
        let store = try FileStore()
        let service = SalesCustomerReport(BusinessContext(store: store))
        let system = Record(SystemLayout.layout)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        for index in 10..<20 {
            var customer = Record(SalesProofRecords.salesLayout)
            customer["sales-key"] = "CUST0\(index)"
            XCTAssertEqual(SalesProofRecords.salesFile(store).write(customer), "00")
        }

        XCTAssertEqual(try service.generate(.init()).count, 10)
        XCTAssertFalse(try XCTUnwrap(store.readRaw(SalesCustomerReport.exportPath)).contains(0x0c))
    }

    func testDefaultPageBreakStartsImmediatelyBeforeFourteenthCustomer() throws {
        let store = try FileStore()
        let system = Record(SystemLayout.layout)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        for index in 10..<24 {
            var customer = Record(SalesProofRecords.salesLayout)
            customer["sales-key"] = "CUST0\(index)"
            XCTAssertEqual(SalesProofRecords.salesFile(store).write(customer), "00")
        }

        let service = SalesCustomerReport(BusinessContext(store: store))
        XCTAssertEqual(try service.generate(.init()).count, 14)
        let pages = try XCTUnwrap(store.readRaw(SalesCustomerReport.exportPath)).split(separator: 0x0c)
        XCTAssertEqual(pages.count, 2)
        let rows = pages.map { page in
            page.split(separator: 0x0a).map { String(decoding: $0.prefix(7), as: UTF8.self) }
                .filter { $0.hasPrefix("CUST") }
        }
        XCTAssertEqual(rows, [(10..<23).map { "CUST0\($0)" }, ["CUST023"]])
    }

    func testFiltersAndPrintsInKeyOrderWithLegacyColumns() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let service = SalesCustomerReport(context)
        var system = Record(SystemLayout.layout)
        system["usera"] = "TEST COMPANY"
        system["sl-delim"] = "\\"
        let day = Int64(Maps04.integerOfDate(year: 2026, month: 11, day: 23))
        system.setInt("run-date", day)
        system.setInt("page-lines", 60)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)

        for (key, status, credit, balance): (String, Int64, Int64, Int64) in [
            ("CUST022", 1, 40, 500), ("CUST011", 1, 30, 0), ("CUST033", 0, 30, 0),
            ("CUST044", 1, 10, 500), ("OTHER01", 1, 30, 0),
        ] {
            var row = Record(SalesProofRecords.salesLayout)
            row["sales-key"] = key
            row["sales-name"] = "TEST " + key
            row["sales-addr1"] = "CITY\\COUNTRY"
            row.setInt("sales-status", status)
            row.setInt("sales-credit", credit)
            row.setInt("sales-current", balance)
            row.setInt("sales-last-inv", day - 40)
            row.setInt("sales-create-date", day)
            XCTAssertEqual(SalesProofRecords.salesFile(store).write(row), "00")
        }
        var filter = SalesCustomerReport.Filter()
        filter.code = "cust"
        filter.status = .active
        filter.creditDays = (.greater, 20)
        filter.overdueDays = (.greater, 30)
        filter.creationDate = (.equal, try XCTUnwrap(context.calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))))

        XCTAssertEqual(try service.generate(filter).map(\.code), ["CUST011", "CUST022"])
        let output = try XCTUnwrap(store.readRaw(SalesCustomerReport.exportPath))
        let lines = output.split(separator: 0x0a)
        XCTAssertTrue(lines.allSatisfy { $0.count == 132 })
        XCTAssertEqual(String(decoding: lines[0].dropFirst(57).prefix(16), as: UTF8.self), "Customer Listing")
        XCTAssertEqual(String(decoding: lines[1].suffix(10), as: UTF8.self), "23/11/2026")
        XCTAssertEqual(String(decoding: lines[5].prefix(27), as: UTF8.self), "CUST011   Active    TEST CU")
        XCTAssertEqual(String(decoding: lines[6].dropFirst(20).prefix(12), as: UTF8.self), "CITY,COUNTRY")
        XCTAssertEqual(String(decoding: lines[8].prefix(7), as: UTF8.self), "CUST022")
    }
}
