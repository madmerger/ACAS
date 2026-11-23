import XCTest

final class TrialBalanceFlows: XCTestCase {
    @MainActor
    func testGL034() throws {
        try checkTrialBalance("GL-034", print: true)
    }

    @MainActor
    func testGL224() throws {
        try checkTrialBalance("GL-224", print: false)
    }

    @MainActor
    func testGL225() throws {
        try checkTrialBalance("GL-225", print: true)
    }

    @MainActor
    func testGL226() throws {
        try checkTrialBalance("GL-226", print: true, report: "structured")
    }

    @MainActor
    private func checkTrialBalance(_ id: String, print: Bool, report: String = "detail") throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for identifier in ["section.general", "gl.confirm-date", "gl.trial-balance"] {
            let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            button.tap()
        }
        let detail = app.buttons["gl.trial-balance.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        if print {
            app.buttons["gl.trial-balance." + report].tap()
            XCTAssertTrue(app.staticTexts["gl.trial-balance.result"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
