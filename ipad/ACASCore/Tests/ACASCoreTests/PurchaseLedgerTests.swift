import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class PurchaseLedgerTests: XCTestCase {
    func testAgedCreditorsCountsBypassedPaymentsBeforeButNotAfterSelectedSupplier() throws {
        let ledger = try makeLedger()
        let date = ledger.processingDate
        let day = try ledger.legacyDate(date)
        for (input, balance, discount): (String, Int64, Int64) in [
            ("SUPP01", 500, 100), ("SUPP02", 10_000, 200), ("SUPP03", 500, 300),
        ] {
            var supplier = ledger.newSupplier
            supplier.code = input
            supplier.name = input
            supplier.address1 = "1 MAIN ROAD\\CITY"
            let code = try ledger.saveSupplier(supplier, creating: true)
            var record = try XCTUnwrap(ledger.supplierRecord(code))
            record.setInt("purch-current", balance)
            XCTAssertTrue(ledger.store.rewrite(ledger.suppliersPath, key: record.raw("purch-key"), data: record.bytes))
            var payment = Record(PurchaseRecords.oiLayout)
            payment["oi-supplier"] = code
            payment.setInt("oi-invoice", 101)
            payment.setInt("oi-date", day)
            payment.setInt("oi-type", 5)
            payment.setInt("oi-deduct-amt", discount)
            XCTAssertTrue(ledger.store.write(ledger.openItemsPath, key: ledger.openItemKey(supplier: code, number: 101), data: payment.bytes))
        }
        var settings = ledger.system
        ledger.setFileFlag(29, in: &settings)
        try ledger.systemFile.write(1, settings.bytes)
        var totals = Record(PurchaseRecords.sys4Layout, bytes: try XCTUnwrap(ledger.systemFile.read(4)))
        totals.setInt("pl-os-bal-last-month", 11_300)
        var bytes = try XCTUnwrap(ledger.systemFile.read(4))
        bytes.replaceSubrange(0..<PurchaseRecords.sys4Layout.size, with: totals.bytes)
        try ledger.systemFile.write(4, bytes)

        _ = try ledger.agedCreditorsReport(date: date, minimum: 1_000)
        let result = Record(PurchaseRecords.sys4Layout, bytes: try XCTUnwrap(ledger.systemFile.read(4)))
        XCTAssertEqual(result.int("pl-variance"), 0)
    }

    func testAgedCreditorsSortsItemsAndWritesReconciliationOnlyWithoutSupplierFilter() throws {
        let ledger = try makeLedger()
        let supplier = try addSupplier(ledger)
        let date = ledger.processingDate
        XCTAssertThrowsError(try ledger.agedCreditorsReport(date: date)) {
            XCTAssertEqual($0 as? PurchaseLedger.PurchaseReportError, .missingOpenItems)
        }
        let day = try ledger.legacyDate(date)
        let ages: [Int64] = [95, 9, 33, 67]
        for (index, age) in ages.enumerated() {
            let number = Int64(index + 101)
            var item = Record(PurchaseRecords.oiLayout)
            item["oi-supplier"] = supplier
            item.setInt("oi-invoice", number)
            item.setInt("oi-date", day - age)
            item.setInt("oi-type", 2)
            item.setInt("oi-net", Int64(index + 1) * 10_000)
            XCTAssertTrue(ledger.store.write(ledger.openItemsPath, key: ledger.openItemKey(supplier: supplier, number: number), data: item.bytes))
        }
        var record = try XCTUnwrap(ledger.supplierRecord(supplier))
        record.setInt("purch-current", 90_000)
        record.setInt("purch-unapplied", 500)
        XCTAssertTrue(ledger.store.rewrite(ledger.suppliersPath, key: record.raw("purch-key"), data: record.bytes))
        var settings = ledger.system
        ledger.setFileFlag(29, in: &settings)
        settings.setInt("p-flag-p", 1)
        try ledger.systemFile.write(1, settings.bytes)
        XCTAssertThrowsError(try ledger.agedCreditorsReport(date: date)) {
            XCTAssertEqual($0 as? PurchaseLedger.PurchaseReportError, .proofRequired)
        }
        XCTAssertEqual(ledger.system.str("oi-5-flag"), "N")
        settings.setInt("p-flag-p", 0)
        try ledger.systemFile.write(1, settings.bytes)
        let bytes = try ledger.agedCreditorsReport(date: date, supplier: "SUPP01", alphabetical: true)
        let output = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(output.contains("Aged Creditors Report (Sorted)"))
        let old = try XCTUnwrap(output.range(of: "101  " + ledger.reportDate(day - 95)))
        let recent = try XCTUnwrap(output.range(of: "102  " + ledger.reportDate(day - 9)))
        XCTAssertLessThan(old.lowerBound, recent.lowerBound)
        XCTAssertTrue(output.contains("1,000.00"))
        XCTAssertFalse(output.contains("Reconciliation Data:"))
        XCTAssertEqual(ledger.store.readRaw(ledger.base + "poisort.wrk")?.count, 4 * 109)
        let unfiltered = try ledger.agedCreditorsReport(date: date)
        XCTAssertTrue(String(decoding: unfiltered, as: UTF8.self).contains("Reconciliation Data:"))
        let totals = Record(PurchaseRecords.sys4Layout, bytes: try XCTUnwrap(ledger.systemFile.read(4)))
        XCTAssertEqual(totals.int("pl-os-bal-this-month"), 89_500)
        XCTAssertEqual(totals.int("pl-variance"), 89_500)
    }

    func testSupplierReportsUseNameOrAccountOrderAndFilterDormantSuppliers() throws {
        let ledger = try makeLedger()
        var supplier = ledger.newSupplier
        supplier.address1 = "1 MAIN ROAD\\CITY"
        supplier.code = "SUPP01"
        supplier.name = "ZEBRA"
        let key1 = try ledger.saveSupplier(supplier, creating: true)
        supplier.code = "SUPP02"
        supplier.name = "ALPHA"
        let key2 = try ledger.saveSupplier(supplier, creating: true)
        try ledger.removeSupplier(code: key2, deactivate: true)
        func report(_ kind: PurchaseLedger.SupplierReport, _ filter: PurchaseLedger.SupplierReportFilter = .init()) throws -> String {
            String(decoding: try XCTUnwrap(ledger.supplierReport(kind, filter: filter)), as: UTF8.self)
        }
        let nameOrder = try report(.alphabetical)
        XCTAssertLessThan(try XCTUnwrap(nameOrder.range(of: "ALPHA")).lowerBound, try XCTUnwrap(nameOrder.range(of: "ZEBRA")).lowerBound)
        XCTAssertEqual(ledger.store.readRaw(ledger.supplierSortPath), [])
        let accountOrder = try report(.turnover)
        XCTAssertLessThan(try XCTUnwrap(accountOrder.range(of: "ZEBRA")).lowerBound, try XCTUnwrap(accountOrder.range(of: "ALPHA")).lowerBound)
        var filter = PurchaseLedger.SupplierReportFilter()
        filter.status = .dormant
        let file = try report(.file, filter)
        XCTAssertTrue(file.contains("ALPHA"))
        XCTAssertFalse(file.contains("ZEBRA"))
        filter.supplier = key1
        XCTAssertNil(try ledger.supplierReport(.file, filter: filter))
    }

    func testAnalysisCodeReportDistinguishesPurchaseAndAllLedgers() throws {
        let ledger = try makeLedger()
        var entry = PurchaseLedger.AnalysisCode()
        entry.code = "a"
        entry.name = "PURCHASE GROUP"
        try ledger.saveAnalysisCode(entry, creating: true)
        var sales = Record(PurchaseLedger.analysisLayout)
        sales["system"] = "S"
        sales["code"] = "b"
        sales["description"] = "SALES GROUP"
        XCTAssertTrue(ledger.store.write(ledger.analysisPath, key: Array("Sb ".utf8), data: sales.bytes))
        let purchase = String(decoding: try ledger.analysisCodeReport(), as: UTF8.self)
        XCTAssertTrue(purchase.contains("PURCHASE GROUP"))
        XCTAssertFalse(purchase.contains("SALES GROUP"))
        let all = String(decoding: try ledger.analysisCodeReport(allLedgers: true), as: UTF8.self)
        XCTAssertTrue(all.contains("PURCHASE GROUP"))
        XCTAssertTrue(all.contains("SALES GROUP"))
    }

    func testAdditionalPostingHidesSavedPurchaseAnalysisUntilRegenerated() throws {
        let ledger = try makeLedger()
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = try addSupplier(ledger)
        var code = PurchaseLedger.AnalysisCode()
        code.code = "a"
        try ledger.saveAnalysisCode(code, creating: true)
        code.code = "a1"
        try ledger.saveAnalysisCode(code, creating: true)
        invoice.lines[0].code = code.code
        invoice.lines[0].net = 10_000
        _ = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        let original = try XCTUnwrap(ledger.purchaseAnalysisReport())
        XCTAssertEqual(ledger.lastPurchaseAnalysisReport, original)

        _ = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        let reopened = PurchaseLedger(ledger.context)
        XCTAssertTrue(reopened.periodCloseStatus.needsPurchaseAnalysis)
        XCTAssertNil(reopened.lastPurchaseAnalysisReport)

        let updated = try XCTUnwrap(reopened.purchaseAnalysisReport())
        XCTAssertNotEqual(updated, original)
        XCTAssertEqual(reopened.lastPurchaseAnalysisReport, updated)
    }

    func testPeriodCloseCarriesPurchaseRecordsAndRetainsSalesValues() throws {
        let ledger = try makeLedger()
        let supplier = try addSupplier(ledger)
        let supplierKey = SJIS.encode(supplier, size: 7)
        var code = PurchaseLedger.AnalysisCode()
        code.code = "a"
        try ledger.saveAnalysisCode(code, creating: true)
        code.code = "a1"
        try ledger.saveAnalysisCode(code, creating: true)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = supplier
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        let closed = try ledger.saveTransaction(invoice)
        let outstanding = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        let pending = try ledger.saveTransaction(invoice)
        let closedKey = ledger.openItemKey(supplier: supplier, number: closed)
        var closedItem = Record(PurchaseRecords.oiLayout, bytes: try XCTUnwrap(ledger.store.read(ledger.openItemsPath, key: closedKey)))
        closedItem.setInt("oi-status", 1)
        XCTAssertTrue(ledger.store.rewrite(ledger.openItemsPath, key: closedKey, data: closedItem.bytes))

        var credit = Record(PurchaseRecords.oiLayout)
        credit["oi-supplier"] = supplier
        credit.setInt("oi-invoice", 101)
        credit.setInt("oi-type", 6)
        credit.setInt("oi-deduct-amt", 100)
        credit.setInt("oi-p-c", 99)
        let creditKey = ledger.openItemKey(supplier: supplier, number: 101)
        XCTAssertTrue(ledger.store.write(ledger.openItemsPath, key: creditKey, data: credit.bytes))

        var supplierRecord = try XCTUnwrap(ledger.supplierRecord(supplier))
        supplierRecord.setInt("purch-current", -9_000)
        supplierRecord.setInt("purch-unapplied", 3_000)
        supplierRecord.setInt("turnover-q2", 300)
        supplierRecord.setInt("purch-average", 20)
        XCTAssertTrue(ledger.store.rewrite(ledger.suppliersPath, key: supplierKey, data: supplierRecord.bytes))
        let valuePath = ledger.base + "value.dat"
        var value = Record(PurchaseRecords.valueLayout)
        value["code"] = "SAA"
        value.setInt("this-count", 42)
        let salesKey = Array("SAA".utf8)
        XCTAssertTrue(ledger.store.write(valuePath, key: salesKey, data: value.bytes))
        var settings = ledger.system
        settings.setInt("scycle", 3)
        settings.setInt("period", 3)
        settings.setInt("current-quarter", 1)
        try ledger.systemFile.write(1, settings.bytes)
        let before = try XCTUnwrap(ledger.systemFile.read(4))
        let day = try ledger.legacyDate(ledger.processingDate)
        XCTAssertThrowsError(try ledger.closePeriod(confirmUnpostedInvoices: false, password: "", endQuarter: false)) {
            XCTAssertEqual($0 as? PurchaseLedger.PeriodCloseError, .unpostedInvoices)
        }
        XCTAssertThrowsError(try ledger.closePeriod(confirmUnpostedInvoices: true, password: "", endQuarter: false)) {
            XCTAssertEqual($0 as? PurchaseLedger.PeriodCloseError, .analysisRequired)
        }
        let dayBook = try XCTUnwrap(ledger.purchaseDayBook())
        XCTAssertTrue(SJIS.decode(Array(dayBook)[...]).contains("Purchase Ledger Day Book"))
        let analysis = try XCTUnwrap(ledger.purchaseAnalysisReport())
        XCTAssertTrue(SJIS.decode(Array(analysis)[...]).contains("Purchase  Analysis"))
        let beforeAnalysis = ledger.store.all(valuePath).filter { $0.key.first == 0x50 }
        XCTAssertFalse(beforeAnalysis.isEmpty)
        try ledger.closePeriod(confirmUnpostedInvoices: true, password: "", endQuarter: false)

        let reopened = PurchaseLedger(ledger.context)
        _ = try reopened.purchaseDayBook()
        XCTAssertEqual(reopened.closedPurchaseDayBook, dayBook)
        XCTAssertEqual(reopened.lastPurchaseAnalysisReport, analysis)

        let afterSupplier = try XCTUnwrap(ledger.supplierRecord(supplier))
        XCTAssertEqual(afterSupplier.int("purch-current"), 0)
        XCTAssertEqual(afterSupplier.int("purch-last"), 0)
        XCTAssertEqual(afterSupplier.int("purch-unapplied"), 12_000)
        XCTAssertEqual(afterSupplier.int("turnover-q2"), 0)
        XCTAssertEqual(afterSupplier.int("purch-average"), 20)
        XCTAssertNil(ledger.header(closed))
        XCTAssertNil(ledger.store.read(ledger.invoicePath, key: ledger.invoiceKey(closed, 1)))
        XCTAssertEqual(ledger.header(outstanding)?.str("ih-day-book-flag"), "B")
        XCTAssertEqual(ledger.header(outstanding)?.int("ih-lines"), 0)
        XCTAssertEqual(ledger.header(pending)?.int("ih-lines"), 1)
        XCTAssertNil(ledger.store.read(ledger.openItemsPath, key: closedKey))
        let afterCredit = Record(PurchaseRecords.oiLayout, bytes: try XCTUnwrap(ledger.store.read(ledger.openItemsPath, key: creditKey)))
        XCTAssertEqual(afterCredit.str("oi-applied"), "z")
        XCTAssertEqual(afterCredit.int("oi-p-c"), 0)
        XCTAssertEqual(afterCredit.int("oi-deduct-amt"), 0)
        XCTAssertEqual(ledger.store.read(valuePath, key: salesKey), value.bytes)
        for entry in beforeAnalysis {
            let old = Record(PurchaseRecords.valueLayout, bytes: entry.data)
            let new = Record(PurchaseRecords.valueLayout, bytes: try XCTUnwrap(ledger.store.read(valuePath, key: entry.key)))
            XCTAssertEqual(new.int("last-count"), old.int("this-count"))
            XCTAssertEqual(new.int("last-net"), old.int("this-net"))
            XCTAssertEqual(new.int("this-count"), 0)
            XCTAssertEqual(new.int("this-net"), 0)
        }
        let after = try XCTUnwrap(ledger.systemFile.read(4))
        let totals = Record(PurchaseRecords.sys4Layout, bytes: after)
        XCTAssertEqual(totals.int("pl-os-bal-last-month"), Record(PurchaseRecords.sys4Layout, bytes: before).int("pl-os-bal-this-month"))
        XCTAssertEqual(totals.int("pl-invoices-this-month"), 0)
        XCTAssertEqual(after.dropFirst(PurchaseRecords.sys4Layout.size), before.dropFirst(PurchaseRecords.sys4Layout.size))
        XCTAssertEqual(ledger.system.int("scycle"), 4)
        XCTAssertEqual(ledger.system.int("current-quarter"), 2)
        XCTAssertEqual(ledger.system.int("bl-end-cycle-date"), day)
        XCTAssertEqual(ledger.system.str("oi-5-flag"), "Y")

        let emptyDayBook = try XCTUnwrap(reopened.purchaseDayBook())
        XCTAssertNotEqual(emptyDayBook, dayBook)
        try reopened.closePeriod(confirmUnpostedInvoices: true, password: "", endQuarter: false)
        XCTAssertEqual(PurchaseLedger(ledger.context).closedPurchaseDayBook, emptyDayBook)
    }

    func testPeriodCloseWeeklyYearEndRequiresPasswordAndNoPendingPayments() throws {
        let ledger = try makeLedger()
        let supplier = try addSupplier(ledger)
        var settings = ledger.system
        for flag in [15, 29] { ledger.setFileFlag(flag, in: &settings) }
        settings.setInt("scycle", 52)
        settings.setInt("period", 13)
        settings.setInt("current-quarter", 4)
        settings.setInt("s-flag-p", 2)
        settings["pass-word"] = "QYBG"
        try ledger.systemFile.write(1, settings.bytes)
        let path = ledger.base + "value.dat"
        XCTAssertTrue(ledger.store.write(path, key: Array("SAA".utf8), data: Record(PurchaseRecords.valueLayout).bytes))
        XCTAssertThrowsError(try ledger.closePeriod(confirmUnpostedInvoices: false, password: "CKQU", endQuarter: false)) {
            XCTAssertEqual($0 as? PurchaseLedger.PeriodCloseError, .unpostedPayments)
        }
        settings.setInt("s-flag-p", 0)
        try ledger.systemFile.write(1, settings.bytes)
        XCTAssertThrowsError(try ledger.closePeriod(confirmUnpostedInvoices: false, password: "", endQuarter: false)) {
            XCTAssertEqual($0 as? PurchaseLedger.PeriodCloseError, .incorrectPassword)
        }
        var record = try XCTUnwrap(ledger.supplierRecord(supplier))
        record.setInt("turnover-q1", 100)
        record.setInt("purch-activety", 12)
        record.setInt("purch-average", 456)
        XCTAssertTrue(ledger.store.rewrite(ledger.suppliersPath, key: SJIS.encode(supplier, size: 7), data: record.bytes))
        try ledger.closePeriod(confirmUnpostedInvoices: false, password: "CKQU", endQuarter: false)
        let after = try XCTUnwrap(ledger.supplierRecord(supplier))
        XCTAssertEqual(after.int("turnover-q1"), 0)
        XCTAssertEqual(after.int("purch-activety"), 0)
        XCTAssertEqual(after.int("purch-average"), 0)
        XCTAssertTrue(ledger.store.all(path).isEmpty)
        XCTAssertEqual(ledger.system.int("scycle"), 1)
        XCTAssertEqual(ledger.system.int("current-quarter"), 1)
    }

    func testDuplicateConfiguredFolioAdvancesWithoutOverwritingInvoice() throws {
        let ledger = try makeLedger()
        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = try addSupplier(ledger)
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 10_000
        let folio = try ledger.saveTransaction(transaction)
        var settings = ledger.invoiceSettings()
        settings.nextFolio = folio
        try ledger.saveInvoiceSettings(settings)
        let original = ledger.store.all(ledger.invoicePath).map(\.data)

        XCTAssertThrowsError(try ledger.saveTransaction(transaction)) { error in
            XCTAssertEqual(error as? PurchaseLedger.Error, .duplicateFolioAdvanced)
        }
        XCTAssertEqual(ledger.store.all(ledger.invoicePath).map(\.data), original)
        XCTAssertEqual(ledger.invoiceSettings().nextFolio, folio + 1)
        XCTAssertEqual(try ledger.saveTransaction(transaction), folio + 1)
    }

    func testHighestFolioKeepsBinaryCounterAndTruncatesInvoiceKey() throws {
        let ledger = try makeLedger()
        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = try addSupplier(ledger)
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 10_000
        let highest: Int64 = 99_999_999
        var settings = ledger.invoiceSettings()
        settings.nextFolio = highest
        try ledger.saveInvoiceSettings(settings)

        XCTAssertEqual(try ledger.saveTransaction(transaction), highest)
        XCTAssertEqual(ledger.invoiceSettings().nextFolio, highest + 1)
        XCTAssertEqual(ledger.nextTransactionFolio, 0)
        XCTAssertEqual(try ledger.saveTransaction(transaction), 0)
        XCTAssertEqual(ledger.invoiceSettings().nextFolio, highest + 2)
        XCTAssertNotNil(ledger.header(0))

        try ledger.saveInvoiceSettings(settings)
        XCTAssertThrowsError(try ledger.saveTransaction(transaction)) { error in
            XCTAssertEqual(error as? PurchaseLedger.Error, .duplicateFolioAdvanced)
        }
        XCTAssertEqual(ledger.invoiceSettings().nextFolio, highest + 1)
        let original = ledger.header(0)?.bytes
        XCTAssertThrowsError(try ledger.saveTransaction(transaction)) { error in
            XCTAssertEqual(error as? PurchaseLedger.Error, .duplicateFolioAdvanced)
        }
        XCTAssertEqual(ledger.header(0)?.bytes, original)
        XCTAssertEqual(ledger.invoiceSettings().nextFolio, highest + 2)
        XCTAssertEqual(try ledger.saveTransaction(transaction), 1)
    }

    func testInvoiceSettingsWriteOnlyConfiguredFieldsAndSetNextTransactionFolio() throws {
        let ledger = try makeLedger()
        var configuration = ledger.system
        configuration.setInt("vat-ac", 123456)
        try ledger.systemFile.write(1, configuration.bytes)
        var settings = ledger.invoiceSettings()
        XCTAssertNil(settings.vatAccount)
        settings.nextFolio = 240
        settings.vatAccount = 654321
        try ledger.saveInvoiceSettings(settings)
        configuration.setInt("next-folio", 240)
        XCTAssertEqual(ledger.systemFile.read(1), configuration.bytes)

        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = try addSupplier(ledger)
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 10_000
        XCTAssertEqual(try ledger.saveTransaction(transaction), 240)
        XCTAssertEqual(ledger.invoiceSettings().nextFolio, 241)

        configuration = ledger.system
        configuration.setInt("level-1", 1)
        try ledger.systemFile.write(1, configuration.bytes)
        settings = ledger.invoiceSettings()
        XCTAssertEqual(settings.vatAccount, 123456)
        settings.nextFolio = 0
        XCTAssertThrowsError(try ledger.saveInvoiceSettings(settings))
        XCTAssertEqual(ledger.systemFile.read(1), configuration.bytes)
        settings.nextFolio = 500
        settings.vatAccount = 1_000_000
        XCTAssertThrowsError(try ledger.saveInvoiceSettings(settings))
        XCTAssertEqual(ledger.systemFile.read(1), configuration.bytes)

        settings.vatAccount = 654321
        try ledger.saveInvoiceSettings(settings)
        configuration.setInt("next-folio", 500)
        configuration.setInt("vat-ac", 654321)
        XCTAssertEqual(ledger.systemFile.read(1), configuration.bytes)
    }

    func testPostingRollsBackGLPostingIfBatchWriteFails() throws {
        try withDiskLedger { ledger, db in
            var system = ledger.system
            system.setInt("level-1", 1)
            try ledger.systemFile.write(1, system.bytes)
            var value = PurchaseLedger.Transaction(date: ledger.processingDate)
            value.supplier = try addSupplier(ledger)
            value.lines[0].code = "a1"
            value.lines[0].net = 10_000
            value.lines[0].tax = 2_000
            let folio = try ledger.saveTransaction(value)
            let batchPath = ledger.base + "batch.dat"
            let postingPath = ledger.base + "posting.dat"
            let postingFile = RelativeFile(ledger.store, path: postingPath, recordSize: PurchaseRecords.postLayout.size)
            let before = EvidenceComparison.snapshot(ledger.store)
            let sql = """
                CREATE TRIGGER reject_batch BEFORE INSERT ON records
                WHEN NEW.file = '\(batchPath)'
                    AND (SELECT length(data) FROM files WHERE name = '\(postingPath)') > 0
                BEGIN SELECT RAISE(ABORT, 'blocked after writing GL posting'); END
                """
            XCTAssertNil(ledger.store.readRaw(postingPath))
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

            XCTAssertThrowsError(try ledger.postTransactions()) { error in
                guard case .rejected(let path) = error as? PurchasePostingWriteError else {
                    return XCTFail("予期しないエラー: \(error)")
                }
                XCTAssertEqual(path, batchPath)
            }
            XCTAssertNil(ledger.store.readRaw(postingPath))
            XCTAssertTrue(ledger.store.all(batchPath).isEmpty)
            XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)

            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_batch", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try ledger.postTransactions().map(\.id), [folio])
            XCTAssertEqual(postingFile.recordCount, 1)
            let raw = try XCTUnwrap(postingFile.read(1))
            let posting = Record(PurchaseRecords.postLayout, bytes: raw)
            XCTAssertEqual(posting.int("post-number"), 1)
            XCTAssertEqual(posting.int("post-amount"), 10_000)
            XCTAssertEqual(posting.int("vat-amount"), 2_000)
            let batches = ledger.store.all(batchPath)
            XCTAssertEqual(batches.count, 1)
            let batch = Record(PurchaseRecords.batchLayout, bytes: try XCTUnwrap(batches.first?.data))
            XCTAssertEqual(batch.int("batch-nos"), posting.int("batch"))
            XCTAssertEqual(batch.int("items"), 1)
            XCTAssertTrue(try ledger.postTransactions().isEmpty)
            XCTAssertEqual(postingFile.recordCount, 1)
            XCTAssertEqual(postingFile.read(1), raw)
            XCTAssertEqual(ledger.store.all(batchPath).count, 1)
        }
    }

    func testPostingDoesNotWriteAfterSQLiteRollsBackSupplierUpdate() throws {
        try withDiskLedger { ledger, db in
            var value = PurchaseLedger.Transaction(date: ledger.processingDate)
            value.supplier = try addSupplier(ledger)
            value.lines[0].code = "a1"
            value.lines[0].net = 10_000
            value.lines[0].tax = 2_000
            let folio = try ledger.saveTransaction(value)
            let before = EvidenceComparison.snapshot(ledger.store)
            let sql = "CREATE TRIGGER reject_supplier BEFORE UPDATE ON records WHEN NEW.file = '\(ledger.suppliersPath)' BEGIN SELECT RAISE(ROLLBACK, 'blocked'); END"
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

            XCTAssertThrowsError(try ledger.postTransactions()) { error in
                guard case .rejected(let path) = error as? PurchasePostingWriteError else {
                    return XCTFail("予期しないエラー: \(error)")
                }
                XCTAssertEqual(path, ledger.suppliersPath)
            }
            XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)
            XCTAssertNil(ledger.store.readRaw(PurchaseLedger.reportPath))
            XCTAssertEqual(ledger.transactions().map(\.posted), [false])
            XCTAssertTrue(ledger.openItems(supplier: value.supplier).isEmpty)

            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_supplier", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try ledger.postTransactions().map(\.id), [folio])
            XCTAssertEqual(try ledger.supplier(code: value.supplier).currentBalance, 12_000)
        }
    }

    func testPostingReportFailureRollsBackBeforeRetry() throws {
        try withDiskLedger { ledger, db in
            var value = PurchaseLedger.Transaction(date: ledger.processingDate)
            value.supplier = try addSupplier(ledger)
            value.lines[0].code = "a1"
            value.lines[0].net = 10_000
            value.lines[0].tax = 2_000
            let folio = try ledger.saveTransaction(value)
            let before = EvidenceComparison.snapshot(ledger.store)
            let sql = "CREATE TRIGGER reject_report BEFORE INSERT ON files WHEN NEW.name = '\(PurchaseLedger.reportPath)' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

            XCTAssertThrowsError(try ledger.postTransactions()) { error in
                XCTAssertEqual((error as? FileStore.DatabaseError)?.code, SQLITE_CONSTRAINT)
            }
            XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)
            XCTAssertNil(ledger.store.readRaw(PurchaseLedger.reportPath))

            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_report", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try ledger.postTransactions().map(\.id), [folio])
            XCTAssertEqual(try ledger.supplier(code: value.supplier).currentBalance, 12_000)
            XCTAssertEqual(ledger.systemFile.read(4).map { Record(PurchaseRecords.sys4Layout, bytes: $0).int("pl-invoices-this-month") }, 12_000)
        }
    }

    func testPostingRestoresStagingIfConfigurationWriteFailsAfterClearingIt() throws {
        try withDiskLedger { ledger, db in
            let supplier = try addSupplier(ledger)
            var staged = Record(PurchaseRecords.oiLayout)
            staged["oi-supplier"] = supplier
            staged.setInt("oi-invoice", 99)
            staged.setInt("oi-type", 2)
            staged.setInt("oi-net", 4_000)
            let path = ledger.base + "openitm4.dat"
            try ledger.store.writeRaw(path, staged.bytes)
            let before = EvidenceComparison.snapshot(ledger.store)
            let sql = """
                CREATE TRIGGER reject_system BEFORE UPDATE ON files
                WHEN NEW.name = '\(ledger.base)system.dat' AND (SELECT length(data) FROM files WHERE name = '\(path)') = 0
                BEGIN SELECT RAISE(ABORT, 'blocked after clearing staging'); END
                """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

            XCTAssertThrowsError(try ledger.postTransactions()) { error in
                XCTAssertEqual((error as? FileStore.DatabaseError)?.message, "blocked after clearing staging")
            }
            XCTAssertEqual(ledger.store.readRaw(path), staged.bytes)
            XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)
            XCTAssertNil(ledger.store.readRaw(PurchaseLedger.reportPath))

            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_system", nil, nil, nil), SQLITE_OK)
            try ledger.postTransactions()
            XCTAssertEqual(ledger.store.readRaw(path), [])
            XCTAssertEqual(ledger.openItems(supplier: supplier).map(\.id), [99])
            XCTAssertEqual(try ledger.supplier(code: supplier).currentBalance, 4_000)
        }
    }

    private func withDiskLedger(_ body: (PurchaseLedger, OpaquePointer) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let context = BusinessContext(store: try FileStore(path: url.path))
        try CompanySetup(context).save(name: "試験会社")
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        try body(PurchaseLedger(context), XCTUnwrap(db))
    }

    func testPurchaseProofReportsSQLiteWriteFailure() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try FileStore(path: url.path)
        let context = BusinessContext(store: store)
        try CompanySetup(context).save(name: "試験会社")
        let ledger = PurchaseLedger(context)

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = "CREATE TRIGGER reject_report BEFORE INSERT ON files WHEN NEW.name = '\(PurchaseLedger.reportPath)' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try ledger.purchaseProof()) { error in
            XCTAssertEqual((error as? FileStore.DatabaseError)?.code, SQLITE_CONSTRAINT)
        }
        XCTAssertNil(store.readRaw(PurchaseLedger.reportPath))
    }

    func testPostingFileUsesEvidenceRecordWidthForConsecutiveEntries() throws {
        let ledger = try makeLedger()
        var system = ledger.system
        system.setInt("level-1", 1)
        try ledger.systemFile.write(1, system.bytes)
        var value = PurchaseLedger.Transaction(date: ledger.processingDate)
        value.supplier = try addSupplier(ledger)
        value.lines[0].code = "a1"
        for net in [100, 200] {
            value.lines[0].net = Int64(net)
            try ledger.saveTransaction(value)
        }
        try ledger.postTransactions()
        XCTAssertEqual(PurchaseRecords.postLayout.size, 98)
        let posting = RelativeFile(ledger.store, path: ledger.base + "posting.dat", recordSize: 98)
        for (number, net) in [(1, 100), (2, 200)] {
            let raw = try XCTUnwrap(posting.read(number))
            let record = Record(PurchaseRecords.postLayout, bytes: raw)
            XCTAssertEqual(raw.count, 98)
            XCTAssertEqual(record.int("post-number"), Int64(number))
            XCTAssertEqual(record.int("post-amount"), Int64(net))
        }
    }

    func testPostingAccumulatesLegacyAnalysisKeysAndTotals() throws {
        let ledger = try makeLedger()
        var value = PurchaseLedger.Transaction(date: ledger.processingDate)
        value.supplier = try addSupplier(ledger)
        value.lines[0].code = "a1"
        value.lines[0].net = 10_000
        try ledger.saveTransaction(value)
        try ledger.postTransactions()
        try ledger.postTransactions()
        let path = ledger.base + "value.dat"
        for (key, amount) in [("P1 ", 10_000), ("Pvi", 2_000)] {
            let bytes = try XCTUnwrap(ledger.store.read(path, key: Array(key.utf8)))
            XCTAssertEqual(bytes.count, 66)
            let actual = Record(PurchaseRecords.valueLayout, bytes: bytes)
            XCTAssertEqual(actual.int("this-count"), 1)
            XCTAssertEqual(actual.int("year-count"), 1)
            XCTAssertEqual(actual.int("last-count"), 0)
            XCTAssertEqual(actual.int("this-net"), Int64(amount))
            XCTAssertEqual(actual.int("year-net"), Int64(amount))
        }
    }

    func testFirstPostingCreatesAnalysisSubtotalsWithoutExistingMaster() throws {
        let ledger = try makeLedger()
        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = try addSupplier(ledger)
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 10_000
        try ledger.saveTransaction(transaction)
        XCTAssertFalse(ledger.store.exists(ledger.analysisPath))

        try ledger.postTransactions()

        for code in ["Pvi", "Pv "] {
            let key = Array(code.utf8)
            XCTAssertNotNil(ledger.store.read(ledger.analysisPath, key: key))
            let raw = try XCTUnwrap(ledger.store.read(ledger.base + "value.dat", key: key))
            let value = Record(PurchaseRecords.valueLayout, bytes: raw)
            XCTAssertEqual(value.int("this-count"), 1)
            XCTAssertEqual(value.int("this-net"), 2_000)
        }
    }

    func testPostingPreservesLegacyExtractedTransactions() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var old = Record(PurchaseRecords.oiLayout)
        old["oi-supplier"] = code
        old.setInt("oi-invoice", 99)
        old.setInt("oi-date", ledger.system.int("run-date"))
        old.setInt("oi-type", 2)
        old.setInt("oi-net", 4_000)
        let path = ledger.base + "openitm4.dat"
        try ledger.store.writeRaw(path, old.bytes)
        var retained = try XCTUnwrap(ledger.systemFile.read(4))
        var extractedTotals = Record(PurchaseRecords.sys4Layout, bytes: retained)
        extractedTotals.setInt("pl-invoices-this-month", 4_000)
        retained.replaceSubrange(0..<extractedTotals.bytes.count, with: extractedTotals.bytes)
        try ledger.systemFile.write(4, retained)
        var new = PurchaseLedger.Transaction(date: ledger.processingDate)
        new.supplier = code
        new.lines[0].code = "a1"
        new.lines[0].net = 10_000
        try ledger.saveTransaction(new)
        try ledger.postTransactions()
        XCTAssertEqual(try ledger.supplier(code: code).currentBalance, 16_000)
        XCTAssertEqual(ledger.openItems(supplier: code).map(\.id), [1, 99])
        XCTAssertEqual(ledger.store.readRaw(path), [])
        let totals = Record(PurchaseRecords.sys4Layout, bytes: try XCTUnwrap(ledger.systemFile.read(4)))
        XCTAssertEqual(totals.int("pl-invoices-this-month"), 16_000)
    }

    func testPostingRejectsUnrelatedStagedItemWithSameFolio() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = code
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 10_000
        let number = try ledger.saveTransaction(transaction)
        var staged = Record(PurchaseRecords.oiLayout)
        staged["oi-supplier"] = code
        staged.setInt("oi-invoice", number)
        staged.setInt("oi-type", 2)
        staged.setInt("oi-net", 4_000)
        let path = ledger.base + "openitm4.dat"
        try ledger.store.writeRaw(path, staged.bytes)

        XCTAssertThrowsError(try ledger.postTransactions()) { error in
            XCTAssertEqual(error as? PurchaseLedger.Error, .duplicateTransaction)
        }
        XCTAssertEqual(ledger.transactions().first?.posted, false)
        XCTAssertEqual(ledger.store.readRaw(path), staged.bytes)
        XCTAssertTrue(ledger.openItems(supplier: code).isEmpty)
    }

    func testCreditRejectsReceiptAndOtherSuppliersInvoice() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var secondSupplier = ledger.newSupplier
        secondSupplier.code = "SUPP02"
        secondSupplier.address1 = "住所\\市"
        let second = try ledger.saveSupplier(secondSupplier, creating: true)
        var value = PurchaseLedger.Transaction(date: ledger.processingDate)
        value.supplier = code
        value.lines[0].code = "a1"
        value.lines[0].net = 100
        let invoice = try ledger.saveTransaction(value)
        value.type = .receipt
        let receipt = try ledger.saveTransaction(value)
        value.type = .creditNote
        value.creditReference = receipt
        XCTAssertThrowsError(try ledger.saveTransaction(value))
        value.supplier = second
        value.creditReference = invoice
        XCTAssertThrowsError(try ledger.saveTransaction(value))
        value.supplier = code
        XCTAssertNoThrow(try ledger.saveTransaction(value))
    }

    func testSupplierAddressLimitIsMeasuredInStoredBytes() throws {
        let ledger = try makeLedger()
        var supplier = ledger.newSupplier
        supplier.code = "SUPP01"
        supplier.address1 = String(repeating: "市", count: 16) + "\\町"
        XCTAssertThrowsError(try ledger.saveSupplier(supplier, creating: true))
        supplier.address1 = String(repeating: "市", count: 15) + "\\町"
        XCTAssertNoThrow(try ledger.saveSupplier(supplier, creating: true))
    }

    func testSupplierAddressDistinguishesShiftJISTrailByteFromDelimiter() throws {
        let ledger = try makeLedger()
        var supplier = ledger.newSupplier
        supplier.code = "SUPP01"
        supplier.address1 = "能"
        XCTAssertEqual(SJIS.encode(supplier.address1, size: 2), [0x94, 0x5c])
        XCTAssertThrowsError(try ledger.saveSupplier(supplier, creating: true))
        supplier.address1 = "能能能能能\\町"
        XCTAssertNoThrow(try ledger.saveSupplier(supplier, creating: true))
    }

    func testEnquiryAppliesLegacyOpenItemBalances() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        let path = ledger.base + "openitm5.dat"
        for (number, type, net, paid) in [(1, 1, 2_000, 0), (2, 3, -2_000, 2_000), (3, 2, 4_000, 1_000)] {
            var item = Record(PurchaseRecords.oiLayout)
            item["oi-supplier"] = code
            item.setInt("oi-invoice", Int64(number))
            item.setInt("oi-type", Int64(type))
            item.setInt("oi-net", Int64(net))
            item.setInt("oi-paid", Int64(paid))
            item.setInt("oi-date", ledger.system.int("run-date"))
            if type == 2 { item.setInt("oi-deduct-amt", 200) }
            ledger.store.write(path, key: Array(item.bytes.prefix(11)), data: item.bytes)
        }
        XCTAssertEqual(ledger.openItems(supplier: code).map(\.balance), [0, 0, 2_800])
    }

    func testDeletedFolioIsReusedOnlyOnce() throws {
        let ledger = try makeLedger()
        var value = PurchaseLedger.Transaction(date: ledger.processingDate)
        value.supplier = try addSupplier(ledger)
        value.lines[0].code = "a1"
        value.lines[0].net = 100
        let first = try ledger.saveTransaction(value)
        let second = try ledger.saveTransaction(value)
        try ledger.removeTransaction(number: first)
        XCTAssertEqual(try ledger.saveTransaction(value), first)
        XCTAssertEqual(try ledger.saveTransaction(value), second + 1)
        XCTAssertEqual(ledger.store.readRaw(ledger.base + "delfolio.dat"), [])
    }

    func testSupplierFormCanSeparateAddressAcrossFields() throws {
        let ledger = try makeLedger()
        var supplier = ledger.newSupplier
        supplier.code = "SUPP01"
        supplier.address1 = "東京都"
        supplier.address2 = "千代田区"
        let code = try ledger.saveSupplier(supplier, creating: true, joiningAddressLines: true)
        let record = try XCTUnwrap(ledger.supplierRecord(code))
        XCTAssertEqual(record.raw("purch-address"), SJIS.encode("東京都\\千代田区", size: 96))
        let address = ledger.supplierAddressLines(try ledger.supplier(code: code))
        XCTAssertEqual(address.first, "東京都")
        XCTAssertEqual(address.second, "千代田区")

        supplier.code = code
        supplier.address2 = ""
        try ledger.saveSupplier(supplier, creating: false, joiningAddressLines: true)
        let updated = try XCTUnwrap(ledger.supplierRecord(code))
        XCTAssertEqual(updated.raw("purch-address"), SJIS.encode("東京都\\", size: 96))
    }

    func testSupplierAddressEditRejectsTruncatingSecondLine() throws {
        let ledger = try makeLedger()
        var supplier = ledger.newSupplier
        supplier.code = "SUPP01"
        supplier.address1 = "東京"
        supplier.address2 = String(repeating: "町", count: 34)
        supplier.code = try ledger.saveSupplier(supplier, creating: true, joiningAddressLines: true)
        let before = try XCTUnwrap(ledger.supplierRecord(supplier.code)).bytes
        supplier.address1 = String(repeating: "東", count: 14)
        XCTAssertThrowsError(try ledger.saveSupplier(supplier, creating: false, joiningAddressLines: true)) {
            XCTAssertEqual($0 as? PurchaseLedger.Error, .addressTooLong)
        }
        XCTAssertEqual(ledger.supplierRecord(supplier.code)?.bytes, before)
    }

    func testSupplierFormRejectsTwoBlankAddressFields() throws {
        let ledger = try makeLedger()
        var supplier = ledger.newSupplier
        supplier.code = "SUPP01"
        supplier.address1 = " "
        supplier.address2 = ""
        XCTAssertThrowsError(try ledger.saveSupplier(supplier, creating: true, joiningAddressLines: true)) {
            XCTAssertEqual($0 as? PurchaseLedger.Error, .missingAddress)
        }
        XCTAssertTrue(ledger.suppliers().isEmpty)
    }

    func testPostingPreviewUsesSignedFixedWidthHeaderTotals() throws {
        let ledger = try makeLedger()
        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = try addSupplier(ledger)
        transaction.type = .creditNote
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 999_999_950
        transaction.lines[0].tax = 2_000
        transaction.carriage = 100
        transaction.carriageTax = 20
        let folio = try ledger.saveTransaction(transaction)
        let amounts = try XCTUnwrap(ledger.postingAmounts(for: folio))
        XCTAssertEqual(amounts.net, -50)
        XCTAssertEqual(amounts.tax, -2_020)

        try ledger.postTransactions()
        let report = try XCTUnwrap(ledger.store.readRaw(PurchaseLedger.reportPath))
        XCTAssertTrue(String(decoding: report, as: UTF8.self).contains("0.50CR"))
    }

    func testReusedFolioRemainsAvailableAfterConfigurationWriteFailure() throws {
        try withDiskLedger { ledger, db in
            var value = PurchaseLedger.Transaction(date: ledger.processingDate)
            value.supplier = try addSupplier(ledger)
            value.lines[0].code = "a1"
            value.lines[0].net = 100
            let folio = try ledger.saveTransaction(value)
            try ledger.removeTransaction(number: folio)
            let path = ledger.base + "delfolio.dat"
            let deleted = try XCTUnwrap(ledger.store.readRaw(path))
            let before = EvidenceComparison.snapshot(ledger.store)
            let sql = "CREATE TRIGGER reject_system BEFORE UPDATE ON files WHEN NEW.name = '\(ledger.base)system.dat' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

            XCTAssertThrowsError(try ledger.saveTransaction(value)) { error in
                XCTAssertEqual((error as? FileStore.DatabaseError)?.code, SQLITE_CONSTRAINT)
            }
            XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)
            XCTAssertEqual(ledger.store.readRaw(path), deleted)
            XCTAssertTrue(ledger.transactions().isEmpty)

            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_system", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try ledger.saveTransaction(value), folio)
            XCTAssertEqual(ledger.transactions().map(\.id), [folio])
            XCTAssertEqual(ledger.store.readRaw(path), [])
        }
    }

    func testSupplierLifecyclePreservesFixedWidthRecord() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        let key = Array(code.utf8)
        XCTAssertEqual(code, "SUPP018")
        let initial = try XCTUnwrap(ledger.store.read(ledger.suppliersPath, key: key))
        XCTAssertEqual(initial.count, 300)
        XCTAssertEqual(initial.suffix(16), ArraySlice(repeating: UInt8(0), count: 16))
        var supplier = try ledger.supplier(code: code)
        supplier.name = "変更後"
        try ledger.saveSupplier(supplier, creating: false)
        let updated = try XCTUnwrap(ledger.store.read(ledger.suppliersPath, key: key))
        XCTAssertEqual(initial.prefix(9), updated.prefix(9))
        XCTAssertEqual(initial.dropFirst(39), updated.dropFirst(39))
        XCTAssertEqual(try ledger.supplier(code: code).name, "変更後")
        try ledger.removeSupplier(code: code, deactivate: true)
        XCTAssertFalse(try ledger.supplier(code: code).active)
        try ledger.removeSupplier(code: code, deactivate: false)
        XCTAssertThrowsError(try ledger.supplier(code: code))
    }

    func testPurchaseEntryProofAndPosting() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        ledger.store.write(ledger.analysisPath, key: Array("Pa1".utf8), data: Array(repeating: 0, count: 66))
        XCTAssertThrowsError(try ledger.analysisCodes())
        var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
        transaction.supplier = "MISS001"
        transaction.lines[0].code = "a1"
        transaction.lines[0].net = 10_000
        XCTAssertThrowsError(try ledger.saveTransaction(transaction))
        XCTAssertFalse(ledger.store.exists(ledger.invoicePath))
        transaction.supplier = code
        let number = try ledger.saveTransaction(transaction)
        let header = try XCTUnwrap(ledger.header(number))
        XCTAssertEqual(header.bytes.count, 129)
        XCTAssertEqual(header.int("ih-vat"), 2_000)
        let line = try XCTUnwrap(ledger.store.read(ledger.invoicePath, key: ledger.invoiceKey(number, 1)))
        XCTAssertEqual(Record(PurchaseRecords.invLineLayout, bytes: line).raw("il-description"), Array(repeating: 0, count: 24))
        XCTAssertEqual(try ledger.purchaseProof().map(\.id), [number])
        let proof = try XCTUnwrap(ledger.store.readRaw(PurchaseLedger.reportPath))
        XCTAssertTrue(String(decoding: proof, as: UTF8.self).contains("Unapplied Purchase Transaction Report"))
        XCTAssertEqual(try ledger.postTransactions().map(\.id), [number])
        XCTAssertEqual(try ledger.supplier(code: code).currentBalance, 12_000)
        XCTAssertEqual(ledger.openItems(supplier: code).first?.balance, 12_000)
        XCTAssertTrue(try ledger.postTransactions().isEmpty)
        XCTAssertThrowsError(try ledger.removeTransaction(number: number))
        XCTAssertThrowsError(try ledger.removeSupplier(code: code, deactivate: false))
    }

    func testPaymentWritesRollBackOnLateFailure() throws {
        try withDiskLedger { ledger, db in
            var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
            invoice.supplier = try addSupplier(ledger)
            invoice.lines[0].code = "a1"
            invoice.lines[0].net = 10_000
            let folio = try ledger.saveTransaction(invoice)
            try ledger.postTransactions()

            var payment = PurchaseLedger.Payment(date: ledger.processingDate)
            payment.supplier = invoice.supplier
            payment.amount = 5_000
            payment.allocations = [.init(invoice: folio, amount: 5_000)]
            let block = "CREATE TRIGGER reject_payment_config BEFORE UPDATE ON files WHEN NEW.name = '\(ledger.base)system.dat' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
            let unblock = "DROP TRIGGER reject_payment_config"

            func assertRollback(_ operation: () throws -> Void) {
                let before = EvidenceComparison.snapshot(ledger.store)
                XCTAssertEqual(sqlite3_exec(db, block, nil, nil, nil), SQLITE_OK)
                XCTAssertThrowsError(try operation())
                XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)
                XCTAssertEqual(sqlite3_exec(db, unblock, nil, nil, nil), SQLITE_OK)
            }

            assertRollback { _ = try ledger.savePayment(payment) }
            let number = try ledger.savePayment(payment)
            assertRollback { try ledger.cancelPayment(supplier: invoice.supplier, number: number) }
            assertRollback { _ = try ledger.proofPayments() }
            try ledger.proofPayments()
            assertRollback { _ = try ledger.postPayments() }
            XCTAssertEqual(try ledger.postPayments().map(\.number), [number])
            XCTAssertTrue(try ledger.postPayments().isEmpty)
        }
    }

    func testScheduledPaymentLayoutAndChequeRemittanceRegister() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.reference = "SCHED-1"
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        invoice.deduction = 500
        invoice.deductionDays = 10
        let folio = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        let day = try ledger.legacyDate(ledger.processingDate)

        try ledger.generatePaymentSchedule(age: 1)
        XCTAssertTrue(ledger.paymentSchedule().isEmpty)
        try ledger.generatePaymentSchedule(age: 0)
        let path = ledger.base + "pay.dat"
        let entry = try XCTUnwrap(ledger.store.all(path).first)
        XCTAssertEqual(entry.key, Array(code.utf8) + [1])
        var expected = Array(code.utf8) + [1, 32]
        func binary(_ value: Int64) -> [UInt8] {
            (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }
        expected += binary(day) + Array(repeating: 0, count: 12)
        let gross: [UInt8] = [0, 0, 0x11, 0x50, 0x0c]
        expected += gross
        expected += binary(folio) + [0] + gross + [0, 0x50, 0x0c] + Array("SCHED-1   ".utf8)
        let blank = Array(repeating: UInt8(0), count: 9) + [0x0c, 0, 0, 0x0c] + Array(repeating: 32, count: 10)
        for _ in 0..<8 { expected += blank }
        XCTAssertEqual(expected.count, 237)
        XCTAssertEqual(entry.data, expected)

        try ledger.amendPaymentSchedule(supplier: code, sequence: 1, line: 1, amount: 11_000)
        XCTAssertEqual(ledger.paymentSchedule().first?.amount, 11_000)
        try ledger.proofPaymentSchedule()
        XCTAssertTrue(SJIS.decode(try XCTUnwrap(ledger.store.readRaw(PurchaseLedger.reportPath))[...]).contains("SCHED-1"))
        try ledger.amendPaymentSchedule(supplier: code, sequence: 1, line: 1, amount: 11_500)

        let file = try ledger.generateChequeFile(firstNumber: 901, date: ledger.processingDate)
        let row = try XCTUnwrap(Array(file).split(separator: 10).first)
        XCTAssertEqual(SJIS.decode(row[345..<354]), "      901")
        XCTAssertEqual(SJIS.decode(row[366..<376]), "SCHED-1   ")
        try ledger.remittanceAdvice()
        let advice = SJIS.decode(try XCTUnwrap(ledger.store.readRaw(PurchaseLedger.reportPath))[...])
        XCTAssertTrue(advice.contains("SCHED-1"))
        XCTAssertTrue(advice.contains("115.00"))

        try ledger.registerScheduledPayments()
        let invoices = ledger.openItemRecords()
        let closed = try XCTUnwrap(invoices.first { $0.int("oi-type") == 2 })
        let payment = try XCTUnwrap(invoices.first { $0.int("oi-type") == 5 })
        XCTAssertEqual(closed.int("oi-status"), 1)
        XCTAssertEqual(closed.int("oi-paid"), 11_500)
        XCTAssertEqual(payment.int("oi-approp"), 11_500)
        XCTAssertEqual(payment.int("oi-deduct-amt"), 500)
        XCTAssertEqual(payment.str("oi-ref"), "0000000901")
        XCTAssertTrue(ledger.paymentSchedule().isEmpty)
        XCTAssertThrowsError(try ledger.registerScheduledPayments())
    }

    func testScheduledPaymentContinuationRetainsLegacySlotsAndCumulativeGross() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        for _ in 0..<10 { try ledger.saveTransaction(invoice) }
        try ledger.postTransactions()
        try ledger.generatePaymentSchedule(age: 0)
        let schedules = ledger.paymentSchedule()
        XCTAssertEqual(schedules.map { $0.lines.count }, [9, 9])
        XCTAssertEqual(Set(schedules.flatMap(\.lines).map(\.folio)).count, 10)
        XCTAssertEqual(schedules.map(\.amount), [108_000, 120_000])
        XCTAssertEqual(schedules.map { $0.lines.first?.folio }, [1, 10])
        let records = ledger.scheduleRecords()
        XCTAssertEqual(records.map { $0.str("continuation") }, ["C", "C"])
        let first = try XCTUnwrap(records.first)
        let second = try XCTUnwrap(records.dropFirst().first)
        let secondSlot = PurchaseLedger.scheduleLayout.offset("folio-2")
        XCTAssertEqual(first.bytes[secondSlot...], second.bytes[secondSlot...])
    }

    func testScheduledBankTransferProducesGLPosting() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var supplier = try ledger.supplier(code: code)
        supplier.sortCode = 123456
        supplier.accountNumber = 12345678
        try ledger.saveSupplier(supplier, creating: false)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        var settings = ledger.system
        settings.setInt("level-1", 1)
        settings.setInt("bl-next-batch", 2)
        settings.setInt("bl-pay-ac", 70)
        settings.setInt("p-creditors", 80)
        try ledger.systemFile.write(1, settings.bytes)
        try ledger.generatePaymentSchedule(age: 0)
        XCTAssertEqual(ledger.paymentSchedule().first?.bankTransfer, true)
        let file = try ledger.generateChequeFile(firstNumber: 901, date: ledger.processingDate)
        let row = try XCTUnwrap(Array(file).split(separator: 10).first)
        XCTAssertEqual(SJIS.decode(row[345..<354]), "BACS     ")

        try ledger.registerScheduledPayments()
        let batches = ledger.store.all(ledger.base + "batch.dat")
        XCTAssertEqual(batches.map { String(decoding: $0.key, as: UTF8.self) }, ["200002"])
        let posting = RelativeFile(ledger.store, path: ledger.base + "posting.dat", recordSize: PurchaseRecords.postLayout.size)
        let entry = Record(PurchaseRecords.postLayout, bytes: try XCTUnwrap(posting.read(1)))
        XCTAssertEqual(entry.int("post-dr"), 80)
        XCTAssertEqual(entry.int("post-cr"), 70)
        XCTAssertEqual(entry.int("post-amount"), 12_000)
        XCTAssertEqual(ledger.system.int("bl-next-batch"), 4)
    }

    func testPaymentPostingRollsBackGLWhenSettingsWriteFails() throws {
        try withDiskLedger { ledger, db in
            var settings = ledger.system
            settings.setInt("level-1", 1)
            settings["irs-instead"] = "N"
            try ledger.systemFile.write(1, settings.bytes)
            var payment = PurchaseLedger.Payment(date: ledger.processingDate)
            payment.supplier = try addSupplier(ledger)
            payment.amount = 5_000
            let number = try ledger.savePayment(payment)
            try ledger.proofPayments()

            let batchPath = ledger.base + "batch.dat"
            let postingPath = ledger.base + "posting.dat"
            let postings = RelativeFile(ledger.store, path: postingPath, recordSize: PurchaseRecords.postLayout.size)
            let before = EvidenceComparison.snapshot(ledger.store)
            let block = """
                CREATE TRIGGER reject_gl_payment_config BEFORE UPDATE ON files
                WHEN NEW.name = '\(ledger.base)system.dat'
                    AND EXISTS (SELECT 1 FROM records WHERE file = '\(batchPath)')
                    AND (SELECT length(data) FROM files WHERE name = '\(postingPath)') > 0
                BEGIN SELECT RAISE(ABORT, 'blocked after writing payment to GL'); END
                """
            XCTAssertEqual(sqlite3_exec(db, block, nil, nil, nil), SQLITE_OK)
            XCTAssertThrowsError(try ledger.postPayments())
            XCTAssertTrue(ledger.store.all(batchPath).isEmpty)
            XCTAssertEqual(postings.recordCount, 0)
            XCTAssertTrue(EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(ledger.store)).isEmpty)

            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_gl_payment_config", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try ledger.postPayments().map(\.number), [number])
            XCTAssertTrue(try ledger.postPayments().isEmpty)
            XCTAssertEqual(ledger.store.all(batchPath).count, 1)
            XCTAssertEqual(postings.recordCount, 1)
        }
    }

    func testPaymentProofReturnsNoReportForUnappliedCreditOnly() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = code
        payment.amount = 5_000
        try ledger.savePayment(payment)
        let proof = try ledger.generatePaymentProof()
        let posted = try ledger.postPaymentsWithReport()
        let previous = try XCTUnwrap(posted.report)
        XCTAssertNotEqual(try XCTUnwrap(proof.report), previous)

        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        let folio = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        try ledger.store.writeRaw(PurchaseLedger.reportPath, Array(previous))

        payment.credit = true
        payment.allocations = [.init(invoice: folio, amount: 5_000)]
        let credit = try ledger.savePayment(payment)
        XCTAssertEqual(ledger.system.int("p-flag-p"), 0)
        let result = try ledger.generatePaymentProof()
        XCTAssertEqual(result.payments.map(\.number), [credit])
        XCTAssertNil(result.report)
        XCTAssertEqual(ledger.store.readRaw(PurchaseLedger.reportPath), Array(previous))
        XCTAssertThrowsError(try ledger.postPayments())
    }

    func testPaymentPostingUpdatesExistingDeductionAnalysis() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        invoice.deduction = 500
        invoice.deductionDays = 10
        let folio = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        let path = ledger.base + "value.dat"
        for code in ["Pzb", "Pz "] {
            var value = Record(PurchaseRecords.valueLayout)
            value["code"] = code
            value.setInt("this-count", 10)
            value.setInt("year-count", 20)
            value.setInt("this-net", 4_000)
            value.setInt("year-net", 8_000)
            let key = Array(code.utf8)
            if ledger.store.read(path, key: key) == nil {
                XCTAssertTrue(ledger.store.write(path, key: key, data: value.bytes))
            } else {
                XCTAssertTrue(ledger.store.rewrite(path, key: key, data: value.bytes))
            }
        }
        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = code
        payment.amount = 11_500
        payment.allocations = [.init(invoice: folio, amount: 11_500, discount: 500)]
        try ledger.savePayment(payment)
        try ledger.proofPayments()
        try ledger.postPayments()

        for code in ["Pzb", "Pz "] {
            let bytes = try XCTUnwrap(ledger.store.read(path, key: Array(code.utf8)))
            let value = Record(PurchaseRecords.valueLayout, bytes: bytes)
            XCTAssertEqual(value.int("this-count"), 9)
            XCTAssertEqual(value.int("year-count"), 19)
            XCTAssertEqual(value.int("this-net"), 3_500)
            XCTAssertEqual(value.int("year-net"), 7_500)
        }
    }

    func testOrphanedPaymentDoesNotBlockOtherSupplierPosting() throws {
        let ledger = try makeLedger()
        let removed = try addSupplier(ledger)
        var another = ledger.newSupplier
        another.code = "SUPP02"
        another.name = "Supplier 2"
        another.address1 = "住所\\市"
        let otherCode = try ledger.saveSupplier(another, creating: true)

        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.amount = 500
        payment.supplier = removed
        try ledger.savePayment(payment)
        try ledger.removeSupplier(code: removed, deactivate: false)
        payment.supplier = otherCode
        try ledger.savePayment(payment)
        try ledger.proofPayments()

        XCTAssertEqual(Set(try ledger.postPayments().map(\.supplier)), [removed, otherCode])
        XCTAssertTrue(ledger.pendingPayments().isEmpty)
        XCTAssertNil(ledger.supplierRecord(removed))
        XCTAssertEqual(ledger.supplierRecord(otherCode)?.int("purch-unapplied"), 500)
    }

    func testPaymentPostingUsesFreeGLBatchAfterInvoicePosting() throws {
        let ledger = try makeLedger()
        var configuration = ledger.system
        configuration.setInt("level-1", 1)
        configuration.setInt("next-batch", 2)
        configuration.setInt("bl-next-batch", 1)
        try ledger.systemFile.write(1, configuration.bytes)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = try addSupplier(ledger)
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        let batchPath = ledger.base + "batch.dat"
        let firstKey = Array("200002".utf8)
        let firstBatch = try XCTUnwrap(ledger.store.read(batchPath, key: firstKey))

        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = invoice.supplier
        payment.amount = 5_000
        payment.allocations = try ledger.proposedAllocations(supplier: invoice.supplier, amount: payment.amount, date: payment.date)
        let number = try ledger.savePayment(payment)
        XCTAssertEqual(ledger.system.int("bl-next-batch"), 2)
        try ledger.proofPayments()
        XCTAssertEqual(try ledger.postPayments().map(\.number), [number])
        XCTAssertEqual(ledger.store.read(batchPath, key: firstKey), firstBatch)
        XCTAssertNotNil(ledger.store.read(batchPath, key: Array("200003".utf8)))
        XCTAssertEqual(ledger.system.int("bl-next-batch"), 4)
    }

    func testPaymentSkipsOccupiedInvoiceNumber() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var item = Record(PurchaseRecords.oiLayout)
        let number = max(1, ledger.system.int("bl-next-batch")) * 1000 + 1
        item["oi-supplier"] = code
        item.setInt("oi-invoice", number)
        item.setInt("oi-type", 2)
        let key = ledger.openItemKey(supplier: code, number: number)
        XCTAssertTrue(ledger.store.write(ledger.openItemsPath, key: key, data: item.bytes))
        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = code
        payment.amount = 500
        XCTAssertEqual(try ledger.savePayment(payment), number + 1)
        XCTAssertEqual(ledger.store.read(ledger.openItemsPath, key: key), item.bytes)
    }

    func testPaymentProofCapsCumulativePaidAtStoredAppropriation() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        let first = try ledger.saveTransaction(invoice)
        let second = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()

        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = code
        payment.amount = 5_000
        payment.allocations = [.init(invoice: first, amount: 5_000)]
        try ledger.savePayment(payment)
        try ledger.proofPayments()
        try ledger.postPayments()

        payment.amount = 6_000
        payment.allocations = [.init(invoice: first, amount: 2_000), .init(invoice: second, amount: 4_000)]
        try ledger.savePayment(payment)
        let key = ledger.openItemKey(supplier: code, number: first)
        var partiallyPaid = Record(PurchaseRecords.oiLayout, bytes: try XCTUnwrap(ledger.store.read(ledger.openItemsPath, key: key)))
        partiallyPaid.setInt("oi-cr", 0)
        XCTAssertTrue(ledger.store.rewrite(ledger.openItemsPath, key: key, data: partiallyPaid.bytes))
        XCTAssertEqual(try ledger.proofPayments().first?.allocated, 4_000)
        let report = try XCTUnwrap(ledger.store.readRaw(PurchaseLedger.reportPath))
        for (folio, appropriated, balance) in [(first, "60.00", "50.00"), (second, "40.00", "80.00")] {
            let prefix = String(repeating: " ", count: 90) + Pic.edit("z(7)9", value: folio, scale: 0)
            let detail = try XCTUnwrap(report.split(separator: 10).map(SJIS.decode).first { $0.hasPrefix(prefix) })
            XCTAssertEqual(detail.dropFirst(110).prefix(9).trimmingCharacters(in: .whitespaces), appropriated)
            XCTAssertTrue(detail.dropFirst(119).contains(balance))
        }
    }

    func testPaymentAllocatesEditsAndPosts() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        let number = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = code
        payment.amount = 5_000
        payment.allocations = try ledger.proposedAllocations(supplier: code, amount: payment.amount, date: payment.date)
        XCTAssertEqual(payment.allocations.map(\.id), [number])
        XCTAssertEqual(payment.allocations.map(\.amount), [5_000])
        let paymentNumber = try ledger.savePayment(payment)
        let pendingInvoice = try XCTUnwrap(ledger.openItemRecords().first { $0.int("oi-invoice") == number })
        XCTAssertEqual(pendingInvoice.int("oi-cr"), 500_000)
        XCTAssertThrowsError(try ledger.postPayments())
        XCTAssertEqual(try ledger.proofPayments().map(\.number), [paymentNumber])
        let report = try XCTUnwrap(ledger.store.readRaw(PurchaseLedger.reportPath))
        let detail = try XCTUnwrap(report.split(separator: 10).map(SJIS.decode)
            .first { $0.hasPrefix(String(repeating: " ", count: 90) + Pic.edit("z(7)9", value: number, scale: 0)) })
        XCTAssertTrue(detail.contains("50.00"))
        XCTAssertTrue(detail.contains("70.00"))
        payment.number = paymentNumber
        payment.amount = 12_500
        payment.allocations = [.init(invoice: number, amount: 12_000)]
        try ledger.savePayment(payment)
        XCTAssertThrowsError(try ledger.postPayments())
        XCTAssertEqual(try ledger.proofPayments().map(\.allocated), [12_000])
        XCTAssertEqual(try ledger.postPayments().map(\.number), [paymentNumber])
        let supplier = try XCTUnwrap(ledger.supplierRecord(code))
        XCTAssertEqual(supplier.int("purch-current"), 0)
        XCTAssertEqual(supplier.int("purch-unapplied"), 500)
        let openItem = try XCTUnwrap(ledger.openItemRecords().first { $0.int("oi-invoice") == number })
        XCTAssertEqual(openItem.int("oi-status"), 1)
        XCTAssertEqual(openItem.int("oi-paid"), 12_000)
        XCTAssertEqual(openItem.int("oi-b-nos"), 0)
        XCTAssertTrue(ledger.pendingPayments().isEmpty)
    }

    func testCancelPaymentReversesAllocationAndRequiresNewProof() throws {
        let ledger = try makeLedger()
        let code = try addSupplier(ledger)
        var invoice = PurchaseLedger.Transaction(date: ledger.processingDate)
        invoice.supplier = code
        invoice.lines[0].code = "a1"
        invoice.lines[0].net = 10_000
        let folio = try ledger.saveTransaction(invoice)
        try ledger.postTransactions()
        var payment = PurchaseLedger.Payment(date: ledger.processingDate)
        payment.supplier = code
        payment.amount = 12_000
        payment.allocations = [.init(invoice: folio, amount: 12_000)]
        let paymentNumber = try ledger.savePayment(payment)
        try ledger.proofPayments()

        try ledger.cancelPayment(supplier: code, number: paymentNumber)

        XCTAssertTrue(ledger.pendingPayments().isEmpty)
        XCTAssertEqual(ledger.system.int("p-flag-p"), 1)
        let openItem = try XCTUnwrap(ledger.openItemRecords().first { $0.int("oi-invoice") == folio })
        for field in ["oi-status", "oi-paid", "oi-p-c", "oi-b-nos", "oi-b-item", "oi-cr"] {
            XCTAssertEqual(openItem.int(field), 0, field)
        }
        XCTAssertEqual(ledger.openItems(supplier: code).map(\.balance), [12_000])
    }

    func testEvidencePurchaseEntryAndReports() throws {
        guard let root = ProcessInfo.processInfo.environment["ACAS_PL_ORACLE"] else {
            throw XCTSkip("実測照合には ACAS_PL_ORACLE を指定してください")
        }
        for run in ["PL-403-breadth", "PL-411-normal-exit", "PL-413-normal-exit-fixture", "PL-414-post-confirmed-input"] {
            let url = URL(fileURLWithPath: root).appendingPathComponent("runs").appendingPathComponent(run)
            let ledger = try makeLedger()
            let fixture = try oracleRecords(url.appendingPathComponent("before-records/records.json"))
            let lengths = ["purchled.dat": 7, "pinvoice.dat": 9, "analysis.dat": 3, "batch.dat": 6, "openitm5.dat": 11]
            for (name, records) in fixture {
                if name.hasSuffix("/system.dat") {
                    try ledger.store.writeRaw(name, Array(Data(contentsOf: url.appendingPathComponent("before-files/" + name))))
                } else if let length = lengths[URL(fileURLWithPath: name).lastPathComponent] {
                    for bytes in records { ledger.store.write(name, key: Array(bytes.prefix(length)), data: bytes) }
                }
            }
            switch run {
            case "PL-403-breadth":
                var value = ledger.newSupplier
                value.code = "TEST01"
                value.name = "EQUIV NEW SUPPLIER"
                value.address1 = "1 TEST ROAD\\LONDON\\UK"
                try ledger.saveSupplier(value, creating: true)
            case "PL-411-normal-exit":
                var transaction = PurchaseLedger.Transaction(date: ledger.processingDate)
                transaction.supplier = "SUPP018"
                transaction.order = "PL-ORDER"
                transaction.reference = "PL-REF"
                transaction.lines[0].code = "a1"
                transaction.lines[0].net = 10_000
                transaction.lines[0].tax = 2_000
                try ledger.saveTransaction(transaction)
            case "PL-413-normal-exit-fixture": try ledger.purchaseProof()
            default: try ledger.postTransactions()
            }
            let diff = try decode(Diff.self, in: url.appendingPathComponent("record-diff.json"))
            for change in diff.changes {
                guard let data = change.after else { continue }
                let expected = FileStore.bytes(hex: data.hex)
                let actual: [UInt8]?
                if let length = lengths[URL(fileURLWithPath: change.file).lastPathComponent] {
                    actual = ledger.store.read(change.file, key: Array(expected.prefix(length)))
                } else if change.file.hasSuffix("/system.dat") {
                    actual = ledger.systemFile.read(Int(change.key) ?? 0)
                } else if change.file.hasSuffix("/posting.dat") {
                    actual = RelativeFile(ledger.store, path: change.file, recordSize: 98).read(Int(change.key) ?? 0)
                } else { continue }
                assertBytes(actual, expected, context: "\(run) \(change.file) \(change.key)")
            }
            if run.hasPrefix("PL-413") || run.hasPrefix("PL-414") {
                let report = try Data(contentsOf: url.appendingPathComponent("files/" + PurchaseLedger.reportPath))
                assertBytes(ledger.store.readRaw(PurchaseLedger.reportPath), Array(report), context: run)
            }
        }
    }

    private func makeLedger() throws -> PurchaseLedger {
        let context = BusinessContext(store: try FileStore(), timeZone: .gmt, now: { Date(timeIntervalSince1970: 1_795_400_000) })
        try CompanySetup(context).save(name: "試験会社")
        let ledger = PurchaseLedger(context)
        var record = ledger.system
        record.setInt("vat-rate-1", 2_000)
        record["pl-delim"] = "\\"
        try ledger.systemFile.write(1, record.bytes)
        return ledger
    }

    private func addSupplier(_ ledger: PurchaseLedger) throws -> String {
        var supplier = ledger.newSupplier
        supplier.code = "SUPP01"
        supplier.name = "試験仕入先"
        supplier.address1 = "住所\\市"
        return try ledger.saveSupplier(supplier, creating: true)
    }

    private struct HexRecord: Decodable { let hex: String }
    private struct OracleFile: Decodable { let records: [String: HexRecord] }
    private struct OracleSnapshot: Decodable { let files: [String: OracleFile] }
    private struct Diff: Decodable {
        struct Change: Decodable { let file: String; let key: String; let after: HexRecord? }
        let changes: [Change]
    }

    private func decode<T: Decodable>(_ type: T.Type, in url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func oracleRecords(_ url: URL) throws -> [String: [[UInt8]]] {
        try decode(OracleSnapshot.self, in: url).files.mapValues { $0.records.values.map { FileStore.bytes(hex: $0.hex) } }
    }

    private func assertBytes(_ actual: [UInt8]?, _ expected: [UInt8], context: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("\(context): レコードなし", file: file, line: line) }
        XCTAssertEqual(actual.count, expected.count, context, file: file, line: line)
        let differences = zip(actual, expected).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertTrue(differences.isEmpty, "\(context): \(differences.prefix(12))", file: file, line: line)
    }
}
