import XCTest

@MainActor
final class SalesReachFlows: XCTestCase {
    func testSL002() throws { try customerMenu("SL-002") }
    func testSL004() throws { try salesEntry("SL-004") }
    func testSL005() throws { try salesAmendment("SL-005") }
    func testSL012() throws { try analysisMenu("SL-012") }
    func testSL202() throws { try customerMenu("SL-202") }
    func testSL203() throws { try customer("SL-203", mode: "register", title: "得意先登録") }
    func testSL204() throws { try customer("SL-204", mode: "edit", title: "得意先変更") }
    func testSL205() throws { try customer("SL-205", mode: "remove", title: "得意先削除") }
    func testSL207() throws { try customer("SL-207", mode: "view", title: "得意先表示") }
    func testSL209() throws { try salesEntry("SL-209") }
    func testSL210() throws { try salesAmendment("SL-210") }
    func testSL217() throws { try analysisMenu("SL-217") }

    func testSL218() throws {
        try reach("SL-218", through: ["sales.analysis.codes", "sales.analysis.add"], title: "売上分析コード登録") { app in
            for (field, placeholder) in [("group", "分析コード"), ("account", "勘定科目コード"),
                                         ("description", "名称"), ("printCode", "印字コード")] {
                let input = app.textFields["sales.analysis." + field]
                XCTAssertTrue(input.exists)
                XCTAssertEqual(input.value as? String, placeholder)
            }
            XCTAssertTrue(app.buttons["sales.analysis.save"].exists)
        }
    }

    func testSL231() throws {
        try reach("SL-231", through: ["sales.invoice.menu"], title: "請求書サブシステム") { app in
            XCTAssertTrue(app.buttons["sales.invoice.pending"].exists)
            XCTAssertTrue(app.buttons["sales.invoice.print"].exists)
        }
    }

    func testSL232() throws { try invoiceEntry("SL-232", operation: "pending", title: "請求書登録", save: "保存") }
    func testSL233() throws { try invoiceEntry("SL-233", operation: "immediate", title: "請求書即時印刷", save: "保存して印刷") }

    func testSL234() throws {
        try reach("SL-234", through: ["sales.invoice.menu", "sales.invoice.amend"], title: "請求書修正") { app in
            XCTAssertTrue(app.buttons["00000000"].exists)
        }
    }

    func testSL235() throws {
        try reach("SL-235", through: ["sales.invoice.menu", "sales.invoice.remove"], title: "請求書削除") { app in
            XCTAssertTrue(app.staticTexts["00000000"].exists)
            XCTAssertTrue(app.buttons["削除"].exists)
        }
    }

    private func customerMenu(_ id: String) throws {
        try reach(id, through: ["sales.customers"], title: "得意先マスター管理") { app in
            for operation in ["register", "edit", "remove", "report", "view"] {
                XCTAssertTrue(app.buttons["sales.customer." + operation].exists)
            }
        }
    }

    private func analysisMenu(_ id: String) throws {
        try reach(id, through: ["sales.analysis.codes"], title: "売上分析コード管理") { app in
            for operation in ["add", "edit", "print", "printAll", "display"] {
                XCTAssertTrue(app.buttons["sales.analysis." + operation].exists)
            }
        }
    }

    private func customer(_ id: String, mode: String, title: String) throws {
        try reach(id, through: ["sales.customers", "sales.customer." + mode], title: title) { app in
            XCTAssertTrue(app.textFields["sales.customer.code"].exists)
            if mode == "register" {
                XCTAssertTrue(app.textFields["sales.customer.name"].exists)
                XCTAssertTrue(app.buttons["sales.customer.save"].exists)
            } else {
                XCTAssertTrue(app.buttons["sales.customer.search"].exists)
                XCTAssertFalse(app.buttons["sales.customer.save"].exists)
                XCTAssertFalse(app.buttons["sales.customer.delete"].exists)
            }
        }
    }

    private func salesEntry(_ id: String) throws {
        try reach(id, through: ["sales.invoice.sale"], title: "売上取引入力") { app in
            assertInvoiceForm(app, save: "保存")
        }
    }

    private func salesAmendment(_ id: String) throws {
        try reach(id, through: ["sales.invoice.amendSale"], title: "請求書修正") { app in
            XCTAssertTrue(app.staticTexts["請求書がありません"].exists)
        }
    }

    private func invoiceEntry(_ id: String, operation: String, title: String, save: String) throws {
        try reach(id, through: ["sales.invoice.menu", "sales.invoice." + operation], title: title) { app in
            assertInvoiceForm(app, save: save)
        }
    }

    private func assertInvoiceForm(_ app: XCUIApplication, save: String) {
        XCTAssertTrue(app.textFields["sales.invoice.customer"].exists)
        XCTAssertTrue(app.textFields["sales.invoice.reference"].exists)
        XCTAssertTrue(app.textFields["sales.invoice.order"].exists)
        XCTAssertEqual(app.buttons["sales.invoice.save"].label, save)
    }

    private func reach(_ id: String, through route: [String], title: String,
                       check: (XCUIApplication) -> Void) throws {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let first = bundle.url(forResource: "SL-002", withExtension: "json", subdirectory: "fixtures")
        try XCTSkipIf(first == nil, "generate_reach_fixtures.py で到達確認の証跡を準備してください")
        let url = try XCTUnwrap(bundle.url(forResource: id, withExtension: "json", subdirectory: "fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = try Data(contentsOf: url).base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[id].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["case.verdict.running"].exists)
        for identifier in ["section.sales", "sales.date.save"] + route {
            let button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if identifier == "sales.analysis.codes", !button.isHittable {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(button.isHittable, identifier)
            button.tap()
        }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), title)
        check(app)
        XCTAssertTrue(app.staticTexts["case.verdict.match"].waitForExistence(timeout: 5), id)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = id
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
