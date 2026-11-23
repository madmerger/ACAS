@testable import ACASCore
import XCTest

final class GeneralLedgerSetupTests: XCTestCase {
    func testDefaultResetRequiresCompanyPasswordAndPreservesFiller() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        try CompanySetup(context).save(name: "TEST")
        let system = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var company = Record(SystemLayout.layout, bytes: try XCTUnwrap(system.read(1)))
        company["pass-word"] = "EZXG"
        try system.write(1, company.bytes)
        var record = [UInt8](repeating: 42, count: 1024)
        try system.write(2, record)
        let ledger = GeneralLedgerSetup(context)
        XCTAssertThrowsError(try ledger.resetDefaults(password: "ZZZZ")) { error in
            XCTAssertEqual(error as? GeneralLedgerSetup.Error, .invalidPassword)
        }
        XCTAssertEqual(system.read(2), record)
        try ledger.resetDefaults(password: "cccc")
        record.replaceSubrange(0..<231, with: SystemAuxRecords.initialDefault().prefix(231))
        XCTAssertEqual(system.read(2), record)
    }

    func testProcessingDateUsesTheConfirmedDate() throws {
        let context = BusinessContext(store: try FileStore())
        try CompanySetup(context).save(name: "TEST")
        let ledger = GeneralLedgerSetup(context)
        try ledger.start(year: 2030, month: 4, day: 12)
        let parts = context.calendar.dateComponents([.year, .month, .day], from: ledger.processingDate)
        XCTAssertEqual(parts, DateComponents(year: 2030, month: 4, day: 12))
    }
}
