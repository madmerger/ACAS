import XCTest

@MainActor
final class SalesReachFlows: XCTestCase {
    func testSL003() throws { try unavailableSalesMenuItem("SL-003", labels: ["売掛残高", "明細照会"]) }
    func testSL017() throws { try unavailableSalesMenuItem("SL-017", labels: ["売掛金年齢表", "年齢分析"]) }
    func testSL208() throws { try unavailableSalesMenuItem("SL-208", labels: ["売掛残高", "明細照会"]) }
    func testSL227() throws { try unavailableSalesMenuItem("SL-227", labels: ["売掛金年齢表", "年齢分析"]) }

    func testSL090() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SL-090", withExtension: "json",
                                                          subdirectory: "fixtures"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let customers = try XCTUnwrap(fixture["customers"] as? [String: String])
        XCTAssertEqual(customers.count, 2)
        try reach("SL-090", through: ["sales.customers", "sales.customer.view"],
                  title: "得意先表示", verdict: nil) { app in
            let field = app.textFields["sales.customer.code"]
            let name = app.descendants(matching: .any)["sales.customer.summary.name"].firstMatch
            var previous = ""
            for (code, expectedName) in customers.sorted(by: { $0.key < $1.key }) {
                field.tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + code)
                app.buttons["sales.customer.search"].tap()
                XCTAssertTrue(name.waitForExistence(timeout: 5))
                XCTAssertEqual(name.value as? String, expectedName)
                attach(app, name: "SL-090-\(code)")
                previous = code
            }
        }
    }

    func testSL002() throws { try customerMenu("SL-002") }
    func testSL004() throws { try salesEntry("SL-004") }
    func testSL005() throws { try salesAmendment("SL-005") }
    func testSL006() throws { try noTransactionsToProof("SL-006") }
    func testSL007() throws { try missingPostingWorkFile("SL-007") }
    func testSL008() throws { try paymentEntry("SL-008") }
    func testSL009() throws { try paymentAmend("SL-009") }
    func testSL010() throws { try paymentProof("SL-010") }
    func testSL011() throws { try paymentPost("SL-011") }
    func testSL012() throws { try analysisMenu("SL-012") }
    func testSL013() throws { try missingAnalysisTotals("SL-013") }
    func testSL014() throws { try missingDayBook("SL-014") }
    func testSL015() throws { try missingOpenItems("SL-015", screen: "statement", title: "得意先明細書") }
    func testSL016() throws { try missingOpenItems("SL-016", screen: "dunning", title: "督促状出力") }
    func testSL020() throws { try invoiceFixedData("SL-020") }
    func testSL021() throws { try periodConfirmation("SL-021") }
    func testSL022() throws { try customerReport("SL-022") }

    func testSL091() throws {
        try reach("SL-091", through: ["sales.analysis.codes", "sales.analysis.add"],
                  title: "売上分析コード登録", verdict: "mismatch") { app in
            for (field, text) in [("group", "A"), ("account", "400001"), ("description", "SALES")] {
                let input = app.textFields["sales.analysis." + field]
                XCTAssertTrue(input.isHittable, field)
                input.tap()
                input.typeText(text)
            }
            XCTAssertEqual(app.textFields["sales.analysis.printCode"].value as? String, "A")
            app.buttons["sales.analysis.save"].tap()
            let display = app.buttons["sales.analysis.display"]
            XCTAssertTrue(display.waitForExistence(timeout: 5))
            display.tap()
            let row = app.descendants(matching: .any)["sales.analysis.code.SA"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains("SALES"))
            XCTAssertEqual(row.value as? String, "400001")
        }
    }

    func testSL202() throws { try customerMenu("SL-202") }
    func testSL203() throws { try customer("SL-203", mode: "register", title: "得意先登録") }
    func testSL204() throws { try customer("SL-204", mode: "edit", title: "得意先変更") }
    func testSL205() throws { try customer("SL-205", mode: "remove", title: "得意先削除") }
    func testSL207() throws { try customer("SL-207", mode: "view", title: "得意先表示") }
    func testSL209() throws { try salesEntry("SL-209") }
    func testSL210() throws { try salesAmendment("SL-210") }
    func testSL211() throws { try noTransactionsToProof("SL-211") }
    func testSL212() throws { try missingPostingWorkFile("SL-212") }
    func testSL213() throws { try paymentEntry("SL-213") }
    func testSL214() throws { try paymentAmend("SL-214") }
    func testSL215() throws { try paymentProof("SL-215") }
    func testSL216() throws { try paymentPost("SL-216") }
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

    func testSL219() throws { try emptyAnalysisList("SL-219", operation: "edit", title: "売上分析コード変更・削除") }
    func testSL222() throws { try emptyAnalysisList("SL-222", operation: "display", title: "売上分析コード表示") }
    func testSL223() throws { try missingAnalysisTotals("SL-223") }
    func testSL224() throws { try missingDayBook("SL-224") }
    func testSL225() throws { try missingOpenItems("SL-225", screen: "statement", title: "得意先明細書") }
    func testSL226() throws { try missingOpenItems("SL-226", screen: "dunning", title: "督促状出力") }

    func testSL230() throws { try invoiceFixedData("SL-230") }
    func testSL231() throws { try invoiceFixedData("SL-231", nextNumber: "10000000") }

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

    func testSL236() throws {
        try reach("SL-236", through: ["sales.invoice.menu", "sales.invoice.deletionReport"], title: "請求書削除帳票") { app in
            app.buttons["sales.invoice.deletionReport.generate"].tap()
            let result = app.staticTexts["sales.invoice.deletionReport.result"]
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            XCTAssertEqual(result.label, "帳票に記載する削除済み請求書はありません")
            XCTAssertTrue(app.buttons["sales.invoice.deletionReport.export"].exists)
        }
    }

    func testSL237() throws {
        try reach("SL-237", through: ["sales.invoice.menu", "sales.invoice.print"],
                  title: "請求書一括印刷", verdict: "mismatch") { app in
            let reprint = app.switches["印刷済みを再印刷"]
            XCTAssertTrue(reprint.exists)
            XCTAssertEqual(reprint.value as? String, "0")
            XCTAssertTrue(app.buttons["sales.invoice.generate"].exists)
            XCTAssertFalse(app.buttons["sales.invoice.export"].exists)
        }
    }

    func testSL239() throws { try periodConfirmation("SL-239") }
    func testSL240() throws { try customerReport("SL-240") }
    func testSL238() throws {
        try reach("SL-238", through: ["sales.invoice.menu"], title: "請求書サブシステム", verdict: nil) { app in
            XCTAssertTrue(app.buttons["sales.invoice.print"].exists)
            XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
                                                                "納品書", "ピッキング")).firstMatch.exists)
        }
    }

    func testSL241() throws {
        try reach("SL-241", through: ["section.system"], title: "システム設定", verdict: nil) { app in
            for section in ["general", "sales", "purchases", "stock", "system"] {
                XCTAssertTrue(app.buttons["section." + section].exists)
            }
            XCTAssertFalse(app.buttons["sales.customers"].exists)
        }
    }

    func testSL242() throws {
        try reach("SL-242", through: ["section.system", "system.company"], title: "会社設定", verdict: nil) { app in
            XCTAssertEqual(app.textFields["system.company.name"].value as? String, "EQUIVALENCE BUSINESS")
            XCTAssertEqual(app.textFields.count, 1)
        }
    }
    func testSL244() throws { try invoiceFixedData("SL-244") }

    private func unavailableSalesMenuItem(_ id: String, labels: [String]) throws {
        try reach(id, through: [], title: "売掛元帳", verdict: nil) { app in
            func check() {
                for label in labels {
                    XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", label)).firstMatch.exists)
                }
            }
            XCTAssertTrue(app.buttons["sales.customers"].exists)
            check()
            attach(app, name: "\(id)-売掛メニュー上部")
            let last = app.buttons["sales.customer.turnover"]
            for _ in 0..<4 where !last.isHittable {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.34)))
                check()
            }
            XCTAssertTrue(last.isHittable)
        }
    }

    private func customerMenu(_ id: String) throws {
        try reach(id, through: ["sales.customers"], title: "得意先マスター管理") { app in
            for operation in ["register", "edit", "remove", "report", "view"] {
                XCTAssertTrue(app.buttons["sales.customer." + operation].exists)
            }
        }
    }

    private func noTransactionsToProof(_ id: String) throws {
        try reach(id, through: ["sales.proof"], title: "未転記売上取引の確認帳票") { app in
            let generate = app.buttons["action.generate"]
            XCTAssertTrue(generate.isHittable)
            generate.tap()
            XCTAssertTrue(app.alerts.staticTexts["確認する売上取引がありません"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.tables["sales.proof.preview"].exists)
        }
    }

    private func missingOpenItems(_ id: String, screen: String, title: String) throws {
        try reach(id, through: ["sales." + screen], title: title,
                  verdict: screen == "dunning" ? "mismatch" : "match") { app in
            let failure = app.staticTexts["sales." + screen + ".error"]
            XCTAssertTrue(failure.waitForExistence(timeout: 5))
            XCTAssertEqual(failure.label, "売掛明細のファイルがありません")
            XCTAssertFalse(app.buttons["sales.statement.generate"].exists)
            XCTAssertFalse(app.buttons["sales.dunning.next"].exists)
        }
    }

    private func missingPostingWorkFile(_ id: String) throws {
        try reach(id, through: ["sales.post"], title: "売上転記") { app in
            let message = app.staticTexts["sales.post.unavailable"]
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertEqual(message.label, "売上転記に必要な作業ファイルがありません")
            XCTAssertFalse(app.buttons["sales.post.start"].exists)
            XCTAssertFalse(app.buttons["sales.post.export"].exists)
        }
    }

    private func periodConfirmation(_ id: String) throws {
        try reach(id, through: ["sales.period"], title: "売掛元帳の期間締め") { app in
            XCTAssertTrue(app.staticTexts["sales.period.notice"].exists)
            XCTAssertEqual(app.switches["sales.period.backedUp"].value as? String, "0")
            XCTAssertFalse(app.buttons["sales.period.execute"].exists)
        }
    }

    private func customerReport(_ id: String) throws {
        try reach(id, through: ["sales.customers", "sales.customer.report"], title: "得意先一覧印刷") { app in
            XCTAssertTrue(app.staticTexts["抽出条件"].exists)
            XCTAssertEqual(app.textFields["得意先コードの先頭"].value as? String, "得意先コードの先頭")
            XCTAssertTrue(app.buttons["sales.customer.report.generate"].exists)
        }
    }

    private func analysisMenu(_ id: String) throws {
        try reach(id, through: ["sales.analysis.codes"], title: "売上分析コード管理") { app in
            for operation in ["add", "edit", "print", "printAll", "display"] {
                XCTAssertTrue(app.buttons["sales.analysis." + operation].exists)
            }
        }
    }

    private func emptyAnalysisList(_ id: String, operation: String, title: String) throws {
        try reach(id, through: ["sales.analysis.codes", "sales.analysis." + operation], title: title) { app in
            XCTAssertFalse(app.staticTexts["sales.analysis.error"].exists)
            let codes = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sales.analysis.code."))
            XCTAssertEqual(codes.count, 0)
        }
    }

    private func missingAnalysisTotals(_ id: String) throws {
        try reach(id, through: ["sales.analysis.totals"], title: "売上分析帳票") { app in
            XCTAssertTrue(app.buttons["sales.analysis.generate"].isHittable)
            app.buttons["sales.analysis.generate"].tap()
            XCTAssertTrue(app.staticTexts["集計ファイルがありません"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["sales.analysis.export"].exists)
        }
    }

    private func missingDayBook(_ id: String) throws {
        try reach(id, through: ["sales.dayBook"], title: "売上日計簿") { app in
            XCTAssertTrue(app.buttons["sales.dayBook.generate"].isHittable)
            app.buttons["sales.dayBook.generate"].tap()
            XCTAssertTrue(app.staticTexts["売上日計簿に必要なファイルがありません"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["sales.dayBook.export"].exists)
        }
    }

    private func paymentEntry(_ id: String) throws {
        try blockedPayment(id, operation: "entry", title: "入金登録",
                           error: "売掛明細のファイルがありません", action: "sales.payment.findInvoices")
    }

    private func paymentAmend(_ id: String) throws {
        try blockedPayment(id, operation: "amend", title: "入金修正",
                           error: "対象の入金がありません", action: "sales.payment.reverse")
    }

    private func paymentProof(_ id: String) throws {
        try blockedPayment(id, operation: "proof", title: "入金検証帳票",
                           error: "対象の入金がありません", action: "sales.payment.proof.generate")
    }

    private func paymentPost(_ id: String) throws {
        try blockedPayment(id, operation: "post", title: "入金転記",
                           error: "入金を転記できませんでした。先に入金検証帳票を作成してください",
                           action: "sales.payment.post.start")
    }

    private func blockedPayment(_ id: String, operation: String, title: String,
                                error: String, action: String) throws {
        try reach(id, through: ["sales.payment." + operation], title: title) { app in
            let message = app.staticTexts["sales.payment.unavailable"]
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertEqual(message.label, error)
            XCTAssertFalse(app.buttons[action].exists)
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

    private func invoiceFixedData(_ id: String, nextNumber: String? = nil) throws {
        try reach(id, through: ["sales.invoice.menu"], title: "請求書固定項目設定") { app in
            let number = app.textFields["sales.invoice.fixed.nextInvoice"]
            XCTAssertEqual(number.value as? String, "00000000")
            XCTAssertEqual(app.textFields["sales.invoice.fixed.extraRate"].value as? String, "00.00")
            XCTAssertFalse(app.buttons["sales.invoice.pending"].exists)
            if let nextNumber {
                number.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
                number.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + nextNumber)
                XCTAssertEqual(number.value as? String, nextNumber)
            }
        }
    }

    private func assertInvoiceForm(_ app: XCUIApplication, save: String) {
        XCTAssertTrue(app.textFields["sales.invoice.customer"].exists)
        XCTAssertTrue(app.textFields["sales.invoice.reference"].exists)
        XCTAssertTrue(app.textFields["sales.invoice.order"].exists)
        XCTAssertEqual(app.buttons["sales.invoice.save"].label, save)
    }

    private func reach(_ id: String, through route: [String], title: String, verdict: String? = "match",
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
            for _ in 0..<3 where !button.isHittable {
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
        if let verdict {
            XCTAssertTrue(app.staticTexts["case.verdict." + verdict].waitForExistence(timeout: 5), id)
        }
        attach(app, name: id)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
