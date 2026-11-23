import XCTest

final class LedgerBatchStatusFlows: XCTestCase {
    @MainActor
    func testGL221() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GL-221", withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "section.general")
        tap(app, "gl.confirm-date")
        tap(app, "gl.batch-status")
        tap(app, "gl.batch-status.print")
        XCTAssertTrue(app.staticTexts["gl.batch-status.result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "GL-221 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }
}
