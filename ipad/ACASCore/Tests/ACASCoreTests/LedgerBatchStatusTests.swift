import ACASCore
import XCTest

final class LedgerBatchStatusTests: XCTestCase {
    func testEmptyCurrentCycleReport() throws {
        let context = BusinessContext(store: try FileStore())
        let company = CompanySetup(context)
        var settings = company.settings
        try settings.setText("TEST", for: "usera")
        try settings.setNumber(1, for: "scycle")
        try company.save(settings)
        try GeneralLedgerSetup(context).start(year: 2026, month: 11, day: 23)

        let report = LedgerBatchStatus(context)
        XCTAssertEqual(report.cycle, 1)
        XCTAssertTrue(report.rows.isEmpty)
        try report.generateReport()
        let lines = [
            "gl060 (3.00.04)                Batch Status Report                      Page - 1",
            "Cycle -  1                                                            23/11/2026",
            "",
            "Ledger  Batch  Status       Last                ---------Batch Controls---------",
            "------  -----  ------     Activity              Items  ---Gross---- -----VAT----",
            " ",
        ]
        let expected = lines.map { $0.isEmpty ? "" : $0.padding(toLength: 132, withPad: " ", startingAt: 0) }
            .joined(separator: "\n")
        XCTAssertEqual(expected.utf8.count, 665)
        XCTAssertEqual(context.store.readRaw(LedgerBatchStatus.reportPath), Array(expected.utf8))
    }
}
