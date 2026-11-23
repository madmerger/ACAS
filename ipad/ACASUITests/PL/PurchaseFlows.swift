import XCTest

@MainActor
final class PurchaseFlows: XCTestCase {
    func testPL001() throws { try verify(1) }
    func testPL002() throws { try verify(2) }
    func testPL003() throws { try verify(3) }
    func testPL004() throws { try verify(4) }
    func testPL005() throws { try verify(5) }
    func testPL006() throws { try verify(6) }
    func testPL007() throws { try verify(7) }
    func testPL008() throws { try verify(8) }
    func testPL009() throws { try verify(9) }
    func testPL010() throws { try verify(10) }
    func testPL011() throws { try verify(11) }
    func testPL012() throws { try verify(12) }
    func testPL013() throws { try verify(13) }
    func testPL014() throws { try verify(14) }
    func testPL015() throws { try verify(15) }
    func testPL016() throws { try verify(16) }
    func testPL017() throws { try verify(17) }
    func testPL018() throws { try verify(18) }
    func testPL019() throws { try verify(19) }
    func testPL020() throws { try verify(20) }
    func testPL021() throws { try verify(21) }
    func testPL022() throws { try verify(22) }
    func testPL090() throws { try verify(90) }
    func testPL200() throws { try verify(200) }
    func testPL201() throws { try verify(201) }
    func testPL202() throws { try verify(202) }
    func testPL203() throws { try verify(203) }
    func testPL204() throws { try verify(204) }
    func testPL205() throws { try verify(205) }
    func testPL206() throws { try verify(206) }
    func testPL207() throws { try verify(207) }
    func testPL208() throws { try verify(208) }
    func testPL209() throws { try verify(209) }
    func testPL210() throws { try verify(210) }
    func testPL211() throws { try verify(211) }
    func testPL212() throws { try verify(212) }
    func testPL213() throws { try verify(213) }
    func testPL214() throws { try verify(214) }
    func testPL215() throws { try verify(215) }
    func testPL216() throws { try verify(216) }
    func testPL217() throws { try verify(217) }
    func testPL218() throws { try verify(218) }
    func testPL219() throws { try verify(219) }
    func testPL220() throws { try verify(220) }
    func testPL221() throws { try verify(221) }
    func testPL222() throws { try verify(222) }
    func testPL223() throws { try verify(223) }
    func testPL224() throws { try verify(224) }
    func testPL225() throws { try verify(225) }
    func testPL226() throws { try verify(226) }
    func testPL227() throws { try verify(227) }
    func testPL228() throws { try verify(228) }
    func testPL229() throws { try verify(229) }
    func testPL230() throws { try verify(230) }
    func testPL231() throws { try verify(231) }
    func testPL232() throws { try verify(232) }
    func testPL233() throws { try verify(233) }
    func testPL234() throws { try verify(234) }
    func testPL235() throws { try verify(235) }
    func testPL236() throws { try verify(236) }
    func testPL237() throws { try verify(237) }
    func testPL238() throws { try verify(238) }
    func testPL239() throws { try verify(239) }
    func testPL240() throws { try verify(240) }
    func testPL241() throws { try verify(241) }
    func testPL410() throws { try verify(410) }
    func testPL414() throws { try verify(414) }

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

    func testInvoiceSettingsRejectBlankNumericFields() throws {
        let app = try launch("PL-413", smokeID: "仕入伝票の固定設定")
        tap(app, "pl.invoice.settings.menu", scrolling: true)
        tap(app, "pl.invoice.settings.open")
        XCTAssertTrue(app.staticTexts["再利用できる削除済みの伝票番号がある場合は、そちらを先に使います。"].exists)
        let folio = "pl.invoice.settings.nextFolio"
        let vat = "pl.invoice.settings.vatAccount"
        let save = "pl.invoice.settings.save"
        let error = app.alerts.staticTexts["次の伝票番号は1から8桁の正の整数、消費税勘定科目コードは6桁以内の整数で入力してください。"]

        enter(app, folio, "", replacing: true)
        dismissKeyboard(app)
        tap(app, save)
        XCTAssertTrue(error.waitForExistence(timeout: 5), "次の伝票番号の空欄を拒否してください")
        app.alerts.buttons["閉じる"].tap()

        enter(app, folio, "240", replacing: true)
        enter(app, vat, "", replacing: true)
        dismissKeyboard(app)
        tap(app, save)
        XCTAssertTrue(error.waitForExistence(timeout: 5), "消費税勘定科目コードの空欄を拒否してください")
        app.alerts.buttons["閉じる"].tap()

        enter(app, vat, "500001", replacing: true)
        dismissKeyboard(app)
        tap(app, save)
        XCTAssertTrue(app.textFields[folio].waitForNonExistence(timeout: 5), "固定設定を保存するとフォームが閉じます")
        tap(app, "pl.invoice.settings.open")
        XCTAssertEqual(app.textFields[folio].value as? String, "240")
        XCTAssertEqual(app.textFields[vat].value as? String, "500001")
    }

    func testDuplicateInvoiceShowsNextFolioGuidance() throws {
        let app = try launch("PL-413", smokeID: "重複した仕入伝票番号の案内")
        tap(app, "pl.invoice.settings.menu", scrolling: true)
        tap(app, "pl.invoice.settings.open")
        enter(app, "pl.invoice.settings.nextFolio", "1", replacing: true)
        dismissKeyboard(app)
        tap(app, "pl.invoice.settings.save")
        tap(app, "pl.invoice.settings.add")
        enter(app, "pl.invoice.supplier", "SUPP018")
        dismissKeyboard(app)
        enter(app, "pl.invoice.line.0.code", "a1", scrolling: true)
        dismissKeyboard(app)
        enter(app, "pl.invoice.line.0.net", "100", replacing: true, scrolling: true)
        dismissKeyboard(app)
        tap(app, "pl.invoice.save", scrolling: true)
        XCTAssertTrue(app.alerts.staticTexts["伝票番号が使用済みのため、次の番号に進めました。固定設定で空き番号を設定できます。"]
            .waitForExistence(timeout: 5))
    }

    func testChequeScheduleRejectsMissingAgeAndGeneratesReport() throws {
        let app = try launch("PL-413", smokeID: "小切手の支払予定")
        tap(app, "pl.cheques", scrolling: true)
        tap(app, "pl.cheques.generate")
        enter(app, "pl.cheques.age", "", replacing: true)
        dismissKeyboard(app)
        tap(app, "pl.cheques.run")
        XCTAssertTrue(app.alerts.staticTexts["経過日数は0〜99の整数で入力してください。"].waitForExistence(timeout: 5))
        app.alerts.buttons["閉じる"].tap()
        enter(app, "pl.cheques.age", "0", replacing: true)
        dismissKeyboard(app)
        tap(app, "pl.cheques.run")
        XCTAssertTrue(app.buttons["pl.cheques.share"].waitForExistence(timeout: 5))
    }

    func testPeriodCloseRequiresConfirmation() throws {
        let app = try launch("PL-413", smokeID: "買掛の期間締め")
        tap(app, "pl.period.close", scrolling: true)
        XCTAssertTrue(app.navigationBars["買掛の期間締め"].waitForExistence(timeout: 5))
        tap(app, "pl.period.close.run")
        XCTAssertTrue(app.buttons["pl.period.close.confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["pl.period.close.completed"].exists)
    }

    func testSupplierFileReportsWithoutMatchingRecordsCannotBeShared() throws {
        let app = try launch("PL-413", smokeID: "仕入先ファイル帳票")
        tap(app, "pl.report.supplier_file", scrolling: true)
        XCTAssertTrue(app.navigationBars["仕入先ファイル帳票"].waitForExistence(timeout: 5))
        tap(app, "pl.report.generate", scrolling: true)
        XCTAssertTrue(app.descendants(matching: .any)["pl.report.share"].firstMatch.waitForExistence(timeout: 5))
        tap(app, "pl.report.preview")
        XCTAssertTrue(app.staticTexts["原本の内容"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Purchase Ledger Dump")).firstMatch.exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "買掛帳票プレビュー"
        preview.lifetime = .keepAlways
        add(preview)
        tap(app, "pl.report.preview.close")
        app.swipeDown()
        enter(app, "pl.report.supplier", "MISS001")
        dismissKeyboard(app)
        tap(app, "pl.report.generate", scrolling: true)
        XCTAssertTrue(app.staticTexts["pl.report.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["pl.report.share"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["pl.report.preview"].firstMatch.exists)
    }

    func testSupplierReportPreviewSplitsJapaneseTextAcrossPages() throws {
        let japaneseName = "日本語仕入先"
        let app = try launch("PL-413", smokeID: "複数ページの仕入先帳票") { fixture in
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
            var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: seed) as? [String: Any])
            var files = try XCTUnwrap(snapshot["files"] as? [String: Any])
            let path = "ledgers/acas/purchled.dat"
            var indexed = try XCTUnwrap(files[path] as? [String: Any])
            var records = try XCTUnwrap(indexed["records"] as? [[String]])
            let prototype = try XCTUnwrap(records.first?[1])
            let name = try XCTUnwrap(japaneseName.data(using: .shiftJIS))
            let nameField = name.map { String(format: "%02x", $0) }.joined()
                + String(repeating: "20", count: 30 - name.count)
            for number in 1...5 {
                let key = String(format: "ZZZZZ%02d", number).utf8.map { String(format: "%02x", $0) }.joined()
                let bytes = key + String(prototype.dropFirst(14))
                records.append([key, number == 5
                    ? String(bytes.prefix(18)) + nameField + String(bytes.dropFirst(78)) : bytes])
            }
            indexed["records"] = records
            files[path] = indexed
            snapshot["files"] = files
            fixture["seed"] = try JSONSerialization.data(withJSONObject: snapshot).base64EncodedString()
        }
        tap(app, "pl.report.supplier_file", scrolling: true)
        tap(app, "pl.report.generate", scrolling: true)
        tap(app, "pl.report.preview", scrolling: true)
        let preview = app.scrollViews["pl.report.preview.lines"]
        let name = preview.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", japaneseName)).firstMatch
        for _ in 0..<5 where !name.exists || !name.isHittable { preview.swipeUp() }
        XCTAssertTrue(name.exists && name.isHittable)
        XCTAssertTrue(name.label.contains("Purch-Name"))
        let page = preview.staticTexts.matching(identifier: "pl.report.preview.page")
            .matching(NSPredicate(format: "label == %@", "2"))
        XCTAssertTrue(page.allElementsBoundByIndex.contains(where: \.isHittable))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "仕入先帳票の2ページ目・日本語名"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEmptyPaymentProofCannotGenerateReport() throws {
        let app = try launch("PL-413", smokeID: "空の支払検証")
        tap(app, "pl.payment.proof", scrolling: true)
        let button = app.buttons["pl.payment.proof.generate"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertFalse(button.isEnabled)
    }

    private func launch(_ id: String, smokeID: String? = nil, openPurchases: Bool = true,
                        configure: (inout [String: Any]) throws -> Void = { _ in }) throws -> XCUIApplication {
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
            try configure(&fixture)
            data = try JSONSerialization.data(withJSONObject: fixture)
        }
        let app = XCUIApplication()
        app.launchEnvironment["ACAS_FIXTURE"] = data.base64EncodedString()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts[smokeID ?? id].waitForExistence(timeout: 10))
        if smokeID == nil { print("ACAS_PL_START|\(id)|\(Date().timeIntervalSince1970)") }
        if openPurchases {
            tap(app, "section.purchases")
            tap(app, "pl.date.confirm")
        }
        return app
    }

    private struct Route {
        let links: [String]
        let title: String
        var action: String?
        init(_ links: String..., title: String, action: String? = nil) {
            self.links = links
            self.title = title
            self.action = action
        }
    }

    private static let routes: [Int: Route] = [
        200: Route(title: "買掛元帳"),
        201: Route("pl.date", title: "処理日入力"),
        202: Route("pl.suppliers", title: "仕入先マスター管理"),
        203: Route("pl.suppliers", "pl.supplier.add", title: "仕入先登録"),
        204: Route("pl.suppliers", "pl.supplier.edit", title: "仕入先変更"),
        205: Route("pl.suppliers", "pl.supplier.delete", title: "仕入先削除"),
        206: Route("pl.report.supplier_file", title: "仕入先ファイル帳票"),
        207: Route("pl.suppliers", "pl.supplier.show", title: "仕入先表示"),
        208: Route("pl.enquiry", title: "買掛残高・明細照会"),
        209: Route("pl.transaction.add", title: "仕入取引入力"),
        210: Route("pl.transaction.edit", title: "仕入取引修正"),
        211: Route("pl.transaction.delete", title: "仕入取引削除"),
        212: Route("pl.transaction.proof", title: "仕入の検証帳票"),
        213: Route("pl.transaction.post", title: "仕入転記"),
        214: Route("pl.payment.add", title: "支払入力・消込"),
        215: Route("pl.payment.edit", title: "支払修正"),
        216: Route("pl.payment.proof", title: "支払検証帳票"),
        217: Route("pl.payment.post", title: "支払転記"),
        218: Route("pl.analysis", title: "仕入分析コード管理"),
        219: Route("pl.analysis", "pl.analysis.add", title: "仕入分析コード登録"),
        220: Route("pl.analysis", title: "仕入分析コード管理"),
        221: Route("pl.analysis", "pl.report.analysis_codes", title: "買掛の分析コードを印刷", action: "pl.report.generate"),
        222: Route("pl.analysis", "pl.report.all_analysis_codes", title: "全元帳の分析コードを印刷", action: "pl.report.generate"),
        223: Route("pl.analysis", title: "仕入分析コード管理"),
        224: Route("pl.report.analysis", title: "買掛分析帳票を作成"),
        225: Route("pl.report.day_book", title: "仕入日計帳"),
        226: Route("pl.report.aged", title: "買掛金年齢表"),
        227: Route("pl.suppliers.alphabetical", title: "仕入先名順一覧"),
        228: Route("pl.report.turnover", title: "仕入先別取引帳票"),
        229: Route("pl.cheques", title: "支払予定・小切手・送金"),
        230: Route("pl.cheques", "pl.cheques.generate", title: "支払予定を作成"),
        231: Route("pl.cheques", "pl.cheques.amend", title: "支払予定を修正"),
        232: Route("pl.cheques", "pl.cheques.proof", title: "支払予定を検証", action: "pl.cheques.run"),
        233: Route("pl.cheques", "pl.cheques.issue", title: "小切手・振込データを作成"),
        234: Route("pl.cheques", "pl.cheques.register", title: "小切手・振込を台帳へ登録"),
        235: Route("pl.cheques", "pl.cheques.remittance", title: "送金案内を作成"),
        236: Route("pl.period.close", title: "買掛の期間締め"),
        237: Route("pl.invoice.settings.menu", "pl.invoice.settings.open", title: "仕入伝票の固定設定"),
        238: Route("pl.report.supplier_file", title: "仕入先ファイル帳票"),
        239: Route("section.system", title: "システム設定"),
        240: Route("pl.settings", "system.company", title: "会社設定"),
        241: Route(title: "処理日入力"),
    ]

    private static let menuCases = [
        201, 202, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 224, 225, 226,
        227, 228, 229, 236, 237, 238,
    ]

    private func verify(_ number: Int) throws {
        let id = String(format: "PL-%03d", number)
        let app = try launch(id, openPurchases: false)
        if number == 90 {
            tap(app, "system.company")
            enter(app, "system.company.name", "EQUIVALENCE BUSINESS")
            tap(app, "action.save")
        }
        tap(app, "section.purchases")
        if [1, 241].contains(number) {
            XCTAssertTrue(app.descendants(matching: .any)["pl.date.value"].firstMatch.waitForExistence(timeout: 5))
        }
        tap(app, "pl.date.confirm")

        switch number {
        case 90:
            tap(app, "pl.suppliers")
            let addSupplier = app.descendants(matching: .any).matching(identifier: "pl.supplier.add").firstMatch
            let returnedToMenu = NSPredicate(format: "exists == true AND hittable == true")
            for (code, name, address) in [
                ("SUPP01", "ALPHA SUPPLIER", "1 SUPPLY ROAD\\LONDON\\UK"),
                ("SUPP02", "BETA SUPPLIER", "2 SUPPLY ROAD\\LONDON\\UK"),
            ] {
                tap(app, "pl.supplier.add")
                enter(app, "pl.supplier.code", code)
                enter(app, "pl.supplier.name", name)
                enter(app, "pl.supplier.address", address)
                dismissKeyboard(app)
                XCTAssertEqual(app.textFields["pl.supplier.code"].value as? String, code)
                tap(app, "pl.supplier.save", scrolling: true)
                let menu = XCTNSPredicateExpectation(predicate: returnedToMenu, object: addSupplier)
                XCTAssertEqual(XCTWaiter.wait(for: [menu], timeout: 10), .completed,
                               "\(code): 保存後に仕入先マスター管理へ戻りませんでした")
            }
        case 410:
            tap(app, "pl.analysis", scrolling: true)
            tap(app, "pl.analysis.add")
            enter(app, "分析コード", "A")
            enter(app, "勘定科目コード", "500001", replacing: true)
            enter(app, "名称", "PURCHASES")
            dismissKeyboard(app)
            XCTAssertEqual(app.textFields["名称"].value as? String, "PURCHASES")
        case 414:
            tap(app, "pl.transaction.post", scrolling: true)
            tap(app, "pl.post.start")
            tap(app, "pl.post.confirm")
            XCTAssertTrue(app.staticTexts["pl.transaction.number"].firstMatch.waitForExistence(timeout: 5))
        case 1, 241:
            break
        default:
            let routeNumber = (1...22).contains(number) ? Self.menuCases[number - 1] : number
            let route = try XCTUnwrap(Self.routes[routeNumber])
            for link in route.links { tap(app, link, scrolling: true) }
            XCTAssertTrue(app.navigationBars[route.title].waitForExistence(timeout: 5)
                          || app.staticTexts[route.title].firstMatch.exists, route.title)
            if let action = route.action { tap(app, action, scrolling: true) }
            if app.alerts.firstMatch.exists { app.alerts.buttons["閉じる"].tap() }
        }

        tap(app, "case.compare")
        let match = app.staticTexts["case.verdict.match"]
        let mismatch = app.staticTexts["case.verdict.mismatch"]
        let outside = app.staticTexts["case.verdict.out_of_scope"]
        let verdict = [match, mismatch, outside].first { $0.exists }
        let result = try XCTUnwrap(verdict).identifier
        let reason = verdict?.value as? String ?? ""
        print("ACAS_PL_RESULT|\(id)|\(result)|\(reason)")
        if number == 90 { RunLoop.current.run(until: Date().addingTimeInterval(2)) }
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertNotEqual(result, "case.verdict.mismatch", reason)
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
        if !value.isEmpty { field.typeText(value) }
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
        let result = match ? "case.verdict.match" : "case.verdict.mismatch"
        print("ACAS_PL_RESULT|\(id)|\(result)|")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = id
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertTrue(match, "\(id) の判定が異なります")
    }
}
