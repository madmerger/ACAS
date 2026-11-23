import ACASCore
import XCTest

final class ChartBranchMutationTests: XCTestCase {
    func testDisabledBranchCannotChangeOrDeleteHeadOfficeAccount() throws {
        let context = BusinessContext(store: try FileStore())
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setText("B", for: "p-c")
        try setup.save(settings)
        let chart = ChartOfAccounts(context)
        try chart.add(code: "300000", name: "Head office", type: 0, placement: "S", level: 1)
        try chart.add(code: "300000", branch: "01", name: "Branch", type: 0, placement: "S", level: 1)
        settings = setup.settings
        try settings.setText("", for: "p-c")
        try setup.save(settings)

        XCTAssertThrowsError(try chart.amend(code: "300000", branch: "01", name: "Changed",
                                              type: 0, placement: "S", level: 1))
        XCTAssertThrowsError(try chart.delete(code: "300000", branch: "01"))
        XCTAssertEqual(chart.account(code: "300000")?.name, "Head office")
        XCTAssertEqual(chart.account(code: "300000", branch: "01")?.name, "Branch")
    }
}
