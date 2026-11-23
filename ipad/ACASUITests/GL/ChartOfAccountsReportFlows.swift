import XCTest

final class ChartOfAccountsReportFlows: XCTestCase {
    @MainActor
    func testGL033() throws {
        try printReport("GL-033")
    }

    @MainActor
    func testGL206() throws {
        try printReport("GL-206")
    }

    @MainActor
    private func printReport(_ id: String) throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for identifier in ["section.general", "gl.confirm-date", "gl.accounts", "gl.accounts.print"] {
            let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            button.tap()
        }
        XCTAssertTrue(app.staticTexts["gl.accounts.print.result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
