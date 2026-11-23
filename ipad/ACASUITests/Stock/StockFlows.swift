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
    func testReachST205() throws {
        try verifyItemReach("ST-205", menu: "master", destination: "delete", action: "削除")
    }

    @MainActor
    func testReachST206() throws {
        try verifyItemReach("ST-206", menu: "master", destination: "renumber", action: "確定",
                            additionalFields: ["新しい品目コード"])
    }

    @MainActor
    func testReachST207() throws {
        try verifyItemReach("ST-207", menu: "master", destination: "lookup", action: "照会")
    }

    @MainActor
    func testPrintST208() throws {
        let id = "ST-208"
        let app = try launchReach(id)
        for identifier in ["stock.confirmDate", "stock.master", "stock.masterReport", "stock.generateMasterReport"] {
            tap(app, identifier)
        }
        let result = app.staticTexts["stock.masterReportResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "帳票を作成しました。")
        verifyVerdict(app, id)
    }

    @MainActor
    func testPrintST216() throws { try verifyConfirmedReport("ST-216", route: "valuation") }

    @MainActor
    func testPrintST217() throws { try verifyConfirmedReport("ST-217", route: "activity") }

    @MainActor
    func testPrintST218() throws { try verifyConfirmedReport("ST-218", route: "reorder") }

    @MainActor
    func testPrintST219() throws { try verifyConfirmedReport("ST-219", route: "history") }

    @MainActor
    func testPrintST220() throws { try verifyConfirmedReport("ST-220", route: "listing") }

    @MainActor
    func testConfirmST090() throws {
        let app = try launchStockOperation("ST-090", "stock.master", "stock.create")
        register(app, code: "ITEM001", abbreviation: "ITM001", name: "ALPHA WIDGET", location: "BIN-A",
                 held: "10", retail: "12", cost: "5", value: "50", point: "2", standard: "5")
        for route in ["section.system", "section.stock", "stock.confirmDate", "stock.master", "stock.create"] {
            tap(app, route)
        }
        register(app, code: "ITEM002", abbreviation: "ITM002", name: "BETA WIDGET", location: "BIN-B",
                 held: "20", retail: "24", cost: "10", value: "200", point: "3", standard: "10")
        verifyVerdict(app, "ST-090")
    }

    @MainActor
    func testConfirmST203() throws {
        let app = try launchStockOperation("ST-203", "stock.master", "stock.create")
        register(app, code: "ITEM003", abbreviation: "ITM003", name: "GAMMA WIDGET", location: "BIN-C",
                 held: "10", retail: "12", cost: "5", value: "50", point: "2", standard: "5")
        verifyVerdict(app, "ST-203")
    }

    @MainActor
    func testConfirmST204() throws {
        let app = try launchStockOperation("ST-204", "stock.master", "stock.edit")
        let result = app.staticTexts["stock.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "分析ファイルのレコード長が一致しないため、在庫品目の変更を中止しました。")
        XCTAssertFalse(app.textFields["stock.code"].exists)
        XCTAssertFalse(app.buttons["stock.action"].exists)
        verifyVerdict(app, "ST-204")
    }

    @MainActor
    func testConfirmST213() throws {
        let app = try launchStockOperation("ST-213", "stock.movements", "stock.order")
        enter(app, "stock.code", "ITM001")
        enter(app, "stock.quantity", "7")
        enter(app, "stock.backordered", "2")
        tap(app, "stock.action")
        XCTAssertTrue(app.staticTexts["stock.result"].waitForExistence(timeout: 5))
        verifyVerdict(app, "ST-213")
    }

    @MainActor
    func testConfirmST222() throws {
        let app = try launchStockOperation("ST-222", "stock.import")
        let source = app.textViews["stock.importContents"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        source.typeText("BATCH01,'BATCH ITEM',2,5,0,0,10,0,12,5,50,,")
        tap(app, "stock.runImport")
        tap(app, "stock.confirmImport")
        XCTAssertEqual(app.staticTexts["stock.importResult"].label, "1 件の品目を取り込みました。")
        verifyVerdict(app, "ST-222", verdict: "mismatch")
    }

    @MainActor
    func testConfirmST223() throws {
        let app = try launchStockOperation("ST-223", "stock.closeStock")
        XCTAssertTrue(app.staticTexts["メニューを選んでください"].waitForExistence(timeout: 5))
        verifyVerdict(app, "ST-223")
    }

    @MainActor
    func testConfirmST225() throws {
        let app = try launchStockOperation("ST-225", "stock.settings")
        XCTAssertTrue(app.descendants(matching: .any)["system.company"].firstMatch.waitForExistence(timeout: 5))
        verifyVerdict(app, "ST-225")
    }

    @MainActor
    private func launchStockOperation(_ id: String, _ routes: String...) throws -> XCUIApplication {
        guard Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures") != nil else {
            throw XCTSkip("在庫操作のレガシー実測が必要です。")
        }
        let app = try launchReach(id)
        tap(app, "stock.confirmDate")
        routes.forEach { tap(app, $0) }
        return app
    }

    @MainActor
    private func register(_ app: XCUIApplication, code: String, abbreviation: String, name: String, location: String,
                          held: String, retail: String, cost: String, value: String, point: String, standard: String) {
        for (id, input) in [("code", code), ("abbreviation", abbreviation), ("name", name), ("location", location)] {
            enter(app, "stock." + id, input)
        }
        for (id, input) in [("held", held), ("retail", retail), ("cost", cost), ("value", value),
                            ("reorderPoint", point), ("reorderQuantity", standard)] {
            replace(app, "stock." + id, with: input)
        }
        makeVisible(app, app.descendants(matching: .any)["stock.action"].firstMatch)
        tap(app, "stock.action")
        XCTAssertEqual(app.staticTexts["stock.result"].label, "品目を保存しました。")
    }

    @MainActor
    private func replace(_ app: XCUIApplication, _ id: String, with text: String) {
        let field = app.textFields[id]
        makeVisible(app, field)
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        field.tap()
        field.typeText(XCUIKeyboardKey.end.rawValue + String(repeating: XCUIKeyboardKey.delete.rawValue,
                       count: (field.value as? String ?? "").count) + text)
    }

    @MainActor
    private func makeVisible(_ app: XCUIApplication, _ element: XCUIElement) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.26))
        for _ in 0..<3 where !element.isHittable { start.press(forDuration: 0.05, thenDragTo: end) }
    }

    @MainActor
    private func verifyConfirmedReport(_ id: String, route: String) throws {
        guard Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures") != nil else {
            throw XCTSkip("帳票確定のレガシー実測が必要です。")
        }
        let app = try launchReach(id)
        for button in ["stock.confirmDate", "stock.reports", "stock." + route, "stock.generateReport"] {
            tap(app, button)
        }
        XCTAssertEqual(app.staticTexts["stock.reportResult"].label, "帳票を作成しました。", id)
        verifyVerdict(app, id)
    }

    @MainActor
    func testReachST209() throws { try verifyMovements("ST-209") }

    @MainActor
    func testReachST210() throws {
        try verifyItemReach("ST-210", menu: "movements", destination: "receive", action: "確定",
                            additionalFields: ["stock.quantity", "stock.price"])
    }

    @MainActor
    func testReachST211() throws {
        try verifyItemReach("ST-211", menu: "movements", destination: "issue", action: "確定",
                            additionalFields: ["stock.quantity"])
    }

    @MainActor
    func testReachST212() throws {
        try verifyItemReach("ST-212", menu: "movements", destination: "barcode", action: "確定",
                            additionalFields: ["stock.quantity", "stock.price"])
    }

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
    private func verifyItemReach(_ id: String, menu: String, destination: String, action: String,
                                 additionalFields: [String] = []) throws {
        let app = try launchReach(id)
        for identifier in ["stock.confirmDate", "stock." + menu, "stock." + destination] { tap(app, identifier) }
        for field in ["stock.code"] + additionalFields {
            XCTAssertTrue(app.textFields[field].waitForExistence(timeout: 5), id)
        }
        let button = app.buttons["stock.action"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        XCTAssertEqual(button.label, action)
        verifyVerdict(app, id)
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
    private func verifyVerdict(_ app: XCUIApplication, _ id: String, verdict: String = "match") {
        XCTAssertTrue(app.staticTexts["case.verdict." + verdict].waitForExistence(timeout: 5), id)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
        makeVisible(app, app.descendants(matching: .any)["stock.action"].firstMatch)
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
