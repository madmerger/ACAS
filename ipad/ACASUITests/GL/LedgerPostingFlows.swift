import XCTest

final class LedgerPostingFlows: XCTestCase {
    @MainActor
    func testGL222() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GL-222", withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for identifier in ["section.general", "gl.confirm-date", "gl.posting"] {
            let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            button.tap()
        }
        XCTAssertTrue(app.staticTexts["バッチの確認"].exists)
        XCTAssertTrue(app.buttons["gl.posting.run"].exists)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "GL-222 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
