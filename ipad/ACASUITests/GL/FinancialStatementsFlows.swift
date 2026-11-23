import XCTest

final class FinancialStatementsFlows: XCTestCase {
    @MainActor func testGL010() throws { try checkDate("GL-010") }
    @MainActor func testGL227() throws { try checkDate("GL-227") }

    @MainActor
    func testGL035() throws {
        let (app, _) = try openStatements("GL-035")
        tap(app, "gl.financial-statements.prepare")
        tap(app, "gl.financial-statements.print")
        XCTAssertTrue(app.buttons["gl.report.share"].waitForExistence(timeout: 5))
        captureMatch(app, "GL-035")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["gl.financial-statements"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func checkDate(_ id: String) throws {
        let (app, input) = try openStatements(id)
        let date = app.staticTexts["gl.financial-statements.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertEqual(date.label, try XCTUnwrap(input["statementDate"] as? String))
        XCTAssertFalse(app.buttons["gl.report.share"].exists)
        captureMatch(app, id)
    }

    @MainActor
    private func openStatements(_ id: String) throws -> (XCUIApplication, [String: Any]) {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                           subdirectory: "fixtures"))
        let fixture = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [String: Any])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for step in ["section.general", "gl.confirm-date", "gl.financial-statements"] { tap(app, step) }
        return (app, input)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
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
