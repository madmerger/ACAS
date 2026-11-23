import XCTest
@testable import ACASCore

final class SalesPostingTests: XCTestCase {
    func testFirstPrintedInvoiceInitializesAnalysisAndWorkFiles() throws {
        let (store, context, invoices) = try newCompany()
        let invoice = try invoices.save(draft(in: invoices))
        XCTAssertEqual(try invoices.printInvoices().map(\.id), [invoice.id])
        XCTAssertFalse(store.exists(SalesPosting.analysisPath))
        XCTAssertFalse(store.exists(SalesPosting.workPath))

        let service = SalesPosting(context)
        XCTAssertNoThrow(try service.checkAvailability())
        XCTAssertEqual(try service.post().posted, [invoice.id.value])
        XCTAssertEqual(store.all(SalesPosting.analysisPath).count, 16)
        XCTAssertEqual(store.readRaw(SalesPosting.workPath), [])
        XCTAssertEqual(try SalesLedger(context).systemRecord().int("s-flag-i"), 2)
        XCTAssertFalse(try SalesPayments(context).allocations(customer: "CUST011", date: invoices.processingDate).isEmpty)
    }

    func testCreditTargetsInvoiceFromPersistedShortHeader() throws {
        let (store, context, invoices) = try newCompany()
        let service = SalesPosting(context)
        let original = draft(in: invoices)
        let first = try invoices.save(original)
        let target = try invoices.save(original)
        _ = try invoices.printInvoices()
        _ = try service.post()
        var credit = original
        credit.kind = .creditNote
        credit.creditedInvoice = target.id.value
        let saved = try invoices.save(credit)
        _ = try invoices.printInvoices()
        XCTAssertEqual(store.read(invoices.file.path, key: invoices.key(saved.id))?.count, SalesInvoices.recordSize)

        XCTAssertEqual(try service.post().posted, [saved.id.value])
        let openItems = SalesOpenItems.file(store)
        XCTAssertEqual(openItems.read(key: SalesOpenItems.key(customer: credit.customer, invoice: first.id.value))?.int("paid"), 0)
        XCTAssertEqual(openItems.read(key: SalesOpenItems.key(customer: credit.customer, invoice: target.id.value))?.int("paid"), 1_000)
        XCTAssertEqual(openItems.read(key: SalesOpenItems.key(customer: credit.customer, invoice: saved.id.value))?.int("credit"), target.id.value)
    }

    func testFirstUnappliedCreditStartsDedicatedReportPage() throws {
        let (store, context, invoices) = try newCompany()
        var credit = draft(in: invoices)
        credit.kind = .creditNote
        _ = try invoices.save(credit, confirmingUnknownCreditTarget: true)
        _ = try invoices.printInvoices()
        _ = try SalesPosting(context).post()

        let report = try XCTUnwrap(store.readRaw(SalesPosting.exportPath))
        let pages = report.split(separator: 0x0c).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(pages.count, 2)
        XCTAssertFalse(pages.first?.contains("--Customer--") ?? true)
        XCTAssertTrue(pages.last?.contains("--Customer--") ?? false)
        XCTAssertTrue(pages.last?.contains("Un-Applied Credits C/F") ?? false)
    }

    private func newCompany() throws -> (FileStore, BusinessContext, SalesInvoices) {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try CompanySetup(context).save(name: "TEST COMPANY")
        var customer = Record(SalesProofRecords.salesLayout)
        customer["sales-key"] = "CUST011"
        customer["sales-name"] = "TEST CUSTOMER"
        customer.setInt("sales-status", 1)
        XCTAssertEqual(SalesProofRecords.salesFile(store).write(customer), "00")
        return (store, context, SalesInvoices(context))
    }

    private func draft(in invoices: SalesInvoices) -> SalesInvoices.Draft {
        var draft = SalesInvoices.Draft(date: invoices.processingDate)
        draft.customer = "CUST011"
        draft.lines[0].product = "PRODUCT"
        draft.lines[0].description = "PRODUCT NAME"
        draft.lines[0].analysis = "a1"
        draft.lines[0].unit = 1_000
        return draft
    }

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
