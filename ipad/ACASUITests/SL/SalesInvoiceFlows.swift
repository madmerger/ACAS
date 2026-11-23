import XCTest

final class SalesInvoiceFlows: XCTestCase {
    @MainActor
    func testSL100() throws { try create("SL-100", credit: false) }

    @MainActor
    func testSL101() throws { try create("SL-101", credit: true) }

    @MainActor
    func testSL103() throws {
        let (app, _) = try launch("SL-103")
        tap("sales.invoice.print", in: app)
        tap("sales.invoice.generate", in: app)
        tap("sales.invoice.confirmPrint", in: app)
        finish(app, "SL-103", result: "請求書帳票を生成しました：1件")
        let export = app.buttons["sales.invoice.export"]
        XCTAssertTrue(export.isHittable)
        XCTAssertEqual(export.label, "帳票原本を保存")
    }

    @MainActor
    private func create(_ id: String, credit: Bool) throws {
        let (app, input) = try launch(id)
        tap("sales.invoice.pending", in: app)
        func fill(_ name: String, field: String, replacing: Bool = false, submit: Bool = false) throws {
            let text = try XCTUnwrap(input[name])
            let element = app.textFields["sales.invoice." + field]
            reveal(element, in: app)
            element.tap()
            if replacing, let old = element.value as? String {
                element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            element.typeText(text)
            if submit { element.typeText("\n") }
        }
        if credit {
            tap("貸方票", in: app)
        }
        try fill("customer", field: "customer")
        try fill("reference", field: "reference")
        try fill("order", field: "order", submit: true)
        tap("sales.invoice.line.0", in: app)
        tap("税率 1", in: app)
        try fill("product", field: "product.0")
        try fill("analysis", field: "analysis.0")
        try fill("description", field: "description.0")
        try fill("unit", field: "unit.0", replacing: true)
        let editProof = XCTAttachment(screenshot: app.screenshot())
        editProof.name = id + "-明細入力"
        editProof.lifetime = .keepAlways
        add(editProof)
        app.buttons["sales.invoice.line.done"].tap()
        app.buttons["sales.invoice.save"].tap()
        finish(app, id, result: "売上取引を保存しました：00000000")
    }

    @MainActor
    private func launch(_ id: String) throws -> (XCUIApplication, [String: String]) {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let ids = ["SL-100", "SL-101", "SL-103"]
        func fixture(_ id: String) -> URL? { bundle.url(forResource: id, withExtension: "json", subdirectory: "fixtures") }
        try XCTSkipIf(ids.allSatisfy { fixture($0) == nil }, "請求書の証跡は generate_invoice_fixtures.py で生成してください")
        let data = try Data(contentsOf: XCTUnwrap(fixture(id), "\(id) の証跡がありません"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(json["input"] as? [String: String])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        tap("section.sales", in: app)
        tap("sales.date.save", in: app)
        tap("sales.invoice.menu", in: app)
        return (app, input)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), element.identifier)
        XCTAssertTrue(element.isHittable, element.label)
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(element, in: app)
        element.tap()
    }

    @MainActor
    private func finish(_ app: XCUIApplication, _ id: String, result: String) {
        let verdict = app.staticTexts["case.verdict.match"]
        let matched = verdict.waitForExistence(timeout: 5)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        let label = app.staticTexts["sales.invoice.result"]
        XCTAssertTrue(label.exists)
        XCTAssertEqual(label.label, result)
        XCTAssertTrue(matched, id + " のレコード差分または帳票が異なります")
    }
}
