import XCTest

final class SystemCompanyDataFlows: XCTestCase {
    @MainActor
    func testSYS206() throws {
        let app = try openCompany("SYS-206")
        XCTAssertEqual(app.textFields["system.company.name"].value as? String, "EQUIVALENCE BUSINESS")
        tap(app, "system.settings.company")
        XCTAssertEqual(app.textFields["system.settings.address-1"].value as? String, "Test Street")
        XCTAssertTrue(app.textFields["system.settings.start-date"].exists)
        captureMatch(app, "SYS-206")
    }

    @MainActor
    func testSYS004() throws {
        let app = try openCompany("SYS-004")
        for (group, field) in [
            ("modules", "level-1"), ("company", "address-1"), ("general", "p-c"),
            ("sales", "sl-credit"), ("purchases", "pl-delim"), ("stock", "stk-debug")
        ] {
            tap(app, "system.settings." + group)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "system.settings." + field)
                .firstMatch.waitForExistence(timeout: 5))
            back(app)
        }
        checkReport(app, id: "SYS-004")
    }

    @MainActor
    func testSYS005() throws {
        try checkNumber("SYS-005", "page-lines", input: "028", display: "48",
                        message: "29行以上を指定してください。48行に戻しました。")
    }

    @MainActor
    func testSYS006() throws {
        try checkNumber("SYS-006", "page-lines", input: "029", display: "29")
    }

    @MainActor
    func testSYS007() throws {
        try checkNumber("SYS-007", "period", input: "13", display: "13", message: "週次")
    }

    @MainActor
    func testSYS008() throws {
        try checkNumber("SYS-008", "period", input: "06", display: "06", message: "隔週")
    }

    @MainActor
    func testSYS009() throws {
        try checkNumber("SYS-009", "period", input: "99", display: "99", message: "月次")
    }

    @MainActor
    func testSYS010() throws {
        let app = try openCompany("SYS-010")
        tap(app, "system.settings.sales")
        let link = app.switches["system.settings.sl-stock-link"]
        let form = app.collectionViews.containing(.switch, identifier: "system.settings.sl-dunning").firstMatch
        for _ in 0..<3 where !link.isHittable { form.swipeUp() }
        XCTAssertTrue(link.isHittable)
        XCTAssertEqual(link.value as? String, "1")
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(link.value as? String, "0")
        back(app)
        checkReport(app, id: "SYS-010")
    }

    @MainActor
    private func checkReport(_ app: XCUIApplication, id: String) {
        tap(app, "system.settings.operations")
        let root = "/home/ubuntu/work/acas-equiv/runtime/ledgers/"
        for (field, suffix) in [("archive-incomplete", "IRS/"), ("archive-ledgers", "ACAS/")] {
            let input = app.textFields["system.settings." + field]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.tap()
            input.typeText(root + suffix)
            XCTAssertEqual(input.value as? String, root + suffix)
        }
        back(app)
        tap(app, "action.save")
        let report = app.buttons["system.settings.report"]
        let form = app.collectionViews.containing(.textField, identifier: "system.company.name").firstMatch
        for _ in 0..<3 where !report.isHittable { form.swipeUp() }
        if !report.exists {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(id) 帳票ボタン未表示"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].exists)
        tap(app, "system.settings.report")
        XCTAssertTrue(app.navigationBars["設定内容の帳票"].waitForExistence(timeout: 5))
        captureMatch(app, id)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
    }

    @MainActor
    private func checkNumber(_ id: String, _ setting: String, input: String, display: String, message: String? = nil) throws {
        let app = try openCompany(id)
        tap(app, "system.settings.company")
        let field = app.textFields["system.settings." + setting]
        let form = app.collectionViews.containing(.textField, identifier: "system.settings.address-1").firstMatch
        for _ in 0..<3 where !field.isHittable { form.swipeUp() }
        XCTAssertTrue(field.isHittable)
        field.tap()
        let original = try XCTUnwrap(field.value as? String)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + input + "\n")
        if let message {
            let label = app.staticTexts[message]
            for _ in 0..<3 where !label.isHittable { form.swipeUp() }
            XCTAssertTrue(label.exists)
        }
        XCTAssertEqual(field.value as? String, display)
        captureMatch(app, id)
    }

    @MainActor
    func testSYS002() throws {
        let app = try openCompany("SYS-002")
        XCTAssertEqual(app.textFields["system.company.name"].value as? String, "EQUIVALENCE BUSINESS")
        tap(app, "system.settings.company")
        let address = app.textFields["system.settings.address-1"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(address.value as? String, "Test Street")
        captureMatch(app, "SYS-002")
    }

    @MainActor
    func testSYS003() throws {
        let app = try openCompany("SYS-003")
        let name = app.textFields["system.company.name"]
        let original = try XCTUnwrap(name.value as? String)
        name.tap()
        name.typeText(" DRAFT\n")
        XCTAssertEqual(name.value as? String, original + " DRAFT")
        tap(app, "system.company.cancel")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "system.master").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["system.company.name"].exists)
        tap(app, "system.company")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, original)
        captureMatch(app, "SYS-003")
    }

    @MainActor
    private func openCompany(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "section.system")
        tap(app, "system.company")
        XCTAssertTrue(app.textFields["system.company.name"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }

    @MainActor
    private func captureMatch(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
