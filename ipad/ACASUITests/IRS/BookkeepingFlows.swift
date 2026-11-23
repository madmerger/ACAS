import XCTest

final class BookkeepingFlows: XCTestCase {
    @MainActor
    func testRegisterAccountAndDisplayIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixture = Data("""
        {"id":"簡易記帳動作確認","title":"勘定科目の登録と照会","workflow":"irs.flow",
         "dateSeconds":1795407349,"changes":[],"reports":{}}
        """.utf8)
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        tap(app, "section.incomplete")
        tap(app, "irs.accounts")
        tap(app, "irs.accountCreate")
        enter(app, "irs.accountCode", "30001")
        enter(app, "irs.accountName", "BANK")
        tap(app, "irs.saveAccount")
        let result = app.staticTexts["irs.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "勘定科目を保存しました。")

        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "irs.accountList")
        XCTAssertTrue(app.staticTexts["BANK"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }

    @MainActor
    private func enter(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        field.tap()
        field.typeText(text)
    }
}
