import XCTest

final class BookkeepingFlows: XCTestCase {
    private struct PostingFixture: Decodable {
        struct Input: Decodable {
            let account: String
            let description: String
            let amount: String
            let defaultSide: String
        }

        let input: Input
    }

    @MainActor
    func testPostFromDefaultBankAccount() throws {
        continueAfterFailure = false
        let id = "IRS-400"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(PostingFixture.self, from: data)
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))

        tap(app, "section.incomplete")
        tap(app, "irs.post")
        let side = app.buttons["irs.postSide"]
        XCTAssertTrue(side.waitForExistence(timeout: 5))
        side.tap()
        tap(app, fixture.input.defaultSide)
        enter(app, "irs.postAccount", fixture.input.account)
        enter(app, "irs.postDescription", fixture.input.description)
        enter(app, "irs.postAmount", fixture.input.amount)
        tap(app, "irs.submitPost")

        let result = app.staticTexts["irs.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "仕訳を転記しました。")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5), id)
    }

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
