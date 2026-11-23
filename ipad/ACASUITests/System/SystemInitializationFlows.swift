import XCTest

final class SystemInitializationFlows: XCTestCase {
    @MainActor
    func testSYS001FromEmptyDatabase() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SYS-001", withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "system.company")
        enter(app, "system.company.name", "EQUIVALENCE BUSINESS")
        group(app, "modules") {
            for key in ["level-1", "level-2", "level-3", "full-invoicing", "level-4"] { flag(app, key, true) }
        }
        group(app, "company") {
            for (key, value) in [
                ("address-1", "Test Street"), ("post-code", "TEST1"), ("country", "UK"),
                ("start-date", "2026/1/1"), ("end-date", "2026/12/31"), ("vat-rate-1", "20.00"),
                ("vat-rate-2", "5.00"), ("current-quarter", "1"), ("vat-reg-number", "TESTVAT"),
            ] { enter(app, "system.settings." + key, value) }
            flag(app, "sl-vat-printed", true)
            flag(app, "sl-vat-printed", false)
            enter(app, "system.settings.scycle", "1")
        }
        group(app, "operations") {
            let path = "/home/ubuntu/work/acas-equiv/runtime/ledgers/"
            for (key, value) in [
                ("op-system", "6"), ("print-spool-name", "CAPTURE"), ("print-spool-name2", "CAPTURE"),
                ("print-spool-name3", "CAPTURE"), ("archive-incomplete", path + "IRS/"), ("archive-ledgers", path + "ACAS/"),
            ] { enter(app, "system.settings." + key, value) }
        }
        group(app, "general") {
            flag(app, "m-v", true)
            flag(app, "vat", true)
            flag(app, "irs-instead", true)
            flag(app, "irs-instead", false)
        }
        group(app, "sales") {
            flag(app, "sl-dunning", false)
            flag(app, "sl-charges", false)
            enter(app, "system.settings.sl-limit", "10000")
            for (key, value) in [("first-sl-batch", "1"), ("sl-pay-ac", "300001"),
                                 ("sl-sales-ac", "400001"), ("s-debtors", "300002")] {
                enter(app, "system.settings." + key, value)
            }
            for key in ["sl-stock-link", "sl-comp-head-inv", "sl-comp-head-stat", "sl-comp-head-lets", "sl-comp-head-pick"] {
                flag(app, key, true)
            }
        }
        group(app, "purchases") {
            enter(app, "system.settings.pl-delim", "\\")
            flag(app, "pl-stock-link", true)
            for (key, value) in [("bl-next-batch", "1"), ("bl-pay-ac", "300001"),
                                 ("bl-purch-ac", "500001"), ("p-creditors", "300003")] {
                enter(app, "system.settings." + key, value)
            }
        }
        group(app, "stock") {
            flag(app, "stk-audit-used", true)
            flag(app, "stk-mov-audit", true)
            enter(app, "system.settings.stk-period-cur", "M")
            enter(app, "system.settings.stk-period-dat", "Y")
            flag(app, "stk-averaging", true)
        }
        tap(app, "action.save")
        XCTAssertTrue(app.staticTexts["会社設定を保存しました"].waitForExistence(timeout: 5))
        tap(app, "system.settings.report")
        XCTAssertTrue(app.navigationBars["設定内容の帳票"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "SYS-001 設定帳票")
        tap(app, "閉じる")

        tap(app, "section.general")
        tap(app, "gl.confirm-date")
        tap(app, "gl.accounts")
        for (code, name, placement) in [
            ("300000", "ASSETS", "S"), ("300001", "BANK", ""), ("300002", "DEBTORS", ""), ("300003", "CREDITORS", ""),
            ("400000", "INCOME", "A"), ("400001", "SALES", ""), ("500000", "COSTS", "B"), ("500001", "PURCHASES", ""),
            ("600000", "VAT", "S"), ("600001", "VAT INPUT", ""), ("600002", "VAT OUTPUT", ""),
        ] {
            tap(app, "gl.accounts.add")
            enter(app, "gl.account.code", code, submit: false)
            enter(app, "gl.account.name", name, submit: false)
            if !placement.isEmpty { enter(app, "gl.account.placement", placement, submit: false) }
            tap(app, "gl.account.save")
            XCTAssertTrue(app.staticTexts["勘定科目を保存しました"].waitForExistence(timeout: 5), code)
            back(app)
            if code == "300000" {
                tap(app, "gl.accounts.edit")
                tap(app, "gl.accounts.edit.30000000")
                tap(app, "gl.account.save")
                XCTAssertTrue(app.buttons["gl.accounts.edit.30000000"].waitForExistence(timeout: 5))
                back(app)
            }
        }
        tap(app, "section.system")
        try MasterSetupFlows.registerMasters(app)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        saveScreenshot(app, name: "SYS-001 一致")
    }

    @MainActor
    private func group(_ app: XCUIApplication, _ group: String, work: () -> Void) {
        tap(app, "system.settings." + group)
        work()
        back(app)
    }

    @MainActor
    private func enter(_ app: XCUIApplication, _ id: String, _ value: String, submit: Bool = true) {
        let field = app.textFields[id]
        reveal(field, app: app)
        field.tap()
        if let previous = field.value as? String, previous != field.placeholderValue, !previous.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(value + (submit ? "\n" : ""))
    }

    @MainActor
    private func flag(_ app: XCUIApplication, _ key: String, _ enabled: Bool) {
        let id = "system.settings." + key
        let toggle = app.switches[id]
        reveal(toggle, app: app)
        let desired = enabled ? "1" : "0"
        if toggle.value as? String != desired {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, desired, id)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let item = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(item, app: app)
        item.tap()
    }

    @MainActor
    private func reveal(_ item: XCUIElement, app: XCUIApplication) {
        if item.isHittable { return }
        let scroll = app.collectionViews.firstMatch
        let surface = scroll.exists ? scroll : app
        for _ in 0..<3 where !item.isHittable { surface.swipeUp() }
        for _ in 0..<3 where !item.isHittable { surface.swipeDown() }
        XCTAssertTrue(item.isHittable, item.debugDescription)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
    }

    @MainActor
    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
