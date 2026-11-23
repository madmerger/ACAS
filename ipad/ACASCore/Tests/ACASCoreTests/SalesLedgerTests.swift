import XCTest
@testable import ACASCore

final class SalesLedgerTests: XCTestCase {
    func testAddressDelimiterOnlyMatchesAtCharacterBoundary() throws {
        let store = try FileStore()
        let ledger = SalesLedger(BusinessContext(store: store))
        var system = Record(SystemLayout.layout)
        system["sl-delim"] = "\\"
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        var customer = try ledger.newCustomer()
        customer.code = "TEST01"
        customer.name = "テスト"
        customer.address1 = "ソ"
        XCTAssertThrowsError(try ledger.register(customer)) { error in
            XCTAssertEqual(error as? SalesLedger.Error, .invalidAddress)
        }
        customer.address1 = "ソ\\1\\2\\3\\4"
        let saved = try ledger.register(customer)
        XCTAssertEqual(saved.address1, customer.address1)
    }
}
