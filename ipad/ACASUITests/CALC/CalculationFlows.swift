import XCTest

final class CalculationFlows: XCTestCase {
    private struct Evidence: Codable {
        let id: String
        let title: String
        let expected: [String: String]?
    }

    private struct Scenario: Decodable {
        let id: String
        let title: String
        let expected: [String: String]?
        let function: Function?
        let inputs: [String]?
        let visible: [String: String]?

        var evidence: Evidence { Evidence(id: id, title: title, expected: expected) }
    }

    private enum Function: String, Decodable {
        case checkDigit, date, vat, age, average

        var title: String {
            switch self {
            case .checkDigit: "チェックディジット"
            case .date: "日付変換"
            case .vat: "付加価値税"
            case .age: "経過日数区分"
            case .average: "平均原価"
            }
        }

        var fields: [String] {
            switch self {
            case .checkDigit: ["calculation.code"]
            case .date: ["calc.input.date"]
            case .vat: ["calc.input.net", "calc.input.rate"]
            case .age: ["calc.input.days"]
            case .average: ["calc.input.value", "calc.input.qty"]
            }
        }
    }

    private struct Measurement: Encodable {
        let id: String
        let verdict: String
        let observed: [String: String]
        let differences: [String]
    }

    @MainActor
    private func openCalculation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_CALC_EVIDENCE"] = "W10="
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let menu = app.descendants(matching: .any).matching(identifier: "calculation.title").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        return app
    }

    @MainActor
    func testRejectsNumericInputBeyondLegacyPicture() {
        let scenarios: [(Function, [String], String)] = [
            (.vat, ["10000000", "10"], "calc.result.tax"),
            (.vat, ["100", "100"], "calc.result.tax"),
            (.vat, ["100.001", "10"], "calc.result.tax"),
            (.age, ["10000000"], "calc.result.bucket"),
            (.average, ["100000000", "1"], "calc.result.cost"),
            (.average, ["100", "1000000"], "calc.result.cost"),
        ]
        for (function, values, resultID) in scenarios {
            let app = openCalculation()
            app.buttons[function.title].tap()
            for (fieldID, value) in zip(function.fields, values) {
                let field = app.textFields[fieldID]
                field.tap()
                field.typeText(value)
            }
            app.buttons["action.calculate"].tap()
            XCTAssertEqual(app.staticTexts["calc.error.numberTooLong"].label, "入力できる桁数を超えています")
            XCTAssertFalse(app.staticTexts[resultID].exists)
        }
    }

    @MainActor
    func testRejectsCheckDigitInputLongerThanSixCharacters() {
        let app = openCalculation()
        let code = app.textFields["calculation.code"]
        code.tap()
        code.typeText("K9P34Y9")
        app.buttons["action.calculate"].tap()
        XCTAssertEqual(app.staticTexts["calc.error.codeTooLong"].label, "取引先コードは６桁で入力してください")
        XCTAssertFalse(app.staticTexts["calculation.result"].exists)
        XCTAssertFalse(app.staticTexts["calculation.valid"].exists)
    }

    @MainActor
    func testCALCIdenticalToLegacy() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "calc-suite", withExtension: "json", subdirectory: "fixtures"
        ), """
        CALC のテスト台帳（calc-suite.json）がありません。基盤の台帳生成の後、リポジトリのルートから次のコマンドを実行し、テスト用に再ビルドしてください。
        python3 ipad/ACASUITests/CALC/generate_calc_fixtures.py ipad/.generated/cases.json
        """)
        let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: fixture))
        guard !scenarios.isEmpty else {
            return XCTFail("CALC のテスト台帳が空です。再生成してテスト用に再ビルドしてください。")
        }
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_CALC_EVIDENCE"] = try JSONEncoder().encode(scenarios.map(\.evidence)).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let menu = app.descendants(matching: .any).matching(identifier: "calculation.title").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()

        var selected = Function.checkDigit
        var measurements: [Measurement] = []
        defer {
            if let data = try? JSONEncoder().encode(measurements) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "CALC実測結果"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        for (index, scenario) in scenarios.enumerated() {
            let id = scenario.id
            print("CALC_UI_BEGIN \(id)")
            let banner = app.staticTexts[id]
            guard banner.exists || banner.waitForExistence(timeout: 5) else {
                return XCTFail("\(id) の表示がありません")
            }
            var observed: [String: String] = [:]
            var differences: [String] = []
            var verdict = "excluded"
            if let function = scenario.function {
                if selected != function {
                    app.buttons[function.title].tap()
                    selected = function
                }
                let values = try XCTUnwrap(scenario.inputs)
                XCTAssertEqual(function.fields.count, values.count)
                for (fieldID, value) in zip(function.fields, values) {
                    let field = app.textFields[fieldID]
                    field.tap()
                    field.typeText(value)
                    if (field.value as? String) != value {
                        differences.append("\(fieldID) の入力が異なります: \(field.value ?? "")")
                    }
                }
                app.buttons["action.calculate"].tap()
                let visible = try XCTUnwrap(scenario.visible)
                let resultIDs = [
                    "calculation.result", "calculation.valid", "calc.invalidCode", "calc.result.normalized",
                    "calc.result.serial", "calc.invalidDate", "calc.result.tax", "calc.result.bucket", "calc.result.cost",
                ]
                let matchedOracle = app.staticTexts["case.verdict.match"].exists
                for resultID in matchedOracle ? visible.keys.sorted() : resultIDs {
                    let label = app.staticTexts[resultID]
                    if label.exists { observed[resultID] = label.label }
                }
                if observed != visible {
                    differences.append("レガシー実測に対応する画面値: \(visible)")
                }
                verdict = differences.isEmpty && matchedOracle ? "match" : "mismatch"
            }
            if !app.staticTexts["case.verdict." + verdict].exists {
                differences.append("画面とテストの判定が一致しません")
                verdict = "mismatch"
            }
            measurements.append(Measurement(id: id, verdict: verdict, observed: observed, differences: differences))
            print("CALC_UI_END \(id) \(verdict)")
            if verdict == "mismatch" {
                print("CALC_UI_DIFF \(id) 画面値: \(observed) / \(differences)")
            }
            if verdict == "mismatch" || ["CALC-200", "CALC-246", "CALC-247", "CALC-277", "CALC-308", "CALC-309"].contains(id) {
                let proof = XCTAttachment(screenshot: app.screenshot())
                proof.name = id
                proof.lifetime = .keepAlways
                add(proof)
            }
            if index + 1 < scenarios.count {
                app.buttons["calc.evidence.next"].tap()
            }
        }
        let failed = measurements.filter { $0.verdict == "mismatch" }.map(\.id)
        XCTAssertTrue(failed.isEmpty, "不一致: " + failed.joined(separator: "、"))
        print("CALC 実 UI: 一致 \(measurements.filter { $0.verdict == "match" }.count) / 不一致 \(failed.count) / 対象外 \(measurements.filter { $0.verdict == "excluded" }.count)")
    }
}
