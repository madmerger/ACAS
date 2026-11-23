import XCTest

final class SalesCustomersFlows: XCTestCase {
    private let fixtureIDs = ["SL-400", "SL-401", "SL-402", "SL-403"]

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
    private func launch(_ id: String, operation: String) throws -> (XCUIApplication, [String: String]) {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let fixtures = fixtureIDs.compactMap { bundle.url(forResource: $0, withExtension: "json", subdirectory: "fixtures") }
        try XCTSkipIf(fixtures.isEmpty, "得意先の証跡テストは generate_customer_fixtures.py <証跡ディレクトリ> --simulator <端末ID> で実行してください")
        let url = try XCTUnwrap(bundle.url(forResource: id, withExtension: "json", subdirectory: "fixtures"), "\(id) の証跡がありません")
        let data = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(fixture["input"] as? [String: String])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        tap("section.sales", in: app)
        tap("sales.customers", in: app)
        tap("sales.customer." + operation, in: app)
        return (app, input)
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
