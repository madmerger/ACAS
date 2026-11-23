import XCTest

final class SalesCustomersFlows: XCTestCase {
    private let fixtureIDs = ["SL-206", "SL-400", "SL-401", "SL-402", "SL-403"]

    @MainActor
    func testSL018() throws { try reportConditions("SL-018", operation: "alphabetical", title: "得意先名称順一覧") }

    @MainActor
    func testSL019() throws { try reportConditions("SL-019", operation: "turnover", title: "得意先別売上高表") }

    @MainActor
    func testSL228() throws { try reportConditions("SL-228", operation: "alphabetical", title: "得意先名称順一覧") }

    @MainActor
    func testSL229() throws { try reportConditions("SL-229", operation: "turnover", title: "得意先別売上高表") }

    @MainActor
    func testEmptyCreditDaysRejectsSave() throws {
        try assertInvalidTerms(fieldID: "sales.customer.creditDays", replacement: "")
    }

    @MainActor
    func testDiscountWithThirdDecimalRejectsSave() throws {
        try assertInvalidTerms(fieldID: "sales.customer.discount", replacement: "5.129")
    }

    @MainActor
    func testChangingLookupCodeDiscardsEditSelection() throws {
        let (app, input) = try launch("SL-400", operation: "edit")
        let code = app.textFields["sales.customer.code"]
        enter(input["code"], in: code)
        tap("sales.customer.search", in: app)
        let save = app.buttons["sales.customer.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        code.tap()
        code.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(code.value as? String, input["code"].map { String($0.dropLast()) })
    }

    @MainActor
    func testSL206() throws {
        let (app, _) = try launch("SL-206", operation: "report")
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["抽出条件"].exists)
        let criteria = XCTAttachment(screenshot: app.screenshot())
        criteria.name = "SL-206-抽出条件"
        criteria.lifetime = .keepAlways
        add(criteria)

        tap("sales.customer.report.generate", in: app)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "SL-206-帳票プレビュー"
        preview.lifetime = .keepAlways
        add(preview)
        let first = app.descendants(matching: .any)["sales.customer.report.row.CUST011"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["sales.customer.report.row.CUST020"].exists)
        XCTAssertTrue(app.buttons["sales.customer.report.export"].isHittable)
    }

    @MainActor
    func testSL400() throws {
        let (app, input) = try launch("SL-400", operation: "edit")
        enter(input["code"], in: app.textFields["sales.customer.code"])
        tap("sales.customer.search", in: app)
        let name = app.textFields["sales.customer.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let old = try XCTUnwrap(name.value as? String)
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + (input["name"] ?? ""))
        tap("sales.customer.save", in: app)
        finish(app, "SL-400", result: "得意先を更新しました")
    }

    @MainActor
    func testSL401() throws {
        let (app, input) = try launch("SL-401", operation: "remove")
        enter(input["code"], in: app.textFields["sales.customer.code"])
        tap("sales.customer.search", in: app)
        let name = app.descendants(matching: .any).matching(identifier: "sales.customer.summary.name").firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "BETA CUSTOMER")
        tap("sales.customer.delete", in: app)
        tap("sales.customer.confirmDelete", in: app)
        finish(app, "SL-401", result: "得意先を削除しました")
    }

    @MainActor
    func testSL402() throws {
        let (app, input) = try launch("SL-402", operation: "view")
        enter(input["code"], in: app.textFields["sales.customer.code"])
        tap("sales.customer.search", in: app)
        finish(app, "SL-402", result: "指定した得意先は登録されていません")
    }

    @MainActor
    func testSL403() throws {
        let (app, input) = try launch("SL-403", operation: "register")
        enter(input["code"], in: app.textFields["sales.customer.code"])
        enter(input["name"], in: app.textFields["sales.customer.name"])
        enter(input["address"], in: app.textFields["sales.customer.address1"])
        tap("sales.customer.save", in: app)
        finish(app, "SL-403", result: "得意先を登録しました：TEST011")
    }

    @MainActor
    private func reportConditions(_ id: String, operation: String, title: String) throws {
        let app = try launchCase(id)
        let report = app.descendants(matching: .any)["sales.customer." + operation].firstMatch
        if !report.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        try XCTUnwrap(report.exists && report.isHittable ? report : nil).tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["抽出条件"].exists)
        XCTAssertTrue(app.buttons["sales.customer.report.generate"].exists)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launch(_ id: String, operation: String) throws -> (XCUIApplication, [String: String]) {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let fixtures = fixtureIDs.compactMap { bundle.url(forResource: $0, withExtension: "json", subdirectory: "fixtures") }
        try XCTSkipIf(fixtures.isEmpty, "得意先の証跡テストは generate_customer_fixtures.py <証跡ディレクトリ> --simulator <端末ID> で実行してください")
        let url = try XCTUnwrap(bundle.url(forResource: id, withExtension: "json", subdirectory: "fixtures"), "\(id) の証跡がありません")
        let data = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(fixture["input"] as? [String: String])
        let app = launchCase(id, data: data)
        tap("sales.customers", in: app)
        tap("sales.customer." + operation, in: app)
        return (app, input)
    }

    @MainActor
    private func launchCase(_ id: String) throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "fixtures")
        try XCTSkipIf(url == nil, "得意先の証跡テストは generate_customer_fixtures.py で準備してください")
        return try launchCase(id, data: Data(contentsOf: XCTUnwrap(url)))
    }

    @MainActor
    private func launchCase(_ id: String, data: Data) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        tap("section.sales", in: app)
        tap("sales.date.save", in: app)
        return app
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        XCTAssertTrue(button.isHittable, id)
        button.tap()
    }

    @MainActor
    private func enter(_ input: String?, in field: XCUIElement) {
        guard let input else { return XCTFail("入力データがありません") }
        XCTAssertTrue(field.waitForExistence(timeout: 5), field.debugDescription)
        field.tap()
        field.typeText(input)
    }

    @MainActor
    private func assertInvalidTerms(fieldID: String, replacement: String) throws {
        let (app, input) = try launch("SL-400", operation: "edit")
        enter(input["code"], in: app.textFields["sales.customer.code"])
        tap("sales.customer.search", in: app)
        let field = app.textFields[fieldID]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let old = try XCTUnwrap(field.value as? String)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + replacement)
        let save = app.buttons["sales.customer.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let alert = app.alerts["取引条件の数値を指定の桁数で入力してください"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = fieldID
        proof.lifetime = .keepAlways
        add(proof)
    }

    @MainActor
    private func finish(_ app: XCUIApplication, _ id: String, result: String) {
        let label = app.staticTexts["sales.customer.result"]
        let found = label.waitForExistence(timeout: 5)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertTrue(found, id)
        XCTAssertEqual(label.label, result)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].exists, id + " のレコード差分が異なります")
    }
}
