import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class PurchaseLedgerTests: XCTestCase {
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
        var new = PurchaseLedger.Transaction(date: ledger.processingDate)
        new.supplier = code
        new.lines[0].code = "a1"
        new.lines[0].net = 10_000
        try ledger.saveTransaction(new)
        try ledger.postTransactions()
        XCTAssertEqual(try ledger.supplier(code: code).currentBalance, 16_000)
        XCTAssertEqual(ledger.openItems(supplier: code).map(\.id), [1, 99])
        XCTAssertEqual(ledger.store.readRaw(path), [])
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
