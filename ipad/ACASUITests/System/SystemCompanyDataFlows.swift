import XCTest

final class SystemCompanyDataFlows: XCTestCase {
    @MainActor
    func testSYS002() throws {
        let app = try openCompany("SYS-002")
        XCTAssertEqual(app.textFields["system.company.name"].value as? String, "EQUIVALENCE BUSINESS")
        tap(app, "system.settings.company")
        let address = app.textFields["system.settings.address-1"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(address.value as? String, "Test Street")
        captureMatch(app, "SYS-002")
    }

    @MainActor
    func testSYS003() throws {
        let app = try openCompany("SYS-003")
        tap(app, "system.company.cancel")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "system.master").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["system.company.name"].exists)
        captureMatch(app, "SYS-003")
    }

    @MainActor
    private func openCompany(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "section.system")
        tap(app, "system.company")
        XCTAssertTrue(app.textFields["system.company.name"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
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
