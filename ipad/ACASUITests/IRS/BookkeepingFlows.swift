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
    func testReachIRS002() throws { try verifyAccounts("IRS-002") }

    @MainActor
    func testReachIRS003() throws { try verifyDefaults("IRS-003") }

    @MainActor
    func testReachIRS010() throws { try verifyRecalculate("IRS-010") }

    @MainActor
    func testReachIRS200() throws {
        try verifyReach("IRS-200", path: []) { app in
            ["settings", "accounts", "defaults", "post"].forEach { expectLink(app, $0) }
        }
    }

    @MainActor
    func testReachIRS202() throws { try verifyAccounts("IRS-202") }

    @MainActor
    func testReachIRS205() throws {
        try verifyReach("IRS-205", path: ["accounts", "accountList"]) { app in
            XCTAssertTrue(app.staticTexts["BANK"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testReachIRS209() throws { try verifyDefaults("IRS-209") }

    @MainActor
    func testReachIRS211() throws {
        try verifyReach("IRS-211", path: ["defaults", "defaultEdit"]) { app in
            XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "30001")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "BK")).firstMatch.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testReachIRS212() throws {
        try verifyReach("IRS-212", path: ["defaults", "defaultList"]) { app in
            XCTAssertTrue(app.staticTexts["30001"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testReachIRS221() throws { try verifyRecalculate("IRS-221") }

    @MainActor
    func testPrintIRS206() throws { try verifyReport("IRS-206", path: ["accounts", "accountPrint"]) }

    @MainActor
    func testPrintIRS213() throws { try verifyReport("IRS-213", path: ["defaults", "defaultPrint"]) }

    @MainActor
    private func verifyReport(_ id: String, path: [String]) throws {
        try verifyReach(id, path: path) { app in
            tap(app, "irs.generateReport")
            XCTAssertTrue(app.staticTexts["irs.reportResult"].waitForExistence(timeout: 5), id)
            XCTAssertEqual(app.staticTexts["irs.reportResult"].label, "帳票を作成しました。", id)
            XCTAssertTrue(app.buttons["irs.exportReport"].isHittable, id)
        }
    }

    @MainActor
    private func verifyAccounts(_ id: String) throws {
        try verifyReach(id, path: ["accounts"]) { app in
            ["accountCreate", "accountEdit", "accountList", "accountPrint", "accountExport", "accountImport"]
                .forEach { expectLink(app, $0) }
        }
    }

    @MainActor
    private func verifyDefaults(_ id: String) throws {
        try verifyReach(id, path: ["defaults"]) { app in
            ["defaultCreate", "defaultEdit", "defaultList", "defaultPrint", "statementSettings"]
                .forEach { expectLink(app, $0) }
        }
    }

    @MainActor
    private func verifyRecalculate(_ id: String) throws {
        try verifyReach(id, path: ["recalculate"]) { app in
            XCTAssertTrue(app.secureTextFields["現在のパスワード"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["元帳を再計算"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private func verifyReach(_ id: String, path: [String], assertDestination: (XCUIApplication) -> Void) throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        tap(app, "section.incomplete")
        for link in path { tap(app, "irs." + link) }
        assertDestination(app)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5), id)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func expectLink(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.descendants(matching: .any)["irs." + id].firstMatch.waitForExistence(timeout: 5), id)
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
