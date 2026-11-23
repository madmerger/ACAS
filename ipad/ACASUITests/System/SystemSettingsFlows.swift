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
        tap(app, "system.settings.confirm-save")
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].waitForExistence(timeout: 5))
        tap(app, "system.settings.report")
        XCTAssertTrue(app.navigationBars["設定内容の帳票"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "システム設定帳票プレビュー"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testResumeInitialSettingsAndSaveWithoutReport() throws {
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
        name.typeText("TEST COMPANY\n")
        tap(app, "system.settings.company")
        let address = app.textFields["system.settings.address-1"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("Test Street")
        XCTAssertEqual(address.value as? String, "Test Street")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "action.save")
        let confirmation = app.staticTexts["system.settings.confirm-report"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))

        let includeReport = app.switches["system.settings.include-report"]
        XCTAssertEqual(includeReport.value as? String, "1")
        includeReport.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: includeReport)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["system.company"].waitForExistence(timeout: 5))
        tap(app, "system.company")
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(includeReport.value as? String, "0")
        tap(app, "system.settings.confirm-save")
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["system.settings.report"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "system.company")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "TEST COMPANY")
        tap(app, "system.settings.company")
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(address.value as? String, "Test Street")
    }

    @MainActor
    func testConfirmInitialSettingsAfterRegisteringCustomer() throws {
        let app = try openInitialCompany()
        app.textFields["system.company.name"].tap()
        app.textFields["system.company.name"].typeText("TEST COMPANY\n")
        tap(app, "action.save")
        XCTAssertTrue(app.staticTexts["system.settings.confirm-report"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        tap(app, "system.master")
        tap(app, "system.master.customer")
        for (field, value) in [("code", "CUST01"), ("name", "ALPHA CUSTOMER")] {
            let input = app.textFields["system.master.field." + field]
            input.tap()
            input.typeText(value + "\n")
        }
        tap(app, "system.master.save")
        XCTAssertTrue(app.staticTexts["マスタを登録しました"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "system.company")
        tap(app, "system.settings.confirm-save")
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRejectInvalidReportPathBeforeInitialConfirmation() throws {
        let app = try openInitialCompany()
        app.textFields["system.company.name"].tap()
        app.textFields["system.company.name"].typeText("TEST COMPANY\n")
        tap(app, "system.settings.operations")
        let path = app.textFields["system.settings.archive-incomplete"]
        path.tap()
        let invalidPath = String(repeating: "a", count: 1025)
        path.typeText(invalidPath)
        XCTAssertEqual(path.value as? String, invalidPath)
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "action.save")
        let warning = app.alerts["入力可能な文字・数値・範囲を確認してください"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons.firstMatch.tap()
        XCTAssertFalse(app.staticTexts["system.settings.confirm-report"].exists)
        tap(app, "system.settings.operations")
        XCTAssertTrue(path.isEnabled)
    }

    @MainActor
    private func openInitialCompany() throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SYS-001", withExtension: "json",
                                                              subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "system.company")
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }
}
