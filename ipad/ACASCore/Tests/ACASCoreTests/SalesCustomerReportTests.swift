import XCTest
@testable import ACASCore

final class SalesCustomerReportTests: XCTestCase {
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
