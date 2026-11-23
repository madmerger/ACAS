import XCTest
@testable import ACASCore

final class SalesInvoicesTests: XCTestCase {
    func testBatchPrintOnlyClearsReportWhenInvoicingAndAnalysisAreEnabled() throws {
        let (service, _) = try makeInvoice()
        let store = service.context.store
        var system = try service.settings()
        for (invoicing, status, expected) in [(0, "1", [UInt8(42)]), (1, "0", [UInt8(42)]), (1, "1", [])] {
            system.setInt("full-invoicing", Int64(invoicing))
            var flags = system.raw("file-statuses")
            flags[14] = Array(status.utf8)[0]
            system.setRaw("file-statuses", flags)
            try service.systemFile.write(1, system.bytes)
            try store.writeRaw(SalesInvoices.printPath, [42])
            try service.openBatchPrint()
            XCTAssertEqual(store.readRaw(SalesInvoices.printPath), expected)
        }
    }

    func testFixedDataValidatesAndPersistsCobolFields() throws {
        let (service, _) = try makeInvoice()
        var system = try service.settings()
        system.setInt("level-1", 1)
        try service.systemFile.write(1, system.bytes)
        var draft = try service.fixedData()
        draft.nextInvoice = "0"
        draft.entryLevel = "2"
        draft.stockLink = "n"
        draft.extraDescription = "追加料金"
        draft.extraType = "c"
        draft.printExtra = "y"
        draft.extraRate = "5.129"
        draft.extraAccount = "400001"
        draft.taxAccount = "400002"
        draft.proFormaDays = "90"
        XCTAssertThrowsError(try service.saveFixedData(draft))
        XCTAssertEqual(try service.settings().bytes, system.bytes)
        draft.nextInvoice = "10000000"
        XCTAssertThrowsError(try service.saveFixedData(draft))
        XCTAssertEqual(try service.settings().bytes, system.bytes)
        draft.extraRate = "5.1"
        try service.saveFixedData(draft)
        let saved = try service.fixedData()
        XCTAssertEqual(saved.nextInvoice, "10000000")
        XCTAssertEqual(saved.entryLevel, "2")
        XCTAssertEqual(saved.stockLink, "N")
        XCTAssertEqual(saved.stockAudit, "N")
        XCTAssertEqual(saved.extraDescription, "追加料金")
        XCTAssertEqual(saved.extraType, "C")
        XCTAssertEqual(saved.printExtra, "Y")
        XCTAssertEqual(saved.extraRate, "05.10")
        XCTAssertEqual(saved.extraAccount, "400001")
        XCTAssertEqual(saved.taxAccount, "400002")
        XCTAssertEqual(saved.proFormaDays, "090")
    }

    func testDeletionReportIncludesDeletedInvoice() throws {
        let (service, invoice) = try makeInvoice()
        try service.delete(invoice.id)

        XCTAssertTrue(service.invoices().isEmpty)
        XCTAssertEqual(try service.printDeletedInvoices(), 1)
        let report = try XCTUnwrap(service.context.store.readRaw(SalesInvoices.deletionReportPath))
        guard report.count >= 133 else {
            XCTFail("削除帳票に132バイトの明細がありません")
            return
        }
        let detail = Array(report.suffix(133).dropLast())
        XCTAssertEqual(detail.count, 132)
        XCTAssertEqual(SJIS.decode(detail[3..<13]).trimmingCharacters(in: .whitespaces), String(invoice.id.value))
        XCTAssertEqual(SJIS.decode(detail[31..<38]), invoice.customer)
        XCTAssertEqual(report.last, 0x0a)
    }

    func testInvoiceCanBeRegisteredForExistingDormantCustomer() throws {
        let (service, invoice) = try makeInvoice()
        let draft = try service.draft(for: invoice.id)
        let customers = SalesProofRecords.salesFile(service.context.store)
        var account = try XCTUnwrap(customers.read(key: draft.customer))
        account.setInt("sales-status", 0)
        XCTAssertEqual(customers.rewrite(account), "00")

        let nextInvoice = try service.save(draft)
        XCTAssertNotEqual(nextInvoice.id, invoice.id)
        XCTAssertEqual(customers.read(key: draft.customer)?.int("sales-status"), 0)
    }

    func testPrintedInvoiceCanBeAmendedAndReturnsToPrintQueue() throws {
        let (service, invoice) = try makeInvoice()
        var header = try XCTUnwrap(service.header(invoice.id))
        header["ih-status-p"] = "P"
        XCTAssertTrue(service.context.store.rewrite(
            service.file.path, key: service.key(invoice.id), data: Array(header.bytes.prefix(SalesInvoices.recordSize))
        ))
        _ = try service.printInvoices()
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status"), "I")
        XCTAssertEqual(service.invoices().filter(\.printed).map(\.id), [invoice.id])

        var draft = try service.draft(for: invoice.id)
        draft.reference = "AMENDED"
        _ = try service.save(draft, replacing: invoice.id)
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status"), "P")
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status-p"), " ")
        XCTAssertEqual(service.header(invoice.id)?.str("ih-status-l"), "L")
        XCTAssertTrue(service.invoices().filter(\.printed).isEmpty)
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

    func testCreditRegistrationRequiresMatchingOpenAccountInvoiceOrExplicitConfirmation() throws {
        let (service, invoice) = try makeInvoice()
        var draft = try service.draft(for: invoice.id)
        draft.kind = .creditNote
        draft.creditedInvoice = invoice.id.value
        let path = "ledgers/acas/openitm3.dat"
        let key = Array(draft.customer.utf8) + [1, 0, 0, 0]
        var record = key + Array(repeating: UInt8(0x20), count: 103)
        let otherKey = Array("OTHER01".utf8) + [1, 0, 0, 0]
        XCTAssertTrue(service.context.store.write(path, key: otherKey, data: otherKey + Array(record.dropFirst(11))))
        let before = service.context.store.snapshot()
        XCTAssertThrowsError(try service.save(draft)) {
            XCTAssertEqual($0 as? SalesInvoices.Error, .unverifiedCreditTarget)
        }
        XCTAssertEqual(service.context.store.snapshot(), before)
        XCTAssertNoThrow(try service.save(draft, confirmingUnknownCreditTarget: true))
        record[21] = 0x31
        record[94] = 0x30
        XCTAssertTrue(service.context.store.write(path, key: key, data: record))
        XCTAssertThrowsError(try service.save(draft, confirmingUnknownCreditTarget: true)) {
            XCTAssertEqual($0 as? SalesInvoices.Error, .invalidCreditTarget)
        }
        record[21] = 0x32
        record[94] = 0x31
        XCTAssertTrue(service.context.store.rewrite(path, key: key, data: record))
        XCTAssertThrowsError(try service.save(draft, confirmingUnknownCreditTarget: true)) {
            XCTAssertEqual($0 as? SalesInvoices.Error, .invalidCreditTarget)
        }
        record[94] = 0x30
        XCTAssertTrue(service.context.store.rewrite(path, key: key, data: record))
        XCTAssertNoThrow(try service.save(draft))
    }

    func testCreditAmendmentChecksCustomerAndInvoiceType() throws {
        let (service, invoice) = try makeInvoice()
        var draft = try service.draft(for: invoice.id)
        draft.kind = .creditNote
        let credit = try service.save(draft)
        draft.creditedInvoice = invoice.id.value
        XCTAssertNoThrow(try service.save(draft, replacing: credit.id))
        draft.creditedInvoice = credit.id.value
        XCTAssertThrowsError(try service.save(draft, replacing: credit.id, confirmingUnknownCreditTarget: true)) {
            XCTAssertEqual($0 as? SalesInvoices.Error, .invalidCreditTarget)
        }
        var target = try XCTUnwrap(service.header(invoice.id))
        target["ih-customer"] = "OTHER01"
        XCTAssertTrue(service.context.store.rewrite(
            service.file.path, key: service.key(invoice.id), data: Array(target.bytes.prefix(SalesInvoices.recordSize))
        ))
        draft.creditedInvoice = invoice.id.value
        XCTAssertThrowsError(try service.save(draft, replacing: credit.id, confirmingUnknownCreditTarget: true)) {
            XCTAssertEqual($0 as? SalesInvoices.Error, .invalidCreditTarget)
        }
    }

    func testChangingInvoiceToCreditNoteRejectsItsOwnNumber() throws {
        let (service, invoice) = try makeInvoice()
        var draft = try service.draft(for: invoice.id)
        draft.kind = .creditNote
        draft.creditedInvoice = invoice.id.value
        let before = service.context.store.snapshot()

        XCTAssertThrowsError(try service.save(draft, replacing: invoice.id, confirmingUnknownCreditTarget: true)) {
            XCTAssertEqual($0 as? SalesInvoices.Error, .invalidCreditTarget)
        }
        XCTAssertEqual(service.context.store.snapshot(), before)
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
