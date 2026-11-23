import ACASCore
import XCTest

final class GeneralLedgerSetupTests: XCTestCase {
    func testProcessingDateUsesTheConfirmedDate() throws {
        let context = BusinessContext(store: try FileStore())
        try CompanySetup(context).save(name: "TEST")
        let ledger = GeneralLedgerSetup(context)
        try ledger.start(year: 2030, month: 4, day: 12)
        let parts = context.calendar.dateComponents([.year, .month, .day], from: ledger.processingDate)
        XCTAssertEqual(parts, DateComponents(year: 2030, month: 4, day: 12))
    }
}
