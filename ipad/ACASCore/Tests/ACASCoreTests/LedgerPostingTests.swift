import Foundation
import XCTest
@testable import ACASCore

final class LedgerPostingTests: XCTestCase {
    func testPostsWaitingBatchAndUsesDebitCreditAndVAT() throws {
        let context = try prepare()
        try closeBatch(context, withTax: true)
        let result = try LedgerPosting(context).postCurrentCycle()
        XCTAssertEqual(result.batches, 1)
        XCTAssertEqual(result.entries, 3)
        let chart = ChartOfAccounts(context)
        XCTAssertEqual(chart.account(code: "300001")?.balance, 10_000)
        XCTAssertEqual(chart.account(code: "300002")?.balance, -12_000)
        XCTAssertEqual(chart.account(code: "300003")?.balance, 2_000)
        let batch = try XCTUnwrap(batchFile(context).read(key: "100001"))
        XCTAssertEqual(batch.int("cleared"), 1)
        XCTAssertEqual(batch.int("posted"), CompanySetup(context).settings.number("run-date"))
        let report = try XCTUnwrap(context.store.readRaw(CompanySetup.reportPath))
        XCTAssertTrue(String(decoding: report, as: UTF8.self).contains("Transaction  Posting"))
        XCTAssertTrue(String(decoding: report, as: UTF8.self).contains("Memo"))
        XCTAssertEqual(try LedgerPosting(context).postCurrentCycle().batches, 0)
        XCTAssertEqual(chart.account(code: "300001")?.balance, 10_000)
    }

    func testCurrentOpenBatchBlocksPosting() throws {
        let context = try prepare()
        let before = context.store.snapshot()
        XCTAssertThrowsError(try LedgerPosting(context).postCurrentCycle()) {
            XCTAssertEqual($0 as? LedgerPosting.Error, .openBatches)
        }
        XCTAssertEqual(context.store.snapshot(), before)
    }

    func testMissingAccountRollsBackOtherAccountBalanceAndBatchStatus() throws {
        let context = try prepare()
        try closeBatch(context)
        XCTAssertEqual(ChartOfAccounts(context).account(code: "300002")?.balance, 0)
        try ChartOfAccounts(context).delete(code: "300002")
        let before = context.store.snapshot()
        XCTAssertThrowsError(try LedgerPosting(context).postCurrentCycle()) {
            XCTAssertEqual($0 as? LedgerPosting.Error, .missingAccount("30000200"))
        }
        XCTAssertEqual(context.store.snapshot(), before)
        XCTAssertFalse(context.store.exists(CompanySetup.reportPath))
    }

    private func prepare() throws -> BusinessContext {
        let date = DateComponents(year: 2026, month: 11, day: 23)
        let context = BusinessContext(store: try FileStore(), timeZone: .gmt)
        let company = CompanySetup(context)
        var settings = company.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try company.save(settings)
        let general = GeneralLedgerSetup(context)
        try general.start(year: 2026, month: 11, day: 23)
        let chart = ChartOfAccounts(context)
        try chart.add(code: "300000", name: "CONTROL", type: 0, placement: "S", level: 1)
        try chart.add(code: "300001", name: "BANK", type: 1, placement: "", level: 0)
        try chart.add(code: "300002", name: "SALES", type: 1, placement: "", level: 0)
        try chart.add(code: "300003", name: "VAT", type: 1, placement: "", level: 0)
        XCTAssertTrue(try general.saveDefault(number: 1, account: "300002", transactionCode: "GL", tax: .noTax))
        var draft = LedgerBatchDraft(cycle: 1, defaultNumber: 1, direction: .debit, date: date)
        draft.description = "Journal"
        draft.gross = 10_000
        draft.expectedItems = 1
        _ = try LedgerBatches(context).add(draft, lines: [
            JournalLine(date: date, account: "300001", amount: 10_000, memo: "Memo")
        ])
        return context
    }

    private func closeBatch(_ context: BusinessContext, withTax: Bool = false) throws {
        let batches = batchFile(context)
        var batch = try XCTUnwrap(batches.read(key: "100001"))
        batch.setInt("status", 1)
        XCTAssertEqual(batches.rewrite(batch), "00")
        if withTax {
            let layout = LedgerBatches.postingLayout
            let relative = RelativeFile(context.store, path: LedgerBatches.postingPath, recordSize: layout.size)
            var posting = Record(layout, bytes: try XCTUnwrap(relative.read(2)))
            posting.setInt("vat-account", 300003)
            posting.setInt("vat-amount", 2_000)
            try relative.write(2, posting.bytes)
        }
    }

    private func batchFile(_ context: BusinessContext) -> IndexedFile {
        IndexedFile(context.store, path: LedgerBatches.batchPath, layout: LedgerBatches.batchLayout, keyLength: 6)
    }
}
