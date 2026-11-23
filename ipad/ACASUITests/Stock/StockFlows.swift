import XCTest

final class StockFlows: XCTestCase {
    private struct MovementFixture: Decodable {
        struct Input: Decodable {
            let code: String
            let quantity: String
            let price: String?
        }

        let workflow: String
        let input: Input
    }

    @MainActor
    func testReachST001() throws { try verifyDate("ST-001", reopen: true) }

    @MainActor
    func testReachST002() throws { try verifyMaster("ST-002") }

    @MainActor
    func testReachST003() throws { try verifyMovements("ST-003") }

    @MainActor
    func testReachST004() throws { try verifyReports("ST-004") }

    @MainActor
    func testReachST005() throws { try verifyClosePeriod("ST-005") }

    @MainActor
    func testReachST006() throws { try verifyRebuild("ST-006") }

    @MainActor
    func testReachST200() throws { try verifyDate("ST-200", reopen: false) }

    @MainActor
    func testReachST201() throws { try verifyDate("ST-201", reopen: true) }

    @MainActor
    func testReachST202() throws { try verifyMaster("ST-202") }

    @MainActor
    func testReachST209() throws { try verifyMovements("ST-209") }

    @MainActor
    func testReachST215() throws { try verifyReports("ST-215") }

    @MainActor
    func testReachST221() throws { try verifyClosePeriod("ST-221") }

    @MainActor
    func testReachST224() throws { try verifyRebuild("ST-224") }

    @MainActor
    func testReachST226() throws { try verifyDate("ST-226", reopen: false) }

    @MainActor
    private func verifyDate(_ id: String, reopen: Bool) throws {
        let app = try launchReach(id)
        if reopen {
            tap(app, "stock.confirmDate")
            tap(app, "stock.date")
        }
        XCTAssertTrue(app.navigationBars["在庫処理日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stock.confirmDate"].waitForExistence(timeout: 5))
        verifyVerdict(app, id)
    }

    @MainActor
    private func verifyMaster(_ id: String) throws {
        try verifyReach(id, destination: "master", identifiers: ["create", "edit", "delete", "renumber", "lookup", "masterReport"])
    }

    @MainActor
    private func verifyMovements(_ id: String) throws {
        try verifyReach(id, destination: "movements", identifiers: ["receive", "issue", "barcode", "order", "audit"])
    }

    @MainActor
    private func verifyReports(_ id: String) throws {
        try verifyReach(id, destination: "reports", identifiers: ["valuation", "activity", "reorder", "history", "listing"])
    }

    @MainActor
    private func verifyClosePeriod(_ id: String) throws {
        try verifyReach(id, destination: "closePeriod", labels: ["当期間の累計を消去", "年度累計を消去"])
    }

    @MainActor
    private func verifyRebuild(_ id: String) throws {
        try verifyReach(id, destination: "rebuild", labels: ["一時ファイルから復元"])
    }

    @MainActor
    private func verifyReach(_ id: String, destination: String, identifiers: [String] = [], labels: [String] = []) throws {
        let app = try launchReach(id)
        tap(app, "stock.confirmDate")
        tap(app, "stock." + destination)
        for identifier in identifiers {
            XCTAssertTrue(app.descendants(matching: .any)["stock." + identifier].firstMatch.waitForExistence(timeout: 5), id)
        }
        for label in labels {
            XCTAssertTrue(app.switches[label].waitForExistence(timeout: 5), id)
        }
        verifyVerdict(app, id)
    }

    @MainActor
    private func launchReach(_ id: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        tap(app, "section.stock")
        return app
    }

    @MainActor
    private func verifyVerdict(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5), id)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testStockReceipt() throws {
        try verifyMovement("ST-400")
    }

    @MainActor
    func testStockReceiptMissingItem() throws {
        try verifyMovement("ST-401")
    }

    @MainActor
    func testStockIssue() throws {
        try verifyMovement("ST-402")
    }

    @MainActor
    func testStockIssueMissingItem() throws {
        try verifyMovement("ST-403")
    }

    @MainActor
    private func verifyMovement(_ id: String) throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(MovementFixture.self, from: data)
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        for identifier in ["section.stock", "stock.confirmDate", "stock.movements", fixture.workflow] {
            tap(app, identifier)
        }
        enter(app, "stock.code", fixture.input.code)
        enter(app, "stock.quantity", fixture.input.quantity)
        if let price = fixture.input.price {
            enter(app, "stock.price", price)
        }
        tap(app, "stock.action")
        let result = app.staticTexts["stock.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        if fixture.input.code == "MISSING" {
            XCTAssertEqual(result.label, "指定した在庫品目がありません。")
        } else {
            XCTAssertTrue(result.label.hasPrefix("在庫数："), result.label)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5), id)
    }

    @MainActor
    func testStockAuditReports() throws {
        continueAfterFailure = false
        let id = "ST-214"
        guard let url = Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures") else {
            throw XCTSkip("在庫の実画面用データを生成してください。")
        }
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        for identifier in ["section.stock", "stock.confirmDate", "stock.movements", "stock.audit", "stock.generateAudit"] {
            tap(app, identifier)
        }
        let matches = app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = id
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(matches, id + " の監査帳票原本が一致しません")
    }

    @MainActor
    func testRegisterAndReceive() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let fixture = Data("""
        {"id":"在庫動作確認","title":"新品目の登録と入庫","workflow":"stock.flow",
         "dateSeconds":1795407349,"changes":[],"reports":{}}
        """.utf8)
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        tap(app, "section.stock")
        tap(app, "stock.confirmDate")
        tap(app, "stock.master")
        tap(app, "stock.create")
        enter(app, "stock.code", "ITEM001")
        enter(app, "stock.abbreviation", "ITEM")
        enter(app, "stock.name", "Test item")
        tap(app, "stock.action")
        let result = app.staticTexts["stock.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "品目を保存しました。")

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "stock.movements")
        tap(app, "stock.receive")
        enter(app, "stock.code", "ITEM001")
        enter(app, "stock.quantity", "2")
        enter(app, "stock.price", "5.00")
        tap(app, "stock.action")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "在庫数：2")
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
