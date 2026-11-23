import XCTest

final class MasterSetupFlows: XCTestCase {
    @MainActor
    func testMasterRecordsMatchLegacyBytes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try masterFixture()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        try Self.registerMasters(app)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "初期マスタ登録"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    static func registerMasters(_ app: XCUIApplication) throws {
        tap(app, "system.master")
        for (kind, records) in [
            ("customer", [
                [("code", "CUST01"), ("name", "ALPHA CUSTOMER"), ("address", "1 TEST ROAD\\LONDON\\UK"),
                 ("address2", "LONDON"), ("phone", "01234567890"), ("email", "alpha@example.test")],
                [("code", "CUST02"), ("name", "BETA CUSTOMER"), ("address", "2 TEST ROAD\\LONDON\\UK")],
            ]),
            ("supplier", [
                [("code", "SUPP01"), ("name", "ALPHA SUPPLIER"), ("address", "1 SUPPLY ROAD\\LONDON\\UK")],
                [("code", "SUPP02"), ("name", "BETA SUPPLIER"), ("address", "2 SUPPLY ROAD\\LONDON\\UK")],
            ]),
            ("stock", [
                [("code", "ITEM001"), ("abbreviation", "ITM001"), ("name", "ALPHA WIDGET"), ("location", "BIN-A"),
                 ("held", "10"), ("reorder-point", "2"), ("reorder-quantity", "5"), ("retail", "12"), ("cost", "5"), ("value", "50")],
                [("code", "ITEM002"), ("abbreviation", "ITM002"), ("name", "BETA WIDGET"), ("location", "BIN-B"),
                 ("held", "20"), ("reorder-point", "3"), ("reorder-quantity", "10"), ("retail", "24"), ("cost", "10"), ("value", "200")],
            ]),
        ] {
            for fields in records {
                tap(app, "system.master." + kind)
                for (key, value) in fields {
                    let field = app.textFields["system.master.field." + key]
                    for _ in 0..<3 where !field.isHittable { app.swipeUp() }
                    XCTAssertTrue(field.isHittable, key)
                    field.tap()
                    field.typeText(value + "\n")
                }
                tap(app, "system.master.save")
                let saved = app.staticTexts["system.master.status"]
                for _ in 0..<3 where !saved.exists { app.swipeUp() }
                XCTAssertTrue(saved.waitForExistence(timeout: 5))
                XCTAssertEqual(saved.label, "マスタを登録しました")
                app.navigationBars.buttons.firstMatch.tap()
            }
        }
    }

    private func masterFixture() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SYS-001", withExtension: "json",
                                                          subdirectory: "fixtures"))
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let changes = try XCTUnwrap(fixture["changes"] as? [[String: Any]])
        let path = "ledgers/acas/system.dat"
        let system = changes.filter { $0["file"] as? String == path }
            .sorted { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
        XCTAssertEqual(system.count, 4)
        let rawSystem = try system.map { "0004000000000000" + (try XCTUnwrap($0["after"] as? String)) }.joined()
        let seed = ["files": [path: ["type": "relative", "hex": rawSystem]]]
        let files = Set(["salesled.dat", "purchled.dat", "stockctl.dat", "analysis.dat"])
        let masterChanges = changes.filter {
            files.contains(URL(fileURLWithPath: $0["file"] as? String ?? "").lastPathComponent)
        }
        XCTAssertEqual(masterChanges.count, 22)
        fixture["title"] = "初期マスタ登録のみ（設定済み）"
        fixture["seed"] = try JSONSerialization.data(withJSONObject: seed).base64EncodedString()
        fixture["changes"] = masterChanges
        fixture["reports"] = [String: String]()
        return try JSONSerialization.data(withJSONObject: fixture).base64EncodedString()
    }

    @MainActor
    private static func tap(_ app: XCUIApplication, _ id: String) {
        let target = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), id)
        target.tap()
    }
}
