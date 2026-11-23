import XCTest

final class PeriodClosingFlows: XCTestCase {
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
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let fixture = try Data(contentsOf: url)
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))

        for identifier in [section, route, "integration.confirmBackup"] {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), identifier)
            element.tap()
        }
        XCTAssertTrue(app.secureTextFields["integration.password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
