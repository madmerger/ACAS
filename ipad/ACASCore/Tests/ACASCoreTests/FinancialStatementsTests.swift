import XCTest
@testable import ACASCore

final class FinancialStatementsTests: XCTestCase {
    func testTotalsFollowLedgerHierarchyAndReportWritesFixedRecords() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try setup.save(settings)
        try GeneralLedgerSetup(context).start(year: 2026, month: 11, day: 23)
        let ledger = IndexedFile(store, path: ChartOfAccounts.path, layout: ChartOfAccounts.layout, keyLength: 8)
        ledger.openOutput()
        for (code, name, level, balance, placement) in [
            (300000, "ASSETS", 1, 0, "S"),
            (300100, "BANKS", 2, 0, "S"),
            (300101, "BANK", 0, 12_345, " "),
            (400000, "INCOME", 1, 0, "A"),
            (400001, "SALES", 0, -12_345, " "),
        ] {
            var record = Record(ChartOfAccounts.layout)
            record.setInt("code", Int64(code))
            record["name"] = name
            record["placement"] = placement
            record.setInt("level", Int64(level))
            record.setInt("balance", Int64(balance))
            XCTAssertEqual(ledger.write(record), "00")
        }
        let original = ledger.allRecords().map(\.bytes)
        let report = try FinancialStatements(context).generateReport()
        let totals = IndexedFile(store, path: FinancialStatements.path, layout: FinancialStatements.layout, keyLength: 9)
        XCTAssertEqual(totals.allRecords().map { $0.int("balance") }, [-12_345, 12_345])
        XCTAssertEqual(totals.allRecords().map { $0.int("last") }, [0, 0])
        XCTAssertEqual(ledger.allRecords().map(\.bytes), original)
        XCTAssertEqual(store.readRaw(CompanySetup.reportPath), report)
        XCTAssertTrue(report.split(separator: 10).allSatisfy { $0.count == 132 })
        XCTAssertTrue(String(decoding: report, as: UTF8.self).contains("23/11/2026"))
    }
}
