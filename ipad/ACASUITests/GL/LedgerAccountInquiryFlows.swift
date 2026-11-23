import XCTest

final class LedgerAccountInquiryFlows: XCTestCase {
    @MainActor
    func testGL023() throws {
        let app = try openInquiry("GL-023")
        let code = app.textFields["gl.accounts.start"]
        code.tap()
        code.typeText("300000")
        tap(app, "gl.accounts.search")
        XCTAssertTrue(app.staticTexts["ASSETS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["300000"].exists)
        captureMatch(app, "GL-023")
    }

    @MainActor
    func testGL205() throws {
        let app = try openInquiry("GL-205")
        XCTAssertTrue(app.textFields["gl.accounts.start"].exists)
        XCTAssertFalse(app.staticTexts["ASSETS"].exists)
        captureMatch(app, "GL-205")
    }

    @MainActor
    private func openInquiry(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for identifier in ["section.general", "gl.confirm-date", "gl.accounts", "gl.accounts.list"] {
            tap(app, identifier)
        }
        XCTAssertTrue(app.textFields["gl.accounts.start"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
        button.tap()
    }

    @MainActor
    private func captureMatch(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
