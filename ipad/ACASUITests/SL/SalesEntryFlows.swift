import XCTest

final class SalesEntryFlows: XCTestCase {
    @MainActor
    func testSL001() throws { try check("SL-001", startup: false) }

    @MainActor
    func testSL200() throws { try check("SL-200", startup: true) }

    @MainActor
    func testSL201() throws { try check("SL-201", startup: false) }

    @MainActor
    func testSL243() throws { try check("SL-243", startup: true) }

    @MainActor
    private func check(_ id: String, startup: Bool) throws {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "fixtures")
        let startFixture = bundle.url(forResource: "SL-243", withExtension: "json", subdirectory: "fixtures")
        try XCTSkipIf(startFixture == nil && url == nil, "処理日の証跡は generate_entry_fixtures.py で生成してください")
        let data = try Data(contentsOf: XCTUnwrap(url))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        app.buttons["section.sales"].tap()
        let confirm = app.buttons["sales.date.save"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sales.customers"].exists)
        if !startup {
            confirm.tap()
            let dateEntry = app.buttons["sales.date"]
            XCTAssertTrue(dateEntry.waitForExistence(timeout: 5))
            dateEntry.tap()
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.datePickers["sales.date.value"].exists)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        if startup {
            confirm.tap()
            XCTAssertTrue(app.buttons["sales.customers"].waitForExistence(timeout: 5))
        }
    }
}
