import XCTest

final class FoundationFlows: XCTestCase {
    @MainActor
    func testCALC200() throws {
        let (app, input) = try launch("CALC-200")
        tap(app, "calculation.title")
        let field = app.textFields["calculation.code"]
        field.tap()
        field.typeText(try XCTUnwrap(input["code"] as? String))
        XCTAssertEqual(app.buttons["action.calculate"].label, "計算")
        tap(app, "action.calculate")
        XCTAssertEqual(app.staticTexts["calculation.result"].label, "2")
        XCTAssertTrue(app.staticTexts["calculation.valid"].exists)
        finish(app, "CALC-200", verdict: "match")
    }

    @MainActor
    func testSL104() throws {
        let (app, _) = try launch("SL-104")
        tap(app, "section.sales")
        tap(app, "sales.proof")
        XCTAssertEqual(app.buttons["action.generate"].label, "帳票を作成")
        tap(app, "action.generate")
        XCTAssertTrue(app.staticTexts["CUST011"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ALPHA CUSTOMER"].exists)
        XCTAssertTrue(app.staticTexts["120.00"].exists)
        finish(app, "SL-104", verdict: "match")
    }

    @MainActor
    func testSL104CompactShowsAllAmounts() throws {
        let (app, _) = try launch("SL-104", compactReport: true)
        tap(app, "section.sales")
        tap(app, "sales.proof")
        tap(app, "action.generate")
        XCTAssertTrue(app.staticTexts["CUST011"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ALPHA CUSTOMER"].exists)
        for (id, amount) in [("net", "100.00"), ("tax", "20.00"), ("gross", "120.00")] {
            XCTAssertEqual(app.staticTexts["sales.proof.compact." + id].label, amount)
        }
        finish(app, "SL-104", verdict: "match")
    }

    @MainActor
    func testSYS001() throws {
        let (app, input) = try launch("SYS-001")
        tap(app, "system.company")
        let field = app.textFields["system.company.name"]
        field.tap()
        field.typeText(try XCTUnwrap(input["company"] as? String))
        XCTAssertEqual(app.buttons["action.save"].label, "保存")
        tap(app, "action.save")
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].waitForExistence(timeout: 5))
        finish(app, "SYS-001", verdict: "mismatch")
    }

    @MainActor
    private func launch(_ id: String, compactReport: Bool = false) throws -> (XCUIApplication, [String: Any]) {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [String: Any])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        if compactReport { app.launchEnvironment["ACAS_COMPACT_REPORT"] = "1" }
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        return (app, input)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        XCTAssertTrue(element.isHittable, id)
        element.tap()
    }

    @MainActor
    private func finish(_ app: XCUIApplication, _ id: String, verdict: String) {
        let result = app.staticTexts["case.verdict." + verdict]
        let found = result.waitForExistence(timeout: 5)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertTrue(found, id + " の判定が異なります")
    }
}
