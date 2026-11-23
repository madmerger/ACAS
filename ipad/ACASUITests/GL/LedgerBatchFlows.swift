import XCTest

final class LedgerBatchFlows: XCTestCase {
    @MainActor func testGL043() throws { try checkCycle("GL-043", error: "GL108") }
    @MainActor func testGL044() throws { try checkCycle("GL-044", error: "GL109") }

    @MainActor
    private func checkCycle(_ id: String, error: String) throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
                                                           subdirectory: "fixtures"))
        let fixture = try Data(contentsOf: url)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        let fields = try XCTUnwrap(payload["input"] as? [String: Any])
        let cycle = try XCTUnwrap(fields["cycle"] as? String)
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for id in ["section.general", "gl.confirm-date", "gl.batches", "gl.batch.new"] { tap(app, id) }
        let field = app.textFields["gl.batch-cycle"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let previous = try XCTUnwrap(field.value as? String)
        enter(app, "gl.batch-cycle", String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + cycle)
        XCTAssertEqual(field.value as? String, cycle)
        tap(app, "gl.batch.save")
        let message = app.staticTexts["gl.batch.error"]
        let form = app.collectionViews["gl.batch.form"]
        for _ in 0..<3 where !message.isHittable { form.swipeUp() }
        XCTAssertTrue(message.label.hasPrefix(error))
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(id) 一致"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRegisterJournalBatch() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GL-020", withExtension: "json",
                                                               subdirectory: "fixtures"))
        var evidence = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        let encodedSeed = try XCTUnwrap(evidence["seed"] as? String)
        let seedData = try XCTUnwrap(Data(base64Encoded: encodedSeed))
        var seed = try XCTUnwrap(JSONSerialization.jsonObject(with: seedData) as? [String: Any])
        var files = try XCTUnwrap(seed["files"] as? [String: [String: Any]])
        let systemPath = "ledgers/acas/system.dat"
        var system = try XCTUnwrap(files[systemPath])
        var systemHex = try XCTUnwrap(system["hex"] as? String)
        let recordTwo = (1024 + 8 + 8) * 2
        let account = systemHex.index(systemHex.startIndex, offsetBy: recordTwo)
        systemHex.replaceSubrange(account..<systemHex.index(account, offsetBy: 8), with: "000493e1")
        system["hex"] = systemHex
        files[systemPath] = system
        seed["files"] = files
        evidence["seed"] = try JSONSerialization.data(withJSONObject: seed).base64EncodedString()
        evidence["id"] = "GL バッチ登録確認"
        evidence["title"] = "ネイティブ画面から仕訳明細を保存"
        evidence["workflow"] = "gl-batch-smoke"
        evidence["changes"] = []
        let app = XCUIApplication()
        defer {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "仕訳バッチ登録"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app.launchEnvironment["ACAS_FIXTURE"] = try JSONSerialization.data(withJSONObject: evidence).base64EncodedString()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap(app, "section.general")
        tap(app, "gl.confirm-date")
        tap(app, "gl.batches")
        tap(app, "gl.batch.new")
        tap(app, "gl.batch.default")
        tap(app, "1：300001")
        enter(app, "gl.batch-gross", "123.44")
        tap(app, "gl.batch.add-line")
        enter(app, "gl.account-code", "400001")
        enter(app, "gl.batch-amount", "123.45")
        tap(app, "gl.batch.save")
        XCTAssertTrue(app.descendants(matching: .any)["gl.batch.row.1"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "gl.batches.maintenance")
        tap(app, "gl.batch.proof.one")
        tap(app, "gl.batch.proof.1")
        let status = app.staticTexts["gl.batch.proof.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "明細または合計に相違があります")
        tap(app, "gl.batch.amend")
        tap(app, "gl.batch.amend.1")
        let gross = app.textFields["gl.batch.amend.batch-gross"]
        XCTAssertTrue(gross.waitForExistence(timeout: 5))
        gross.tap()
        let value = try XCTUnwrap(gross.value as? String)
        gross.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + "123.45")
        tap(app, "gl.batch.amend.save")
        XCTAssertTrue(app.buttons["gl.batch.amend.1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "gl.batch.proof.one")
        tap(app, "gl.batch.proof.1")
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "予定額と明細の合計が一致しました")
        XCTAssertTrue(app.buttons["gl.report.share"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "gl.posting")
        tap(app, "gl.posting.run")
        tap(app, "gl.posting.confirm")
        let posting = app.staticTexts["gl.posting.result"]
        XCTAssertTrue(posting.waitForExistence(timeout: 5))
        XCTAssertEqual(posting.label, "仕訳を転記し、転記帳票を出力しました。")
        XCTAssertTrue(app.buttons["gl.report.share"].exists)
    }

    @MainActor
    private func enter(_ app: XCUIApplication, _ id: String, _ input: String) {
        let field = app.textFields[id]
        let form = app.collectionViews["gl.batch.form"]
        XCTAssertTrue(form.exists)
        for _ in 0..<3 where !field.isHittable { form.swipeUp() }
        XCTAssertTrue(field.isHittable, id)
        field.tap()
        field.typeText(input)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), id)
        element.tap()
    }
}
