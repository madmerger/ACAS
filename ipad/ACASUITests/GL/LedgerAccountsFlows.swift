import XCTest

final class LedgerAccountsFlows: XCTestCase {
    @MainActor
    func testGL024() throws {
        try checkRejected("GL-024", message: "先頭４桁が１０００以上の６桁の勘定科目コードを入力してください")
    }

    @MainActor
    func testGL025() throws {
        try checkRejected("GL-025", message: "先頭４桁が９９９９のコードは予約済みです")
    }

    @MainActor
    func testGL026() throws {
        try checkRejected("GL-026", message: "売上または仕入に予約された先頭桁は使用できません")
    }

    @MainActor
    func testGL027() throws {
        try checkRejected("GL-027", message: "売上または仕入に予約された先頭桁は使用できません")
    }

    @MainActor
    func testGL038() throws {
        try checkRejected("GL-038", message: "対応する見出し科目がありません")
    }

    @MainActor
    func testGL021() throws {
        let app = try openEditList("GL-021")
        tap(app, "gl.accounts.edit.30000000")
        let name = app.textFields["gl.account.name"]
        XCTAssertEqual(name.value as? String, "ASSETS")
        name.tap()
        name.typeText(" UPDATED")
        XCTAssertEqual(name.value as? String, "ASSETS UPDATED")
        tap(app, "gl.account.save")
        captureMatch(app, "GL-021")
    }

    @MainActor
    func testGL022() throws {
        let app = try openEditList("GL-022")
        tap(app, "gl.accounts.edit.30000100")
        tap(app, "gl.account.delete")
        tap(app, "gl.account.delete.confirm")
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let deleted = app.buttons["gl.accounts.edit.30000100"]
        let refresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: deleted)
        XCTAssertEqual(XCTWaiter.wait(for: [refresh], timeout: 5), .completed)
        captureMatch(app, "GL-022")
    }

    @MainActor
    func testGL204() throws {
        let app = try openEditList("GL-204")
        XCTAssertTrue(app.buttons["gl.accounts.edit.30000000"].waitForExistence(timeout: 5))
        captureMatch(app, "GL-204")
    }

    @MainActor
    private func checkRejected(_ id: String, message: String) throws {
        let app = try submitAccount(id)
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
        captureMatch(app, id)
    }

    @MainActor
    private func submitAccount(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                           subdirectory: "fixtures"))
        let fixture = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        let values = try XCTUnwrap(object["input"] as? [String: Any])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for step in ["section.general", "gl.confirm-date", "gl.accounts", "gl.accounts.add"] { tap(app, step) }
        try fill(app, "gl.account.code", values["account"])
        if let name = values["name"] as? String { try fill(app, "gl.account.name", name) }
        tap(app, "gl.account.save")
        return app
    }

    @MainActor
    private func openEditList(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for id in ["section.general", "gl.confirm-date", "gl.accounts", "gl.accounts.edit"] { tap(app, id) }
        return app
    }

    @MainActor
    private func captureMatch(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(id) 一致"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
