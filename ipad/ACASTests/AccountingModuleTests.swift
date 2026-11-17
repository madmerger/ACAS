import XCTest
@testable import ACAS

final class AccountingModuleTests: XCTestCase {
    func testModuleTitlesAndOrder() {
        XCTAssertEqual(AccountingModule.allCases.map(\.title), [
            "Sales Ledger", "Purchase Ledger", "Stock Control", "General Ledger", "IRS"
        ])
    }

    func testModuleIdentifiersAreUniqueAndStable() {
        let modules = AccountingModule.allCases
        XCTAssertEqual(Set(modules.map(\.id)).count, modules.count)
        for module in modules {
            XCTAssertEqual(AccountingModule(rawValue: module.id), module)
            XCTAssertFalse(module.title.isEmpty)
        }
    }

    func testUnknownAndEmptyModulesAreRejected() {
        XCTAssertNil(AccountingModule(rawValue: ""))
        XCTAssertNil(AccountingModule(rawValue: "Unknown"))
    }
}
