import XCTest

final class SalesPostingFlows: XCTestCase {
    @MainActor
    func testShowsMissingWorkFileWithoutPosting() throws {
        continueAfterFailure = false
        var system = [UInt8](repeating: 0, count: 1024)
        system[14] = 60
        system[275 + 14] = 0x31
        let bytes = [UInt8(0), 4, 0, 0, 0, 0, 0, 0] + system
        let seed = try JSONSerialization.data(withJSONObject: [
            "files": ["ledgers/acas/system.dat": ["type": "relative", "hex": bytes.map { String(format: "%02x", $0) }.joined()]],
        ])
        let fixture = try JSONSerialization.data(withJSONObject: [
            "id": "SL-212", "title": "売上転記：作業ファイル未作成", "workflow": "ui-test-only",
            "dateSeconds": 1_795_440_000, "seed": seed.base64EncodedString(), "changes": [], "reports": [:],
        ])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for id in ["section.sales", "sales.date.save", "sales.post"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            element.tap()
        }
        let message = app.staticTexts["sales.post.unavailable"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "売上転記に必要な作業ファイルがありません")
        XCTAssertFalse(app.buttons["sales.post.start"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "売上転記の作業ファイル未作成"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
