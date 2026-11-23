import XCTest
@testable import ACASCore

final class SalesPaymentsTests: XCTestCase {
    func testUsingOnlyUnappliedBalancePreservesPaymentFlag() throws {
        let (store, context, date) = try setup()
        var draft = SalesPayments.Draft(date: date)
        draft.customer = "CUST011"
        draft.amount = 100
        draft.useUnappliedBalance = true
        let service = SalesPayments(context)
        let ledger = SalesLedger(context)
        XCTAssertEqual(try service.saveBatch([draft]), 3)
        XCTAssertEqual(try ledger.systemRecord().int("s-flag-p"), 0)

        var system = try ledger.systemRecord()
        system.setInt("s-flag-p", 2)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        XCTAssertEqual(try service.saveBatch([draft]), 4)
        XCTAssertEqual(try ledger.systemRecord().int("s-flag-p"), 2)
    }

    func testPaymentBatchUpdatesOpenItemAndUnappliedBalance() throws {
        let (store, context, date) = try setup()
        let service = SalesPayments(context)
        XCTAssertEqual(SalesOpenItems.layout.size, 114)
        XCTAssertEqual(try service.allocations(customer: "cust011", date: date).first?.outstanding, 1_000)
        var payment = SalesPayments.Draft(date: date)
        payment.customer = "CUST011"
        payment.amount = 1_200
        payment.allocations = [10: 1_000]
        var journal = SalesPayments.Draft(date: date)
        journal.customer = payment.customer
        journal.amount = 200
        journal.useUnappliedBalance = true

        XCTAssertEqual(try service.saveBatch([payment, journal]), 3)
        let openItems = SalesOpenItems.file(store)
        let invoice = try XCTUnwrap(openItems.read(key: SalesOpenItems.key(customer: payment.customer, invoice: 10)))
        XCTAssertEqual(invoice.int("paid"), 1_000)
        XCTAssertEqual(invoice.int("credit"), 100_000)
        XCTAssertEqual(invoice.int("status"), 1)
        XCTAssertEqual(invoice.int("batch"), 3)
        let saved = try XCTUnwrap(openItems.read(key: SalesOpenItems.key(customer: payment.customer, invoice: 3_001)))
        XCTAssertEqual(saved.int("type"), 5)
        XCTAssertEqual(saved.int("net"), 1_000)
        XCTAssertEqual(saved.int("paid"), 1_200)
        let unapplied = try XCTUnwrap(openItems.read(key: SalesOpenItems.key(customer: payment.customer, invoice: 3_002)))
        XCTAssertEqual(unapplied.int("type"), 6)
        let ledger = SalesLedger(context)
        XCTAssertEqual(try ledger.customer(code: payment.customer).unapplied, 300)
        XCTAssertEqual(try ledger.systemRecord().int("first-sl-batch"), 4)
        XCTAssertEqual(try ledger.systemRecord().int("s-flag-p"), 1)
    }

    func testInvalidAllocationRollsBackTheWholeBatch() throws {
        let (store, context, date) = try setup()
        var first = SalesPayments.Draft(date: date)
        first.customer = "CUST011"
        first.amount = 500
        first.useUnappliedBalance = true
        var second = first
        second.useUnappliedBalance = false
        second.allocations = [10: 501]
        let before = EvidenceComparison.snapshot(store)
        XCTAssertThrowsError(try SalesPayments(context).saveBatch([first, second]))
        XCTAssertEqual(EvidenceComparison.snapshot(store), before)
    }

    func testProofSortsPaymentBeforeInvoiceAndAmendmentRestoresJournal() throws {
        let (store, context, date) = try setup()
        let service = SalesPayments(context)
        var draft = SalesPayments.Draft(date: date)
        draft.customer = "CUST011"
        draft.amount = 500
        draft.useUnappliedBalance = true
        draft.allocations = [10: 500]
        try service.saveBatch([draft])

        let proof = try SalesPaymentProof(context).generate()
        let payment = try XCTUnwrap(proof.first)
        XCTAssertEqual(payment.amount, 500)
        XCTAssertTrue(payment.journal)
        let sorted = try XCTUnwrap(store.readRaw(SalesPaymentProof.sortedPath))
        XCTAssertEqual(sorted.count, 228)
        XCTAssertEqual(Record(SalesOpenItems.layout, bytes: Array(sorted.prefix(114))).int("type"), 6)
        XCTAssertEqual(Record(SalesOpenItems.layout, bytes: Array(sorted.suffix(114))).int("type"), 2)
        let report = try XCTUnwrap(store.readRaw(SalesPaymentProof.exportPath))
        XCTAssertEqual(String(decoding: report[48..<80], as: UTF8.self), "Payment And Journal Proof Report")
        XCTAssertEqual(try SalesLedger(context).systemRecord().int("s-flag-p"), 2)

        try service.cancel(payment)
        XCTAssertTrue(try service.pending().isEmpty)
        let remaining = try XCTUnwrap(SalesOpenItems.file(store).allRecords().first)
        XCTAssertEqual(remaining.int("paid"), 0)
        XCTAssertEqual(remaining.int("batch"), 0)
        XCTAssertEqual(try SalesLedger(context).customer(code: draft.customer).unapplied, 500)
    }

    private func setup() throws -> (FileStore, BusinessContext, Date) {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let date = try XCTUnwrap(context.calendar.date(from: DateComponents(year: 2026, month: 11, day: 23)))
        var settings = Record(SystemLayout.layout)
        settings["file-statuses"] = String(repeating: "0", count: 18) + "1"
        settings.setInt("first-sl-batch", 3)
        settings.setInt("page-lines", 60)
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, settings.bytes)
        var customer = Record(SalesProofRecords.salesLayout)
        customer["sales-key"] = "CUST011"
        customer.setInt("sales-unapplied", 500)
        XCTAssertEqual(SalesProofRecords.salesFile(store).write(customer), "00")
        var invoice = Record(SalesOpenItems.layout)
        invoice["customer"] = "CUST011"
        invoice.setInt("type", 2)
        invoice.setInt("invoice", 10)
        invoice.setInt("net", 1_000)
        invoice.setInt("date", Int64(Maps04.integerOfDate(year: 2026, month: 11, day: 1)))
        XCTAssertEqual(SalesOpenItems.file(store).write(invoice), "00")
        return (store, context, date)
    }
}
