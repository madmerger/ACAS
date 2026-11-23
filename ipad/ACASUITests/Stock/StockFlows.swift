import XCTest

final class StockFlows: XCTestCase {
    @MainActor
    func testStockAuditReports() throws {
        continueAfterFailure = false
        let id = "ST-214"
        guard let url = Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures") else {
            throw XCTSkip("在庫の実画面用データを生成してください。")
        }
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        for identifier in ["section.stock", "stock.confirmDate", "stock.movements", "stock.audit", "stock.generateAudit"] {
            tap(app, identifier)
        }
        let matches = app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(matches, id + " の監査帳票原本が一致しません")
    }

    @MainActor
    func testRegisterAndReceive() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixture = Data("""
        {"id":"在庫動作確認","title":"新品目の登録と入庫","workflow":"stock.flow",
         "dateSeconds":1795407349,"changes":[],"reports":{}}
        """.utf8)
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        tap(app, "section.stock")
        tap(app, "stock.confirmDate")
        tap(app, "stock.master")
        tap(app, "stock.create")
        enter(app, "stock.code", "ITEM001")
        enter(app, "stock.abbreviation", "ITEM")
        enter(app, "stock.name", "Test item")
        tap(app, "stock.action")
        let result = app.staticTexts["stock.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "品目を保存しました。")

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "stock.movements")
        tap(app, "stock.receive")
        enter(app, "stock.code", "ITEM001")
        enter(app, "stock.quantity", "2")
        enter(app, "stock.price", "5.00")
        tap(app, "stock.action")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "在庫数：2")
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }

    @MainActor
    private func enter(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        field.tap()
        field.typeText(text)
    }
}
