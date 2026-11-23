import XCTest

final class LedgerCycleCloseFlows: XCTestCase {
    @MainActor func testGL008() throws { try checkClose("GL-008") }
    @MainActor func testGL037() throws { try checkClose("GL-037", cancel: true) }
    @MainActor func testGL223() throws { try checkClose("GL-223") }

    @MainActor
    private func checkClose(_ id: String, cancel: Bool = false) throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for identifier in ["section.general", "gl.confirm-date", "gl.cycle-close"] {
            let item = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), identifier)
            item.tap()
        }
        XCTAssertTrue(app.staticTexts["実行する前に、台帳データのバックアップを確認してください。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gl.cycle-close.run"].exists)
        if cancel {
            app.buttons["gl.cycle-close.cancel"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["gl.cycle-close"].firstMatch.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
