import XCTest

final class SalesDunningFlows: XCTestCase {
    @MainActor
    func testValidDateStaysAtDateEntry() throws {
        continueAfterFailure = false
        var system = [UInt8](repeating: 0, count: 1024)
        system[14] = 60
        system.replaceSubrange(19..<23, with: withUnsafeBytes(of: Int32(155_555).littleEndian, Array.init))
        system[275 + 18] = 0x31
        system[327] = 0x31
        system[554] = 0x59
        var sortedSystem = system
        sortedSystem[554] = 0x4e
        let key = Array("CUST011".utf8) + [1, 0, 0, 0]
        let item = key + [UInt8](repeating: 0, count: 114 - key.count)
        let seed = try JSONSerialization.data(withJSONObject: [
            "files": [
                "ledgers/acas/system.dat": ["type": "relative", "hex": hex([0, 4, 0, 0, 0, 0, 0, 0] + system)],
                "ledgers/acas/openitm3.dat": ["type": "indexed", "records": [[hex(key), hex(item)]]],
            ],
        ])
        let fixture = try JSONSerialization.data(withJSONObject: [
            "id": "SL-督促状試験", "title": "督促状の基準日入力", "workflow": "sales-dunning",
            "dateSeconds": 1_795_440_000, "seed": seed.base64EncodedString(),
            "changes": [[
                "file": "ledgers/acas/system.dat", "key": "00000001",
                "before": hex(system), "after": hex(sortedSystem),
            ]],
            "reports": [
                "ledgers/acas/oisort.wrk": hex(item), "letter.001": "", "letter.002": "", "letter.003": "",
            ],
        ])
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = fixture.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        for id in ["section.sales", "sales.date.save"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            element.tap()
        }
        let dunning = app.descendants(matching: .any)["sales.dunning"].firstMatch
        if !dunning.exists || !dunning.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(dunning.waitForExistence(timeout: 5))
        dunning.tap()
        let next = app.buttons["sales.dunning.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let verdict = app.staticTexts["case.verdict.match"]
        XCTAssertFalse(verdict.exists)
        next.tap()
        let error = app.staticTexts["sales.dunning.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "旧システムと同じ制約により、基準日を確定できません。督促状は出力されません。")
        XCTAssertTrue(next.exists)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "督促状の基準日入力"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
