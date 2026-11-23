import ACASCore
import XCTest

final class LedgerBatchProofTests: XCTestCase {
    func testProofRecordsTotalsAndEnablesPostingOnlyForMatchingBatch() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try setup.save(settings)
        let chart = ChartOfAccounts(context)
        try chart.add(code: "300000", name: "BANK", type: 0, placement: "S", level: 1)
        try chart.add(code: "400000", name: "EXPENSE", type: 0, placement: "S", level: 1)
        try GeneralLedgerSetup(context).saveDefault(number: 1, account: "300000", transactionCode: "GL", tax: .noTax)
        let date = DateComponents(year: 2026, month: 11, day: 23)
        var draft = LedgerBatchDraft(cycle: 1, defaultNumber: 1, direction: .debit, date: date)
        let line = JournalLine(date: date, account: "400000", amount: 12_345, memo: "Posting test")
        let batches = LedgerBatches(context)
        draft.gross = 12_345
        try batches.add(draft, lines: [line])
        draft.gross = 1
        try batches.add(draft, lines: [line])
        draft = LedgerBatchDraft(cycle: 2, defaultNumber: 1, direction: .debit, date: date)
        try batches.add(draft, lines: [line])
        let proof = LedgerBatchProof(context)
        let posting = LedgerPosting(context)

        XCTAssertThrowsError(try posting.postCurrentCycle())
        let one = try XCTUnwrap(proof.generate(batch: 1).first)
        XCTAssertTrue(one.verified)
        XCTAssertEqual(store.readRaw(CompanySetup.reportPath), one.bytes)
        XCTAssertTrue(String(decoding: one.bytes, as: UTF8.self).contains("* Batch Verified Ok *"))
        let all = try proof.generate()
        XCTAssertEqual(all.map(\.id), [1, 2])
        XCTAssertEqual(all.map(\.verified), [true, false])
        XCTAssertEqual(batches.all.map(\.closed), [true, false, false])
        XCTAssertThrowsError(try posting.postCurrentCycle())
    }
}
