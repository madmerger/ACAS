import XCTest

final class SalesPeriodFlows: XCTestCase {
    @MainActor
    func testRequiresBackupAcknowledgementBeforePeriodClose() throws {
        continueAfterFailure = false
        var system = [UInt8](repeating: 0, count: 1024)
        system[14] = 60
        system[275 + 14] = 0x31
        let bytes = [UInt8(0), 4, 0, 0, 0, 0, 0, 0] + system
        let seed = try JSONSerialization.data(withJSONObject: [
            "files": ["ledgers/acas/system.dat": ["type": "relative", "hex": bytes.map { String(format: "%02x", $0) }.joined()]],
        ])
        let fixture = try JSONSerialization.data(withJSONObject: [
            "id": "SL-239", "title": "期間締めのバックアップ確認", "workflow": "ui-test-only",
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
        let period = app.descendants(matching: .any)["sales.period"].firstMatch
        if !period.exists || !period.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.81))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        period.tap()
        XCTAssertTrue(app.staticTexts["sales.period.notice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sales.period.execute"].exists)
        let backup = app.switches["sales.period.backedUp"]
        XCTAssertTrue(backup.exists)
        XCTAssertEqual(backup.value as? String, "0")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "期間締めのバックアップ確認"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        backup.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertEqual(backup.value as? String, "1")
        let error = app.staticTexts["sales.period.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "売掛明細のファイルがありません")
    }
}
