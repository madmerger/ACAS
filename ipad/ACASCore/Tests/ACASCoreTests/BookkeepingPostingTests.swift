import Foundation
import XCTest
@testable import ACASCore

final class BookkeepingPostingTests: XCTestCase {
    func testDefaultBalanceCarriesForwardAndRecalculationResolvesSubaccount() throws {
        let store = try FileStore()
        let service = BookkeepingService(BusinessContext(store: store))
        try service.saveAccount(code: 10001, name: "既定", category: .assets, editing: false)
        try service.saveAccount(code: 20001, name: "親", category: .expense, editing: false)
        try service.saveAccount(code: 20001, child: 20002, name: "補助", category: .expense, editing: false)
        try service.saveDefault(slot: 1, account: 10001, label: "BK", usesTax: false)
        for amount: Int64 in [100, 200] {
            try service.post(defaultSlot: 1, side: .debit, account: 20002, date: service.today,
                             amount: amount, description: "転記")
        }
        XCTAssertEqual(try service.accountRecord(10001).int("dr"), 300)
        XCTAssertEqual(try service.accountRecord(20001, 20002).int("cr"), 300)
        try service.recalculate()
        XCTAssertEqual(try service.accountRecord(20001, 20002).int("cr"), 300)
        XCTAssertEqual(try service.accountRecord(20002).int("cr"), 0)
    }
}
