import XCTest

final class LedgerMenuReachabilityFlows: XCTestCase {
    @MainActor func testGL002() throws { try checkAccounts("GL-002") }
    @MainActor func testGL202() throws { try checkAccounts("GL-202") }

    @MainActor
    func testGL003() throws {
        try check("GL-003", path: ["gl.defaults"], buttons: ["gl.defaults.add", "gl.defaults.edit", "gl.defaults.list"])
    }

    @MainActor
    func testGL004() throws {
        try check("GL-004", path: ["gl.batches"], buttons: ["gl.batch.new"])
    }

    @MainActor
    func testGL006() throws {
        try check("GL-006", path: ["gl.batch-status"], buttons: ["gl.batch-status.display", "gl.batch-status.print"])
    }

    @MainActor
    func testGL007() throws {
        try check("GL-007", path: ["gl.posting"], buttons: ["gl.posting.run"])
    }

    @MainActor
    func testGL009() throws {
        try check("GL-009", path: ["gl.trial-balance"], buttons: ["gl.trial-balance.detail"])
    }

    @MainActor
    func testGL203() throws {
        try check("GL-203", path: ["gl.accounts", "gl.accounts.add"], buttons: ["gl.account.save"]) { app in
            XCTAssertTrue(app.textFields["gl.account.code"].exists)
            XCTAssertTrue(app.textFields["gl.account.name"].exists)
        }
    }

    @MainActor
    func testGL212() throws {
        try check("GL-212", path: ["gl.batches"], buttons: ["gl.batch.new"])
    }

    @MainActor
    func testGL213() throws {
        try check("GL-213", path: ["gl.batches", "gl.batch.new"], buttons: ["gl.batch.add-line"]) { app in
            XCTAssertTrue(app.buttons["gl.batch.default"].exists)
            XCTAssertTrue(app.buttons["gl.batch.save"].exists)
        }
    }

    @MainActor
    func testGL215() throws {
        try check("GL-215", path: ["gl.batches.maintenance", "gl.batch.amend"], buttons: []) { app in
            XCTAssertTrue(app.staticTexts["gl.batch.amend.empty"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testGL216() throws {
        try check("GL-216", path: ["gl.batches.maintenance", "gl.batch.proof.all"], buttons: []) { app in
            let status = app.staticTexts["gl.batch.proof.status"]
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertEqual(status.label, "検証対象のバッチはありません")
            XCTAssertFalse(app.buttons["gl.report.share"].exists)
        }
    }

    @MainActor
    func testGL217() throws {
        try check("GL-217", path: ["gl.batches.maintenance", "gl.batch.proof.one"], buttons: []) { app in
            XCTAssertTrue(app.staticTexts["gl.batch.proof.empty"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["gl.report.share"].exists)
        }
    }

    @MainActor
    private func checkAccounts(_ id: String) throws {
        try check(id, path: ["gl.accounts"], buttons: [
            "gl.accounts.add", "gl.accounts.edit", "gl.accounts.list", "gl.accounts.print"
        ])
    }

    @MainActor
    private func check(_ id: String, path: [String], buttons: [String],
                       assertFields: (XCUIApplication) -> Void = { _ in }) throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                               subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for identifier in ["section.general", "gl.confirm-date"] + path {
            let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            button.tap()
        }
        for button in buttons {
            XCTAssertTrue(app.buttons[button].waitForExistence(timeout: 5), button)
        }
        assertFields(app)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
