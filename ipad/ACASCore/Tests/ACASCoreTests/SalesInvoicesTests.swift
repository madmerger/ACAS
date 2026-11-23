import XCTest
@testable import ACASCore

final class SalesInvoicesTests: XCTestCase {
    func testPrintedInvoiceCanBeAmendedAndReturnsToPrintQueue() throws {
        let (service, invoice) = try makeInvoice()
        var header = try XCTUnwrap(service.header(invoice.id))
        header["ih-status-p"] = "P"
        XCTAssertTrue(service.context.store.rewrite(
            service.file.path, key: service.key(invoice.id), data: Array(header.bytes.prefix(SalesInvoices.recordSize))
        ))
        _ = try service.printInvoices()
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status"), "I")

        var draft = try service.draft(for: invoice.id)
        draft.reference = "AMENDED"
        _ = try service.save(draft, replacing: invoice.id)
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status"), "P")
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status-p"), " ")
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status-l"), "L")
        XCTAssertEqual(try service.printInvoices().map(\.id), [invoice.id])
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status"), "I")
        XCTAssertEqual(service.header(invoice.id)?.str("ih-ref"), "AMENDED   ")
    }

    func testAppliedInvoiceCannotBeDeletedWithEitherStatusCase() throws {
        let (service, invoice) = try makeInvoice()
        for status in ["z", "Z"] {
            var header = try XCTUnwrap(service.header(invoice.id))
            header["ih-status"] = status
            XCTAssertTrue(service.context.store.rewrite(
                service.file.path, key: service.key(invoice.id), data: Array(header.bytes.prefix(SalesInvoices.recordSize))
            ))
            let before = service.context.store.snapshot()
            XCTAssertThrowsError(try service.delete(invoice.id)) {
                XCTAssertEqual($0 as? SalesInvoices.Error, .locked)
            }
            XCTAssertEqual(service.context.store.snapshot(), before)
        }
    }

    private func makeInvoice() throws -> (SalesInvoices, SalesInvoices.Invoice) {
        let store = try FileStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = SalesInvoices(BusinessContext(store: store, timeZone: .gmt, now: { date }))
        var settings = Record(SystemLayout.layout)
        settings.setInt("next-invoice", 1)
        try service.systemFile.write(1, settings.bytes)
        var account = Record(SalesProofRecords.salesLayout)
        let customer = "TEST011"
        account["sales-key"] = customer
        account["sales-name"] = "TEST CUSTOMER"
        account.setInt("sales-status", 1)
        XCTAssertTrue(store.write(SalesProofRecords.salesFile(store).path, key: Array(customer.utf8), data: account.bytes))
        var draft = SalesInvoices.Draft(date: date)
        draft.customer = customer
        draft.lines[0].product = "PRODUCT"
        draft.lines[0].description = "PRODUCT NAME"
        draft.lines[0].unit = 100
        return (service, try service.save(draft))
    }
}
