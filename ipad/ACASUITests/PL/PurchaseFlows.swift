import XCTest

@MainActor
final class PurchaseFlows: XCTestCase {
    func testPL400() throws {
        let app = try launch("PL-400")
        tap(app, "pl.suppliers")
        tap(app, "pl.supplier.edit")
        enter(app, "pl.supplier.search.code", "SUPP018")
        tap(app, "pl.supplier.search")
        XCTAssertTrue(app.descendants(matching: .any)["pl.supplier.result"].firstMatch.exists)
        dismissKeyboard(app)
        tap(app, "pl.supplier.edit.open", scrolling: true)
        enter(app, "pl.supplier.name", "EQUIV UPDATED SUPPLIER", replacing: true)
        tap(app, "pl.supplier.save", scrolling: true)
        finish(app, "PL-400")
    }

    func testPL401() throws {
        let app = try launch("PL-401")
        tap(app, "pl.suppliers")
        tap(app, "pl.supplier.delete")
        enter(app, "pl.supplier.search.code", "SUPP026")
        tap(app, "pl.supplier.search")
        XCTAssertTrue(app.descendants(matching: .any)["pl.supplier.result"].firstMatch.exists)
        dismissKeyboard(app)
        tap(app, "pl.supplier.delete.open", scrolling: true)
        tap(app, "pl.supplier.delete.confirm")
        finish(app, "PL-401")
    }

    func testPL402() throws {
        let app = try launch("PL-402")
        tap(app, "pl.suppliers")
        tap(app, "pl.supplier.show")
        enter(app, "pl.supplier.search.code", "MISS001")
        tap(app, "pl.supplier.search")
        XCTAssertTrue(app.alerts.staticTexts["該当する仕入先がありません。"].exists)
        finish(app, "PL-402")
    }

    func testPL403() throws {
        let app = try launch("PL-403")
        tap(app, "pl.suppliers")
        tap(app, "pl.supplier.add")
        enter(app, "pl.supplier.code", "TEST01")
        enter(app, "pl.supplier.name", "EQUIV NEW SUPPLIER")
        enter(app, "pl.supplier.address", "1 TEST ROAD\\LONDON\\UK")
        tap(app, "pl.supplier.save", scrolling: true)
        finish(app, "PL-403")
    }

    func testPL411() throws {
        let app = try launch("PL-411")
        tap(app, "pl.transaction.add")
        enter(app, "pl.invoice.supplier", "SUPP018")
        enter(app, "pl.invoice.order", "PL-ORDER")
        enter(app, "pl.invoice.reference", "PL-REF")
        dismissKeyboard(app)
        enter(app, "pl.invoice.line.0.code", "a1", scrolling: true)
        dismissKeyboard(app)
        enter(app, "pl.invoice.line.0.net", "100", replacing: true, scrolling: true)
        dismissKeyboard(app)
        tap(app, "pl.invoice.save", scrolling: true)
        finish(app, "PL-411")
    }

    func testPL412() throws {
        let app = try launch("PL-412")
        tap(app, "pl.transaction.add")
        enter(app, "pl.invoice.supplier", "MISS001")
        tap(app, "pl.invoice.supplier.check")
        XCTAssertTrue(app.alerts.staticTexts["該当する仕入先がありません。"].exists)
        finish(app, "PL-412")
    }

    func testPL413() throws {
        let app = try launch("PL-413")
        tap(app, "pl.transaction.proof")
        tap(app, "pl.proof.generate")
        let folios = app.staticTexts.matching(identifier: "pl.transaction.number")
        XCTAssertTrue(folios.firstMatch.waitForExistence(timeout: 5), "検証帳票の取引行がありません")
        XCTAssertEqual(folios.count, 1, "検証帳票の取引行数")
        let folio = "1"
        XCTAssertEqual(folios.firstMatch.label, folio)
        let table = app.descendants(matching: .any).matching(identifier: "pl.transactions.table").firstMatch
        for (column, expected) in [("supplier", "SUPP018"), ("type", "請求書"), ("net", "100.00"), ("tax", "20.00")] {
            let cell = table.staticTexts["pl.transaction.\(folio).\(column)"]
            XCTAssertTrue(cell.exists, "伝票\(folio)の\(column)列がありません")
            XCTAssertEqual(cell.label, expected, "伝票\(folio)の\(column)列")
        }
        finish(app, "PL-413")
    }

    func testPaymentEntryShowsSavedAmountInPendingPayments() throws {
        let app = try launch("PL-413", smokeID: "支払入力スモーク")
        tap(app, "pl.payment.add", scrolling: true)
        tap(app, "pl.payment.supplier")
        let supplier = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "SUPP018")).firstMatch
        XCTAssertTrue(supplier.waitForExistence(timeout: 5))
        supplier.tap()
        enter(app, "pl.payment.amount", "50", replacing: true)
        dismissKeyboard(app)
        tap(app, "pl.payment.save", scrolling: true)
        XCTAssertTrue(app.textFields["pl.payment.amount"].waitForNonExistence(timeout: 5), "支払入力画面が閉じません")
        tap(app, "pl.payment.edit", scrolling: true)
        let amount = app.descendants(matching: .any)["pl.payment.pending.amount.SUPP018/1001"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "50.00")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "支払入力スモーク"
        proof.lifetime = .keepAlways
        add(proof)
    }

    private func launch(_ id: String, smokeID: String? = nil) throws -> XCUIApplication {
        continueAfterFailure = false
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures"),
            """
            \(id) のフィクスチャがありません。リポジトリのルートで以下を実行してから再ビルドしてください。
            python3 ipad/ACASUITests/PL/generate_fixtures.py "$HOME/acas-ipad-oracle"
            xcodegen generate --spec ipad/project.yml
            """
        )
        var data = try Data(contentsOf: url)
        if let smokeID {
            var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            fixture["id"] = smokeID
            fixture["title"] = "実UIの動作確認（同一性比較なし）"
            fixture["workflow"] = "pl.smoke"
            data = try JSONSerialization.data(withJSONObject: fixture)
        }
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[smokeID ?? id].waitForExistence(timeout: 10))
        tap(app, "section.purchases")
        tap(app, "pl.date.confirm")
        return app
    }

    private func tap(_ app: XCUIApplication, _ id: String, scrolling: Bool = false) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(element, in: app, scrolling: scrolling)
        element.tap()
    }

    private func enter(_ app: XCUIApplication, _ id: String, _ value: String, replacing: Bool = false, scrolling: Bool = false) {
        let field = app.textFields[id]
        reveal(field, in: app, scrolling: scrolling)
        field.tap()
        if replacing, let current = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrolling: Bool) {
        if scrolling {
            for _ in 0..<4 where !element.exists || !element.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), element.identifier)
        XCTAssertTrue(element.isHittable, element.identifier)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let dismiss = keyboard.buttons["キーボードを非表示"]
        guard dismiss.isHittable else { return }
        dismiss.tap()
    }

    private func finish(_ app: XCUIApplication, _ id: String) {
        let match = app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertTrue(match, "\(id) の判定が異なります")
    }
}
