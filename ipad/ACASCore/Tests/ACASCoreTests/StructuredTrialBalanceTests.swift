import XCTest
@testable import ACASCore

final class StructuredTrialBalanceTests: XCTestCase {
    func testDetailAndHeadingRollUpToTheNetTotal() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try setup.save(settings)
        try GeneralLedgerSetup(context).start(year: 2026, month: 11, day: 23)
        let ledger = IndexedFile(store, path: ChartOfAccounts.path, layout: ChartOfAccounts.layout, keyLength: 8)
        ledger.openOutput()
        for (code, level, balance) in [(300000, 1, 0), (300001, 0, 12_345), (300002, 0, -2_345)] {
            var record = Record(ChartOfAccounts.layout)
            record.setInt("code", Int64(code))
            record.setInt("level", Int64(level))
            record.setInt("balance", Int64(balance))
            XCTAssertEqual(ledger.write(record), "00")
        }
        try StructuredTrialBalance(context).generateReport()
        let report = try XCTUnwrap(store.readRaw(CompanySetup.reportPath))
        let lines = report.split(separator: 10).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count == 132 })
        XCTAssertTrue(lines.contains { $0.hasPrefix("    3000.01") && $0.contains("123.45") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("    3000.02") && $0.contains("23.45") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("3000.00") && $0.contains("100.00") })
        XCTAssertTrue(lines.contains { $0.contains("t o t a l") && $0.contains("100.00") })
    }
}
