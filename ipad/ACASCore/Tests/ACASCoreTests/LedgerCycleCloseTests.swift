import XCTest
@testable import ACASCore

final class LedgerCycleCloseTests: XCTestCase {
    func testPeriodEndArchivesCurrentBatchAndCopiesQuarterBalance() throws {
        let context = try fixture(closed: true, archive: true, cycle: 12)
        try LedgerCycleClose(context).close()

        let settings = CompanySetup(context).settings
        XCTAssertEqual(settings.number("scycle"), 1)
        XCTAssertEqual(settings.number("current-quarter"), 1)
        let batch = try XCTUnwrap(batchFile(context).read(key: "100001"))
        XCTAssertEqual(batch.int("cleared"), 2)
        XCTAssertEqual(batch.int("stored"), settings.number("run-date"))
        XCTAssertEqual(batch.int("start"), 0)
        XCTAssertEqual(batchFile(context).read(key: "100002")?.int("cleared"), 0)

        let postings = postingFile(context)
        XCTAssertEqual(postings.recordCount, 2)
        XCTAssertEqual(Record(LedgerBatches.postingLayout, bytes: try XCTUnwrap(postings.read(2))).int("batch"), 2)
        let bytes = try XCTUnwrap(context.store.readRaw(LedgerCycleClose.archivePath))
        let rows = bytes.split(separator: 10)
        XCTAssertEqual(rows.map(\.count), [78, 78])
        XCTAssertEqual(rows.map { String(decoding: $0.dropFirst(20).prefix(8), as: UTF8.self) },
                       ["30000100", "30000200"])
        let account = try XCTUnwrap(ChartOfAccounts(context).account(code: "300001"))
        XCTAssertEqual(account.previousBalance, 1_250)
        XCTAssertEqual(account.quarterBalances, [0, 0, 0, 1_250])
    }

    func testNonPeriodCloseRemovesPostingsWithoutAdvancingCycle() throws {
        let context = try fixture(closed: true, archive: false, cycle: 1)
        try LedgerCycleClose(context).close()
        XCTAssertEqual(CompanySetup(context).settings.number("scycle"), 1)
        XCTAssertFalse(context.store.exists(LedgerCycleClose.archivePath))
        XCTAssertEqual(postingFile(context).recordCount, 2)
    }

    func testUnfinishedBatchesLeaveAllRecordsUnchanged() throws {
        let context = try fixture(closed: false, archive: true, cycle: 12)
        let before = context.store.snapshot()
        XCTAssertThrowsError(try LedgerCycleClose(context).close()) {
            XCTAssertEqual($0 as? LedgerCycleClose.Error, .unfinishedBatches)
        }
        XCTAssertEqual(context.store.snapshot(), before)
    }

    private func fixture(closed: Bool, archive: Bool, cycle: Int64) throws -> BusinessContext {
        let context = BusinessContext(store: try FileStore(), timeZone: .gmt)
        let company = CompanySetup(context)
        var settings = company.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(cycle, for: "scycle")
        try settings.setNumber(3, for: "period")
        try settings.setNumber(4, for: "current-quarter")
        try settings.setText(archive ? "Y" : "N", for: "arch")
        try company.save(settings)
        let ledger = IndexedFile(context.store, path: ChartOfAccounts.path, layout: ChartOfAccounts.layout, keyLength: 8)
        var account = Record(ChartOfAccounts.layout)
        account.setInt("code", 300001)
        account.setInt("type", 1)
        account.setInt("balance", 1_250)
        XCTAssertEqual(ledger.write(account), "00")
        let postings = postingFile(context)
        try postings.write(1, Record(LedgerBatches.postingLayout).bytes)
        for (number, batchCycle) in [(Int64(1), cycle), (2, cycle + 1)] {
            var batch = Record(LedgerBatches.batchLayout)
            batch.setInt("ledger", 1)
            batch.setInt("number", number)
            batch.setInt("cycle", batchCycle)
            batch.setInt("status", closed ? 1 : 0)
            batch.setInt("start", number)
            XCTAssertEqual(batchFile(context).write(batch), "00")
            var posting = Record(LedgerBatches.postingLayout)
            posting.setInt("batch", number)
            posting.setInt("sequence", 1)
            posting.setInt("debit", 300001)
            posting.setInt("credit", 300002)
            posting.setInt("amount", 1_250)
            try postings.write(Int(number + 1), posting.bytes)
        }
        return context
    }

    private func batchFile(_ context: BusinessContext) -> IndexedFile {
        IndexedFile(context.store, path: LedgerBatches.batchPath, layout: LedgerBatches.batchLayout, keyLength: 6)
    }

    private func postingFile(_ context: BusinessContext) -> RelativeFile {
        RelativeFile(context.store, path: LedgerBatches.postingPath, recordSize: LedgerBatches.postingLayout.size)
    }
}
