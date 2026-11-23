import XCTest

final class SalesPaymentsFlows: XCTestCase {
    @MainActor
    func testSavesPaymentBatch() throws {
        continueAfterFailure = false
        var system = [UInt8](repeating: 0, count: 1024)
        system[14] = 60
        system[275 + 18] = 0x31
        let key = Array("CUST011".utf8)
        let customer = key + [UInt8](repeating: 0x20, count: 300 - key.count)
        let seed = try JSONSerialization.data(withJSONObject: [
            "files": [
                "ledgers/acas/system.dat": ["type": "relative", "hex": hex([0, 4, 0, 0, 0, 0, 0, 0] + system)],
                "ledgers/acas/salesled.dat": ["type": "indexed", "records": [[hex(key), hex(customer)]]],
            ],
        ])
        let fixture = try JSONSerialization.data(withJSONObject: [
            "id": "SL-入金試験", "title": "入金組の登録", "workflow": "ui-test-only",
            "dateSeconds": 1_795_440_000, "seed": seed.base64EncodedString(), "changes": [], "reports": [:],
        ])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        tap("section.sales", in: app)
        tap("sales.date.save", in: app)
        tap("sales.payment.entry", in: app)

        let code = app.textFields["sales.payment.customer"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("CUST011")
        let amount = app.textFields["sales.payment.amount"]
        amount.tap()
        amount.typeText("12.50")
        tap("sales.payment.findInvoices", in: app)
        tap("sales.payment.add", in: app)
        tap("sales.payment.save", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["sales.payment.saved"].waitForExistence(timeout: 5))
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "入金組の保存"
        proof.lifetime = .keepAlways
        add(proof)

        app.navigationBars.buttons.firstMatch.tap()
        tap("sales.payment.proof", in: app)
        tap("sales.payment.proof.generate", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["sales.payment.proof.CUST011/1/1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sales.payment.proof.export"].exists)
        let report = XCTAttachment(screenshot: app.screenshot())
        report.name = "入金検証帳票"
        report.lifetime = .keepAlways
        add(report)

        app.navigationBars.buttons.firstMatch.tap()
        tap("sales.payment.amend", in: app)
        tap("sales.payment.amend.CUST011/1/1", in: app)
        tap("sales.payment.reverse", in: app)
        XCTAssertTrue(app.staticTexts["sales.payment.cancelled"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        tap("sales.payment.post", in: app)
        tap("sales.payment.post.start", in: app)
        tap("sales.payment.post.confirm", in: app)
        XCTAssertTrue(app.staticTexts["sales.payment.post.finished"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sales.payment.post.export"].exists)
        let posting = XCTAttachment(screenshot: app.screenshot())
        posting.name = "入金転記帳票"
        posting.lifetime = .keepAlways
        add(posting)
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        button.tap()
    }
}
