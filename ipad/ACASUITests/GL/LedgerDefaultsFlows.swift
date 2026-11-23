import XCTest

final class LedgerDefaultsFlows: XCTestCase {
    @MainActor
    func testGL040() throws {
        let app = try saveDefault("GL-040")
        XCTAssertTrue(app.buttons["gl.defaults.entry.1"].staticTexts["300001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gl.defaults.entry.1"].staticTexts["BK"].exists)
        captureMatch(app, "GL-040")
    }

    @MainActor
    func testGL041() throws {
        let app = try saveDefault("GL-041")
        XCTAssertTrue(app.staticTexts["指定コードに対応する勘定科目が見つかりません。既定値には入力したコードが記録されました。"]
            .waitForExistence(timeout: 5))
        captureMatch(app, "GL-041")
    }

    @MainActor
    func testGL042() throws {
        let (app, _) = try openMenu("GL-042")
        tap(app, "gl.defaults.list")
        XCTAssertTrue(app.staticTexts["未設定"].firstMatch.waitForExistence(timeout: 5))
        captureMatch(app, "GL-042")
    }

    @MainActor
    func testGL207() throws {
        let (app, _) = try openMenu("GL-207")
        for action in ["add", "edit", "list"] { XCTAssertTrue(app.buttons["gl.defaults." + action].exists) }
        captureMatch(app, "GL-207")
    }

    @MainActor
    private func saveDefault(_ id: String) throws -> XCUIApplication {
        let (app, input) = try openMenu(id)
        let entry = try XCTUnwrap(input["entry"] as? Int)
        let account = try XCTUnwrap(input["account"] as? String)
        tap(app, "gl.defaults.edit")
        tap(app, "gl.defaults.entry.\(entry)")
        let accountField = app.textFields["gl.defaults.account"]
        let previous = try XCTUnwrap(accountField.value as? String)
        accountField.tap()
        accountField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + account)
        XCTAssertEqual(accountField.value as? String, account)
        let codeField = app.textFields["gl.defaults.code"]
        codeField.tap()
        if let code = input["transactionCode"] as? String { codeField.typeText(code) }
        tap(app, "gl.defaults.save")
        return app
    }

    @MainActor
    private func openMenu(_ id: String) throws -> (XCUIApplication, [String: Any]) {
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
        for action in ["section.general", "gl.confirm-date", "gl.defaults"] { tap(app, action) }
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
