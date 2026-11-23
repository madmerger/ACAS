import XCTest
@testable import ACASCore

final class SalesPostingTests: XCTestCase {
    func testPrintedInvoicePostsOnceAndUnprintedInvoiceIsSkipped() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let invoices = SalesInvoices(context)
        var system = Record(SystemLayout.layout)
        system["file-statuses"] = String(repeating: "0", count: 14) + "1000"
        system.setInt("level-1", 1)
        system.setInt("next-batch", 4)
        system.setInt("sl-sales-ac", 1234)
        system.setInt("s-debtors", 4567)
        system.setInt("vat-ac", 7890)
        system.setInt("page-lines", 60)
        let date = Int64(Maps04.integerOfDate(year: 2026, month: 11, day: 23))
        system.setInt("run-date", date)
        try invoices.systemFile.write(1, system.bytes)
        let service = SalesPosting(context)
        let before = store.snapshot()
        XCTAssertThrowsError(try service.post()) { XCTAssertEqual($0 as? SalesPosting.Error, .missingWorkFile) }
        XCTAssertEqual(store.snapshot(), before)
        try store.writeRaw(SalesPosting.workPath, [])

        var customer = Record(SalesProofRecords.salesLayout)
        customer["sales-key"] = "CUST011"
        customer["sales-name"] = "得意先"
        let customers = SalesProofRecords.salesFile(store)
        XCTAssertEqual(customers.write(customer), "00")
        for number: Int64 in [10, 11] {
            var header = Record(SalesProofRecords.ihLayout)
            header["ih-customer"] = "CUST011"
            header.setInt("ih-invoice", number)
            header.setInt("ih-date", date)
            header.setInt("ih-type", 2)
            header.setInt("ih-net", 1_000)
            header.setInt("ih-vat", 100)
            header["ih-status"] = number == 10 ? "I" : "P"
            header["ih-status-l"] = "L"
            XCTAssertEqual(invoices.file.write(header), "00")
        }
        let posted = try service.post()
        XCTAssertEqual(posted.posted, [10])
        XCTAssertTrue(posted.unprinted)
        XCTAssertEqual(invoices.header(.init(value: 10))?.str("ih-status"), "Z")
        XCTAssertEqual(invoices.header(.init(value: 11))?.str("ih-status"), "P")
        XCTAssertEqual(customers.read(key: "CUST011")?.int("sales-current"), 1_100)
        XCTAssertEqual(SalesOpenItems.file(store).allRecords().map { $0.int("invoice") }, [10])
        XCTAssertEqual(store.readRaw(SalesPosting.workPath), [])
        let gl = RelativeFile(store, path: "ledgers/acas/posting.dat", recordSize: SalesPostingRecords.posting.size)
        let posting = Record(SalesPostingRecords.posting, bytes: try XCTUnwrap(gl.read(1)))
        XCTAssertEqual(posting.int("debit"), 4567)
        XCTAssertEqual(posting.int("credit"), 1234)
        XCTAssertEqual(posting.int("tax-account"), 7890)
        XCTAssertEqual(posting.int("tax-amount"), 100)
        let monthly = Record(SalesPostingRecords.monthly, bytes: try XCTUnwrap(invoices.systemFile.read(4)))
        XCTAssertEqual(monthly.int("invoices"), 1_100)
        let report = try XCTUnwrap(store.readRaw(SalesPosting.exportPath))
        XCTAssertEqual(String(decoding: report[54..<76], as: UTF8.self), "Invoice Posting Report")
        XCTAssertTrue(try service.post().posted.isEmpty)
        XCTAssertEqual(customers.read(key: "CUST011")?.int("sales-current"), 1_100)
    }
}
