import XCTest

final class LedgerBatchDraftFlows: XCTestCase {
    @MainActor
    func testGL045() throws {
        let (app, _) = try open("GL-045")
        tap(app, "gl.batch.exit-default")
        assertDraftClosed(app)
        finishSession(app)
        capture(app, "GL-045")
    }

    @MainActor
    func testGL046() throws {
        let (app, input) = try openDraft("GL-046")
        try fillLine(app, input)
        let date = app.datePickers["gl.batch-line-date"]
        reveal(app, date)
        XCTAssertFalse(String(describing: date.value).contains("E3"))
        XCTAssertFalse(app.staticTexts["gl.batch.error"].exists)
        capture(app, "GL-046", screenMatches: false)
    }

    @MainActor
    func testGL047() throws {
        let (app, input) = try openDraft("GL-047")
        try fillLine(app, input)
        tap(app, "gl.batch.cancel")
        assertDraftClosed(app)
        finishSession(app)
        capture(app, "GL-047")
    }

    @MainActor
    func testGL048() throws {
        let (app, _) = try openDraft("GL-048")
        tap(app, "gl.batch.save")
        let error = app.staticTexts["gl.batch.error"]
        reveal(app, error)
        XCTAssertTrue(error.label.contains("勘定科目"))
        capture(app, "GL-048")
    }

    @MainActor
    func testGL049() throws {
        let (app, input) = try openDraft("GL-049")
        try fillLine(app, input)
        XCTAssertEqual(app.textFields["gl.batch-amount"].value as? String, "0")
        XCTAssertFalse(app.staticTexts["gl.batch.error"].exists)
        capture(app, "GL-049")
    }

    @MainActor
    func testGL050() throws {
        let (app, _) = try openDraft("GL-050")
        let date = app.datePickers["gl.batch-line-date"]
        reveal(app, date)
        let before = date.value as? String
        XCTAssertNotNil(before)
        date.tap()
        app.navigationBars["新規バッチ登録"].firstMatch.tap()
        XCTAssertEqual(date.value as? String, before)
        capture(app, "GL-050")
    }

    @MainActor
    func testGL051() throws {
        let (app, _) = try openDraft("GL-051")
        let account = app.textFields["gl.account-code"]
        reveal(app, account)
        account.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture(app, "GL-051")
    }

    @MainActor
    private func open(_ id: String) throws -> (XCUIApplication, [String: Any]) {
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
        for item in ["section.general", "gl.confirm-date", "gl.batches", "gl.batch.new"] { tap(app, item) }
        return (app, input)
    }

    @MainActor
    private func openDraft(_ id: String) throws -> (XCUIApplication, [String: Any]) {
        let (app, input) = try open(id)
        tap(app, "gl.batch.default")
        tapOption(app, "33：一時既定勘定")
        tap(app, "gl.batch.direction")
        tapOption(app, "借方")
        try fill(app, "gl.batch-temp-account", input["temporaryAccount"])
        try fill(app, "gl.batch-temp-code", input["transactionCode"])
        try fill(app, "gl.batch-cycle", input["cycle"], replace: true)
        try fill(app, "gl.batch-count", input["items"])
        try fill(app, "gl.batch-gross", input["gross"])
        try fill(app, "gl.batch-description", input["memo"])
        tap(app, "gl.batch.add-line")
        return (app, input)
    }

    @MainActor
    private func fillLine(_ app: XCUIApplication, _ input: [String: Any]) throws {
        try fill(app, "gl.account-code", input["lineAccount"])
        try fill(app, "gl.batch-amount", input["lineAmount"])
        if let memo = input["lineMemo"] as? String, !memo.isEmpty { try fill(app, "gl.batch-memo", memo) }
    }

    @MainActor
    private func finishSession(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "gl.close-ledger")
        tap(app, "system.session.end")
        XCTAssertTrue(app.staticTexts["system.session.ended"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertDraftClosed(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["gl.batch.new"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["gl.batch.row.1"].firstMatch.exists)
    }

    @MainActor
    private func fill(_ app: XCUIApplication, _ id: String, _ input: Any?, replace: Bool = false) throws {
        let field = app.textFields[id]
        reveal(app, field)
        let value = try XCTUnwrap(input as? String)
        let count = replace ? (field.value as? String ?? "").count : 0
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        if app.collectionViews["gl.batch.form"].exists {
            reveal(app, element)
        } else {
            XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        }
        element.tap()
    }

    @MainActor
    private func tapOption(_ app: XCUIApplication, _ name: String) {
        let option = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), name)
        option.tap()
    }

    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        let form = app.collectionViews["gl.batch.form"]
        for _ in 0..<4 where !element.isHittable { form.swipeUp() }
        for _ in 0..<4 where !element.isHittable { form.swipeDown() }
        XCTAssertTrue(element.isHittable, element.identifier)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ id: String, screenMatches: Bool = true) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) \(screenMatches ? "一致" : "不一致（画面）")"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
