import ACASCore
import XCTest

final class LedgerBatchesTests: XCTestCase {
    func testBatchAndPostingBytesAndValidation() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let company = CompanySetup(context)
        var settings = company.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try company.save(settings)
        let chart = ChartOfAccounts(context)
        try chart.add(code: "300000", name: "CONTROL", type: 0, placement: "S", level: 1)
        try chart.add(code: "300001", name: "BANK", type: 1, placement: "", level: 0)
        XCTAssertTrue(try GeneralLedgerSetup(context).saveDefault(number: 1, account: "300001", transactionCode: "GL", tax: .noTax))

        let date = DateComponents(year: 2026, month: 11, day: 23)
        let batch = LedgerBatches(context)
        let postingPath = "ledgers/acas/posting.dat"
        let batchPath = "ledgers/acas/batch.dat"
        let invalid = LedgerBatchDraft(cycle: 3, defaultNumber: 1, direction: .debit, date: date)
        let entry = JournalLine(date: date, account: "300000", amount: 12_345, memo: "Memo")
        XCTAssertThrowsError(try batch.add(invalid, lines: [entry]))
        XCTAssertFalse(store.exists(batchPath))
        XCTAssertFalse(store.exists(postingPath))

        var draft = LedgerBatchDraft(cycle: 1, defaultNumber: 1, direction: .debit, date: date)
        draft.description = "Journal"
        draft.gross = 12_345
        draft.expectedItems = 1
        XCTAssertEqual(try batch.add(draft, lines: [entry]), 1)
        XCTAssertEqual(batch.all.map(\.id), [1])
        let record = try XCTUnwrap(store.read(batchPath, key: Array("100001".utf8)))
        XCTAssertEqual(record.count, 96)
        XCTAssertEqual(Array(record.prefix(12)), Array("100001010001".utf8))
        XCTAssertEqual(Array(record.suffix(5)), Array("00001".utf8))
        let posting = try XCTUnwrap(RelativeFile(store, path: postingPath, recordSize: 98).read(2))
        XCTAssertEqual(Array(posting.prefix(46)), Array("0000100001GL23/11/2630000000300001000000012345".utf8))
        XCTAssertEqual(company.settings.number("next-batch"), 2)
    }
}
