import ACASCore
import XCTest

final class ChartOfAccountsTests: XCTestCase {
    func testLowerHeadersUseTheSameBranchLookupAsDetails() throws {
        let chart = ChartOfAccounts(BusinessContext(store: try FileStore()))
        try chart.add(code: "300000", name: "CONTROL", type: 0, placement: "S", level: 1,
                      amendScreenVisited: false)

        for (code, level) in [("310000", 2), ("311000", 3), ("311100", 4)] {
            XCTAssertThrowsError(try chart.add(code: code, name: "HEADER", type: 0, placement: "S",
                                               level: level, amendScreenVisited: false)) { error in
                guard case ChartOfAccounts.Error.missingHeader = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertNil(chart.account(code: code))
            try chart.add(code: code, name: "HEADER", type: 0, placement: "S", level: level,
                          amendScreenVisited: true)
            XCTAssertEqual(chart.account(code: code)?.level, level)
        }
    }
}
