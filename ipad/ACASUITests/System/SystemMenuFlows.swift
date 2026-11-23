import XCTest

final class SystemMenuFlows: XCTestCase {
    @MainActor
    func testSYS200() throws {
        let app = try launch("SYS-200")
        XCTAssertTrue(app.navigationBars["会計管理"].waitForExistence(timeout: 5))
        for section in ["general", "sales", "purchases", "stock", "orders", "payroll", "retail", "system"] {
            XCTAssertTrue(app.descendants(matching: .any)["section." + section].exists, section)
        }
        captureMatch(app, "SYS-200")
    }

    @MainActor func testSYS202() throws { try checkUnavailable("SYS-202", section: "orders") }
    @MainActor func testSYS203() throws { try checkUnavailable("SYS-203", section: "payroll") }
    @MainActor func testSYS204() throws { try checkUnavailable("SYS-204", section: "retail") }

    @MainActor
    private func checkUnavailable(_ id: String, section: String) throws {
        let app = try launch(id)
        let item = app.descendants(matching: .any)["section." + section].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.staticTexts["この機能はまだ利用できません"].waitForExistence(timeout: 5))
        captureMatch(app, id)
    }

    @MainActor
    private func launch(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        return app
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
