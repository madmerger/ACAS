import XCTest

final class SalesStatementsFlows: XCTestCase {
    @MainActor
    func testMissingOpenItemsPreventsStatementGeneration() throws {
        continueAfterFailure = false
        var system = [UInt8](repeating: 0, count: 1024)
        system[14] = 60
        let bytes = [UInt8(0), 4, 0, 0, 0, 0, 0, 0] + system
        let seed = try JSONSerialization.data(withJSONObject: [
            "files": ["ledgers/acas/system.dat": ["type": "relative", "hex": bytes.map { String(format: "%02x", $0) }.joined()]],
        ])
        let fixture = try JSONSerialization.data(withJSONObject: [
            "id": "SL-明細書試験", "title": "売掛明細ファイル欠落", "workflow": "ui-test-only",
            "dateSeconds": 1_795_440_000, "seed": seed.base64EncodedString(), "changes": [], "reports": [:],
        ])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for id in ["section.sales", "sales.date.save"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            element.tap()
        }
        let statement = app.descendants(matching: .any)["sales.statement"].firstMatch
        if !statement.exists || !statement.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(statement.waitForExistence(timeout: 5))
        statement.tap()
        let error = app.staticTexts["sales.statement.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "売掛明細のファイルがありません")
        XCTAssertFalse(app.buttons["sales.statement.generate"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "得意先明細書の必要ファイル欠落"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
