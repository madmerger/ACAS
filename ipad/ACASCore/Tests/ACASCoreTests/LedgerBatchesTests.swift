import ACASCore
import SQLite3
import XCTest

final class LedgerBatchesTests: XCTestCase {
    func testLeavingDefaultSelectionConsumesNumberAndRetainingTemporaryDefaultDoesNotCreateBatch() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        try setup.save(name: "TEST")
        try ChartOfAccounts(context).add(code: "300000", name: "BANK", type: 0, placement: "S", level: 1)
        let batch = LedgerBatches(context)
        let counter = setup.settings.number("next-batch")
        try batch.exitDefaultSelection()
        XCTAssertEqual(setup.settings.number("next-batch"), counter + 1)
        try batch.retainTemporaryDefault(TemporaryLedgerDefault(account: "300000", code: "bk", tax: .noTax),
                                        branch: "00")
        let stored = try XCTUnwrap(GeneralLedgerSetup(context).defaults.last)
        XCTAssertEqual(stored.id, 33)
        XCTAssertEqual(stored.account, "300000")
        XCTAssertEqual(stored.transactionCode, "BK")
        XCTAssertEqual(stored.tax, .noTax)
        XCTAssertTrue(batch.all.isEmpty)
    }

    func testCycleOutsideCurrentAndNextIsRejectedWithoutWrites() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try setup.save(settings)
        let before = store.snapshot()
        for (cycle, expected) in [(0, LedgerBatches.Error.cycleTooEarly), (3, .cycleTooLate)] {
            let draft = LedgerBatchDraft(cycle: cycle, defaultNumber: 0, direction: .debit, date: DateComponents())
            XCTAssertThrowsError(try LedgerBatches(context).add(draft, lines: [])) { error in
                XCTAssertEqual(error as? LedgerBatches.Error, expected)
            }
        }
        XCTAssertEqual(store.snapshot(), before)
    }

    func testTaxAmountsAndAccountAreWrittenToTheBatchAndPosting() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try setup.save(settings)
        let chart = ChartOfAccounts(context)
        try chart.add(code: "300000", name: "CONTROL", type: 0, placement: "S", level: 1)
        try chart.add(code: "300001", name: "BANK", type: 1, placement: "", level: 0)
        try GeneralLedgerSetup(context).saveDefault(number: 1, account: "300001", transactionCode: "GL", tax: .input)
        let date = DateComponents(year: 2026, month: 11, day: 23)
        var draft = LedgerBatchDraft(cycle: 1, defaultNumber: 1, direction: .debit, date: date)
        draft.gross = 120
        draft.tax = 20
        let line = JournalLine(date: date, account: "300001", amount: 100, memo: "", tax: 20)
        let batches = LedgerBatches(context)
        XCTAssertThrowsError(try batches.add(draft, lines: [line]))
        try GeneralLedgerSetup(context).saveDefault(number: 31, account: "300000", transactionCode: "", tax: .noTax)
        XCTAssertEqual(try batches.add(draft, lines: [line]), 1)
        let batch = try XCTUnwrap(store.read("ledgers/acas/batch.dat", key: Array("100001".utf8)))
        XCTAssertEqual(Array(batch[34..<40]), [0, 0, 0, 0, 0x02, 0x0F])
        let posting = try XCTUnwrap(RelativeFile(store, path: "ledgers/acas/posting.dat", recordSize: 98).read(2))
        XCTAssertEqual(String(decoding: posting[78..<88], as: UTF8.self), "30000000DR")
        XCTAssertEqual(String(decoding: posting[88..<98], as: UTF8.self), "0000000020")
    }

    func testDefaultAndLineKeepTheirOwnBranches() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setText("B", for: "p-c")
        try settings.setNumber(1, for: "scycle")
        try setup.save(settings)
        let chart = ChartOfAccounts(context)
        for branch in ["00", "01", "02"] {
            try chart.add(code: "300000", branch: branch, name: "CONTROL", type: 0, placement: "S", level: 1)
        }
        try GeneralLedgerSetup(context).saveDefault(number: 1, account: "300000", transactionCode: "GL", tax: .noTax)
        let date = DateComponents(year: 2026, month: 11, day: 23)
        var draft = LedgerBatchDraft(cycle: 1, defaultNumber: 1, direction: .credit, date: date)
        draft.defaultBranch = "01"
        let line = JournalLine(date: date, account: "300000", branch: "02", amount: 10, memo: "")
        XCTAssertEqual(try LedgerBatches(context).add(draft, lines: [line]), 1)
        let posting = try XCTUnwrap(RelativeFile(store, path: "ledgers/acas/posting.dat", recordSize: 98).read(2))
        XCTAssertEqual(String(decoding: posting[20..<36], as: UTF8.self), "3000000130000002")
    }

    func testFailedCounterWriteRollsBackBatchAndPostings() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let store = try FileStore(path: path.path)
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try setup.save(settings)
        try ChartOfAccounts(context).add(code: "300000", name: "TEST", type: 0, placement: "S", level: 1)
        try GeneralLedgerSetup(context).saveDefault(number: 1, account: "300000", transactionCode: "GL", tax: .noTax)
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_open(path.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, """
            CREATE TRIGGER fail_batch_counter BEFORE UPDATE ON files
            WHEN NEW.name LIKE '%/system.dat' BEGIN SELECT RAISE(ABORT, 'test'); END
            """, nil, nil, nil), SQLITE_OK)
        let batches = LedgerBatches(context)
        let date = DateComponents(year: 2026, month: 11, day: 23)
        let draft = LedgerBatchDraft(cycle: 1, defaultNumber: 1, direction: .debit, date: date)
        let line = JournalLine(date: date, account: "300000", amount: 10, memo: "")
        XCTAssertThrowsError(try batches.add(draft, lines: [line]))
        XCTAssertFalse(store.exists("ledgers/acas/batch.dat"))
        XCTAssertFalse(store.exists("ledgers/acas/posting.dat"))
        XCTAssertEqual(sqlite3_exec(database, "DROP TRIGGER fail_batch_counter", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try batches.add(draft, lines: [line]), 1)
    }

    func testPrepareCreatesOnlySentinelAndIsIdempotent() throws {
        let store = try FileStore()
        let batches = LedgerBatches(BusinessContext(store: store))

        try batches.prepare()
        try batches.prepare()

        let sentinel = try XCTUnwrap(store.read("ledgers/acas/batch.dat", key: Array("999999".utf8)))
        XCTAssertEqual(sentinel.count, 96)
        XCTAssertEqual(Array(sentinel.prefix(12)), Array("999999000099".utf8))
        XCTAssertTrue(batches.all.isEmpty)
        XCTAssertTrue(store.exists("ledgers/acas/posting.dat"))
    }

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
        XCTAssertEqual(Array(posting.prefix(46)), Array("0000100001GL23/11/2030000000300001000000012345".utf8))
        XCTAssertEqual(company.settings.number("next-batch"), 2)
    }
}
