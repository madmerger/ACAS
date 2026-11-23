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
    func testReachIRS001() throws { try verifyConfigurationAccess("IRS-001") }

    @MainActor
    func testReachIRS002() throws { try verifyAccounts("IRS-002") }

    @MainActor
    func testReachIRS003() throws { try verifyDefaults("IRS-003") }

    @MainActor
    func testMissingPostingIRS008() throws { try verifyMissingPosting("IRS-008", destination: "amendment") }

    @MainActor
    func testMissingPostingIRS009() throws { try verifyMissingPosting("IRS-009", destination: "analysis") }

    @MainActor
    func testMissingPostingIRS219() throws { try verifyMissingPosting("IRS-219", destination: "amendment") }

    @MainActor
    func testMissingPostingIRS220() throws { try verifyMissingPosting("IRS-220", destination: "analysis") }

    @MainActor
    private func verifyMissingPosting(_ id: String, destination: String) throws {
        try verifyReach(id, path: [destination]) { app in
            let error = app.staticTexts["irs.openPostingError"]
            XCTAssertTrue(error.waitForExistence(timeout: 5), id)
            XCTAssertEqual(error.label, "転記ファイルがないため開けませんでした（状態コード35）。", id)
        }
    }

    @MainActor
    func testReachIRS010() throws { try verifyRecalculate("IRS-010") }

    @MainActor
    func testReachIRS200() throws {
        try verifyReach("IRS-200", path: []) { app in
            ["settings", "accounts", "defaults", "post"].forEach { expectLink(app, $0) }
        }
    }

    @MainActor
    func testReachIRS201() throws { try verifyConfigurationAccess("IRS-201") }

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
    func testReachIRS223() throws { try verifyConfigurationAccess("IRS-223") }

    @MainActor
    private func verifyConfigurationAccess(_ id: String) throws {
        try verifyReach(id, path: ["settings"]) { app in
            XCTAssertTrue(app.secureTextFields["irs.settingsPassword"].waitForExistence(timeout: 5), id)
            XCTAssertTrue(app.staticTexts["irs.processingDate"].exists, id)
            XCTAssertFalse(app.textFields["irs.operatorName"].exists, id)
        }
    }

    @MainActor
    func testCloseIRS222() throws {
        try verifyReach("IRS-222", path: []) { app in
            tap(app, "irs.close")
            XCTAssertTrue(app.staticTexts["メニューを選んでください"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["irs.close"].exists)
        }
    }

    @MainActor
    func testSaveIRS090() throws {
        struct Fixture: Decodable { let input: [String: String] }
        let id = "IRS-090"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let fields = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).input
        try verifyReach(id, path: ["settings"]) { app in
            XCTAssertFalse(app.textFields["irs.operatorName"].exists)
            tap(app, "irs.authenticateSettings")
            for name in ["operatorName", "client", "street", "city", "country", "postcode"] {
                let field = app.textFields["irs." + name]
                XCTAssertTrue(field.waitForExistence(timeout: 5), name)
                field.tap()
                field.typeText(fields[name]!)
            }
            app.swipeUp()
            for name in ["startDate", "endDate"] {
                let picker = app.datePickers["irs." + name]
                if !picker.isHittable { app.swipeUp() }
                XCTAssertTrue(picker.waitForExistence(timeout: 5), name)
                let date = fields[name]!.split(separator: "/").map { Int($0)! }
                let wheels = picker.pickerWheels
                XCTAssertEqual(wheels.count, 3, name)
                wheels.element(boundBy: 0).adjust(toPickerWheelValue: "20\(date[2])年")
                wheels.element(boundBy: 1).adjust(toPickerWheelValue: "\(date[1])月")
                wheels.element(boundBy: 2).adjust(toPickerWheelValue: "\(date[0])日")
            }
            let output = app.textFields["irs.printDestination"]
            if !output.isHittable { app.swipeUp() }
            output.tap()
            output.typeText(fields["printDestination"]!)
            if !app.buttons["irs.saveSettings"].isHittable { app.swipeUp() }
            tap(app, "irs.saveSettings")
            XCTAssertEqual(app.staticTexts["irs.result"].label, "簡易記帳設定を保存しました。")
        }
    }

    @MainActor
    func testRegisterIRS091() throws {
        struct Fixture: Decodable {
            struct Input: Decodable {
                struct Account: Decodable { let code: String; let name: String; let category: String }
                struct Default: Decodable { let slot: Int; let code: String; let label: String; let usesTax: Bool }
                let accounts: [Account]
                let defaults: [Default]
            }
            let input: Input
        }
        let id = "IRS-091"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let input = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).input
        let categories = ["R": "資産", "U": "負債", "A": "収益", "E": "費用", "C": "その他"]
        let reserved = [30: "期首残高", 31: "仕入付加価値税", 32: "売上付加価値税"]
        try verifyReach(id, path: ["accounts", "accountCreate"]) { app in
            for account in input.accounts {
                enter(app, "irs.accountCode", account.code)
                enter(app, "irs.accountName", account.name)
                tap(app, "irs.category")
                tap(app, categories[account.category]!)
                tap(app, "irs.saveAccount")
                XCTAssertEqual(app.staticTexts["irs.result"].label, "勘定科目を保存しました。")
            }
            tap(app, "section.system")
            tap(app, "section.incomplete")
            tap(app, "irs.defaults")
            tap(app, "irs.defaultCreate")
            for row in input.defaults {
                if row.slot != 1 {
                    tap(app, "irs.defaultSlot")
                    let title = reserved[row.slot] ?? String(row.slot)
                    let option = app.descendants(matching: .any).matching(identifier: title).firstMatch
                    for _ in 0..<6 where !option.isHittable { app.swipeUp() }
                    tap(app, title)
                }
                enter(app, "irs.defaultAccount", row.code)
                if row.slot < 30 {
                    enter(app, "irs.defaultLabel", row.label)
                    if row.usesTax { app.switches.firstMatch.tap() }
                }
                tap(app, "irs.saveDefault")
                XCTAssertEqual(app.staticTexts["irs.result"].label, "既定勘定を保存しました。")
            }
        }
    }

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
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
