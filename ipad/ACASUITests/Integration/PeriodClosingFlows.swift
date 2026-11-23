import XCTest

final class PeriodClosingFlows: XCTestCase {
    private struct IRSFixture: Decodable {
        struct Input: Decodable {
            let client: String
            let irsDirectory: String
        }

        let input: Input
    }

    @MainActor
    func testStandaloneIRSWithIRSDirectory() throws {
        try verifyStandaloneIRS("INT-400")
    }

    @MainActor
    func testStandaloneIRSWithMainLedgerDirectory() throws {
        try verifyStandaloneIRS("INT-401")
    }

    @MainActor
    func testPurchaseInvoiceTransfer() throws {
        let id = "INT-405"
        let app = try launch(id)
        for identifier in ["section.purchases", "integration.purchasePosting", "integration.reviewPurchasePosting"] {
            tap(app, identifier)
        }
        tap(app, "integration.confirmPurchasePosting")
        let result = app.staticTexts["integration.purchaseResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("200001"))
        finish(app, id)
    }

    @MainActor
    func testSalesPeriodConfirmation() throws {
        try verifyConfirmation("INT-402", section: "section.sales", route: "integration.salesPeriod")
    }

    @MainActor
    func testPurchasePeriodConfirmation() throws {
        try verifyConfirmation("INT-403", section: "section.purchases", route: "integration.purchasePeriod")
    }

    @MainActor
    func testSalesPeriodClosing() throws {
        try verifyClosing("INT-402", section: "section.sales", route: "integration.salesPeriod")
    }

    @MainActor
    func testPurchasePeriodClosing() throws {
        try verifyClosing("INT-403", section: "section.purchases", route: "integration.purchasePeriod")
    }

    @MainActor
    private func verifyClosing(_ id: String, section: String, route: String) throws {
        let fixture = Bundle(for: Self.self).url(forResource: id + "-close", withExtension: "json", subdirectory: "fixtures")
        guard let fixture else { throw XCTSkip("期末確定までのレガシー実測証跡が必要です。") }
        let app = try launch(id, fixture: Data(contentsOf: fixture))
        for identifier in [section, route, "integration.confirmBackup", "integration.closePeriod"] {
            tap(app, identifier)
        }
        XCTAssertTrue(app.staticTexts["integration.periodResult"].waitForExistence(timeout: 5))
        finish(app, id)
    }

    @MainActor
    private func verifyConfirmation(_ id: String, section: String, route: String) throws {
        let app = try launch(id)
        for identifier in [section, route, "integration.confirmBackup"] {
            tap(app, identifier)
        }
        XCTAssertTrue(app.secureTextFields["integration.password"].waitForExistence(timeout: 5))
        finish(app, id)
    }

    @MainActor
    private func verifyStandaloneIRS(_ id: String) throws {
        let fixture = try JSONDecoder().decode(IRSFixture.self, from: fixtureData(id))
        let app = try launch(id, irsDirectory: fixture.input.irsDirectory)
        tap(app, "section.incomplete")
        tap(app, "irs.settings")
        let client = app.textFields["irs.client"]
        XCTAssertTrue(client.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(client.value as? String)
        client.tap()
        client.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + fixture.input.client)
        XCTAssertEqual(client.value as? String, fixture.input.client)
        tap(app, "irs.saveSettings")
        let result = app.staticTexts["irs.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "簡易記帳設定を保存しました。")
        finish(app, id)
    }

    private func fixtureData(_ id: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        return try Data(contentsOf: url)
    }

    @MainActor
    private func launch(_ id: String, irsDirectory: String? = nil, fixture: Data? = nil) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try (fixture ?? fixtureData(id)).base64EncodedString()
        app.launchEnvironment["ACAS_IRS"] = irsDirectory
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))

        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }

    @MainActor
    private func finish(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
