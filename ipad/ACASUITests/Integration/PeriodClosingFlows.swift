import XCTest

final class PeriodClosingFlows: XCTestCase {
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
    private func verifyConfirmation(_ id: String, section: String, route: String) throws {
        let app = try launch(id)
        for identifier in [section, route, "integration.confirmBackup"] {
            tap(app, identifier)
        }
        XCTAssertTrue(app.secureTextFields["integration.password"].waitForExistence(timeout: 5))
        finish(app, id)
    }

    @MainActor
    private func launch(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let fixture = try Data(contentsOf: url)
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
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
