import XCTest

final class LedgerBatchStatusFlows: XCTestCase {
    @MainActor
    func testGL219() throws {
        let app = try openStatusMenu("GL-219")
        XCTAssertTrue(app.buttons["gl.batch-status.display"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gl.batch-status.print"].exists)
        captureMatch(app, "GL-219")
    }

    @MainActor
    func testGL220() throws {
        let app = try openStatusMenu("GL-220")
        tap(app, "gl.batch-status.display")
        let cycle = app.descendants(matching: .any).matching(identifier: "gl.batch-status.cycle").firstMatch
        XCTAssertTrue(cycle.waitForExistence(timeout: 5))
        XCTAssertTrue(cycle.label == "1" || cycle.value as? String == "1", "レガシーの現在サイクルは1")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gl.batch-status.row."))
        XCTAssertEqual(rows.count, 0)
        captureMatch(app, "GL-220")
    }

    @MainActor
    func testGL221() throws {
        let app = try openStatusMenu("GL-221")
        tap(app, "gl.batch-status.print")
        XCTAssertTrue(app.staticTexts["gl.batch-status.result"].waitForExistence(timeout: 5))
        captureMatch(app, "GL-221")
    }

    @MainActor
    private func openStatusMenu(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "section.general")
        tap(app, "gl.confirm-date")
        tap(app, "gl.batch-status")
        return app
    }

    @MainActor
    private func captureMatch(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
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
