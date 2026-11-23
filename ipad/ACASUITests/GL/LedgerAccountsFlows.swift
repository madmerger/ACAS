import XCTest

final class LedgerAccountsFlows: XCTestCase {
    @MainActor
    func testGL020() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GL-020", withExtension: "json", subdirectory: "fixtures"))
        let fixture = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        let values = try XCTUnwrap(object["input"] as? [String: Any])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts["GL-020"].waitForExistence(timeout: 10))
        tap(app, "section.general")
        tap(app, "gl.confirm-date")
        tap(app, "gl.accounts")
        tap(app, "gl.accounts.add")
        try fill(app, "gl.account.code", values["account"])
        try fill(app, "gl.account.name", values["name"])
        try fill(app, "gl.account.placement", values["placement"])
        tap(app, "gl.account.save")
        XCTAssertTrue(app.staticTexts["勘定科目を保存しました"].waitForExistence(timeout: 5))
        let verdict = app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "GL-020"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(verdict)
    }

    @MainActor
    private func fill(_ app: XCUIApplication, _ id: String, _ value: Any?) throws {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        field.tap()
        field.typeText(try XCTUnwrap(value as? String))
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }
}
