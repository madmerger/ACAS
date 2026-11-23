import XCTest

final class LedgerBusinessDateFlows: XCTestCase {
    @MainActor func testGL001() throws { try checkDateMenu("GL-001", reopen: true) }
    @MainActor func testGL200() throws { try checkDateMenu("GL-200") }
    @MainActor func testGL201() throws { try checkDateMenu("GL-201", reopen: true) }
    @MainActor func testGL232() throws { try checkDateMenu("GL-232") }

    @MainActor
    func testGL036() throws {
        let app = try openLedger("GL-036")
        tap(app, "gl.confirm-date")
        tap(app, "gl.business-date")
        for (part, value) in [("year", "2026"), ("month", "2"), ("day", "31")] {
            let field = app.textFields["gl.date." + part]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let previous = try XCTUnwrap(field.value as? String)
            field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
        }
        tap(app, "gl.confirm-date")
        XCTAssertTrue(app.staticTexts["存在する日付を入力してください"].waitForExistence(timeout: 5))
        captureMatch(app, "GL-036")
    }

    @MainActor
    func testGL230() throws {
        let app = try openLedger("GL-230")
        tap(app, "gl.confirm-date")
        tap(app, "gl.close-ledger")
        XCTAssertTrue(app.buttons["system.company"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gl.confirm-date"].exists)
        captureMatch(app, "GL-230")
    }

    @MainActor
    func testGL231() throws {
        let app = try openLedger("GL-231")
        for id in ["gl.confirm-date", "gl.company-settings", "system.company", "system.settings.company"] {
            tap(app, id)
        }
        XCTAssertTrue(app.textFields["system.settings.address-1"].waitForExistence(timeout: 5))
        captureMatch(app, "GL-231")
    }

    @MainActor
    private func checkDateMenu(_ id: String, reopen: Bool = false) throws {
        let app = try openLedger(id)
        let fields = ["year", "month", "day"].map { app.textFields["gl.date." + $0] }
        let initial = try fields.map { field in
            let populated = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value MATCHES %@", "[0-9]+"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [populated], timeout: 5), .completed)
            return try XCTUnwrap(field.value as? String)
        }
        if reopen {
            XCTAssertFalse(app.staticTexts["case.verdict.match"].exists)
            tap(app, "gl.confirm-date")
            tap(app, "gl.business-date")
            for (field, value) in zip(fields, initial) {
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value),
                                                         object: field)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
            }
        }
        captureMatch(app, id)
    }

    @MainActor
    private func openLedger(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "section.general")
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let item = app.descendants(matching: .any)["\(id)"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), id)
        item.tap()
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
