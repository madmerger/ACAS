import XCTest

@MainActor
final class SalesAnalysisReportFlows: XCTestCase {
    func testSL220() throws { try verify("SL-220", operation: "print", verdict: "match") }
    func testSL221() throws { try verify("SL-221", operation: "printAll", verdict: "mismatch") }
    func testSL221OriginalPrefix() throws { try verify("SL-221-prefix", operation: "printAll", verdict: "match") }

    private func verify(_ id: String, operation: String, verdict: String) throws {
        continueAfterFailure = false
        let url = Bundle(for: Self.self).url(forResource: id, withExtension: "json", subdirectory: "fixtures")
        try XCTSkipIf(url == nil, "generate_reach_fixtures.py で売上分析コード帳票の証跡を準備してください")
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: XCTUnwrap(url)).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        for identifier in ["section.sales", "sales.date.save", "sales.analysis.codes",
                           "sales.analysis." + operation, "sales.analysis.generate"] {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if identifier == "sales.analysis.codes", !element.isHittable {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(element.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(element.isHittable, identifier)
            element.tap()
        }
        XCTAssertTrue(app.buttons["sales.analysis.export"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["sales.analysis.error"].exists)
        XCTAssertTrue(app.staticTexts["case.verdict." + verdict].waitForExistence(timeout: 5))
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
    }
}
