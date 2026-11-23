import XCTest

final class SystemSettingsFlows: XCTestCase {
    @MainActor
    func testAvailableLedgerSettingsAndReportPreview() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SYS-001", withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "system.company")

        let name = app.textFields["system.company.name"]
        name.tap()
        name.typeText("TEST COMPANY")
        name.typeText("\n")
        tap(app, "system.settings.modules")
        let enableLedger = app.switches["system.settings.level-1"]
        XCTAssertTrue(enableLedger.waitForExistence(timeout: 5))
        enableLedger.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(enableLedger.value as? String, "1")
        app.navigationBars.buttons.firstMatch.tap()

        tap(app, "system.settings.general")
        XCTAssertTrue(app.staticTexts["次のバッチ番号"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "action.save")
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].waitForExistence(timeout: 5))
        tap(app, "system.settings.report")
        XCTAssertTrue(app.navigationBars["設定内容の帳票"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "システム設定帳票プレビュー"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }
}
