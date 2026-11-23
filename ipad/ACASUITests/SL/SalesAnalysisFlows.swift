import XCTest

final class SalesAnalysisFlows: XCTestCase {
    @MainActor
    func testRegistersAndDisplaysAnalysisCode() throws {
        continueAfterFailure = false
        var system = [UInt8](repeating: 0, count: 1024)
        system[14] = 60
        system[275 + 14] = 0x30
        let bytes = [UInt8(0), 4, 0, 0, 0, 0, 0, 0] + system
        let seed = try JSONSerialization.data(withJSONObject: [
            "files": ["ledgers/acas/system.dat": ["type": "relative", "hex": bytes.map { String(format: "%02x", $0) }.joined()]],
        ])
        let fixture = try JSONSerialization.data(withJSONObject: [
            "id": "SL-分析試験", "title": "売上分析コードの登録", "workflow": "ui-test-only",
            "dateSeconds": 1_795_440_000, "seed": seed.base64EncodedString(), "changes": [], "reports": [:],
        ])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for id in ["section.sales", "sales.date.save", "sales.analysis.codes", "sales.analysis.add"] {
            tap(id, in: app)
        }
        let group = app.textFields["sales.analysis.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.tap()
        group.typeText("A")
        let account = app.textFields["sales.analysis.account"]
        account.tap()
        account.typeText("400001")
        let description = app.textFields["sales.analysis.description"]
        description.tap()
        let longDescription = String(repeating: "A", count: 25)
        description.typeText(longDescription)
        tap("sales.analysis.save", in: app)
        let descriptionError = app.alerts["説明は24バイト以内で入力してください（全角のみなら12文字まで）"]
        XCTAssertTrue(descriptionError.waitForExistence(timeout: 5))
        descriptionError.buttons.firstMatch.tap()
        description.tap()
        description.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: longDescription.count))
        let printCode = app.textFields["sales.analysis.printCode"]
        XCTAssertEqual(printCode.value as? String, "A")
        printCode.tap()
        printCode.typeText("BCD")
        tap("sales.analysis.save", in: app)
        let printCodeError = app.alerts["印字コードは3バイト以内で入力してください（全角のみなら1文字まで）"]
        XCTAssertTrue(printCodeError.waitForExistence(timeout: 5))
        printCodeError.buttons.firstMatch.tap()
        printCode.tap()
        printCode.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        tap("sales.analysis.save", in: app)
        tap("sales.analysis.display", in: app)
        let row = app.descendants(matching: .any)["sales.analysis.code.SA"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "400001")
        XCTAssertFalse(row.label.contains("印字コード"))
        let standard = app.descendants(matching: .any)["sales.analysis.code.Sa"].firstMatch
        XCTAssertTrue(standard.label.contains("標準グループ"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "登録した売上分析コード"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.navigationBars["売上分析コード表示"].buttons.firstMatch.tap()
        tap("sales.analysis.printAll", in: app)
        tap("sales.analysis.generate", in: app)
        let purchaseCarriage = app.descendants(matching: .any)["sales.analysis.code.Pza"].firstMatch
        if !purchaseCarriage.isHittable { app.swipeUp() }
        XCTAssertTrue(purchaseCarriage.waitForExistence(timeout: 5))
        XCTAssertTrue(purchaseCarriage.label.contains("仕入運賃"))
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
    }
}
