import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class PurchaseTransferTests: XCTestCase {
    func testPostingUsesInvoiceDateAndRejectsUnrepresentableIRSHandoff() throws {
        let store = try FileStore()
        let settings = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var system = Record(SystemLayout.layout)
        system.setInt("next-batch", 1)
        system.setInt("postings", 1)
        try settings.write(1, system.bytes)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-23T00:00:00Z"))
        let invoiceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        let transfer = PurchaseTransfer(BusinessContext(store: store, timeZone: .gmt))
        let invoice = PurchaseTransfer.Invoice(number: 1, supplier: "仕入先", net: 100, tax: 20, date: invoiceDate)
        _ = try transfer.write([invoice], processingDate: date)
        let posting = RelativeFile(store, path: "ledgers/acas/posting.dat", recordSize: 98)
        let rowIndex = Int(system.int("postings")) + 1
        let row = Record(TransferRecords.postLayout, bytes: try XCTUnwrap(posting.read(rowIndex)))
        XCTAssertEqual(row.str("post-date"), "01/10/26")
        system = Record(SystemLayout.layout, bytes: try XCTUnwrap(settings.read(1)))
        system["irs-instead"] = "Y"
        try settings.write(1, system.bytes)
        let overflow = PurchaseTransfer.Invoice(number: 2, supplier: "仕入先", net: 1_000_000_000, tax: 0)
        XCTAssertThrowsError(try transfer.write([overflow], processingDate: date)) {
            guard case PurchaseTransfer.Failure.invalidInvoice = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(store.exists("ledgers/irs/postings2irs.dat"))
        XCTAssertEqual(settings.read(1), system.bytes)
    }

    func testPostingSequenceCannotOverflowWhenStoringTheNextIndex() throws {
        let store = try FileStore()
        let settings = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var system = Record(SystemLayout.layout)
        system.setInt("next-batch", 1)
        system.setInt("postings", Int64(Int16.max) - 1)
        try settings.write(1, system.bytes)
        let date = Date(timeIntervalSince1970: 1_795_408_126)
        let transfer = PurchaseTransfer(BusinessContext(store: store))
        let invoice = PurchaseTransfer.Invoice(number: 1, supplier: "仕入先", net: 100, tax: 20)
        XCTAssertThrowsError(try transfer.write([invoice], processingDate: date)) {
            guard case PurchaseTransfer.Failure.noSequence = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(store.exists("ledgers/acas/posting.dat"))
        XCTAssertEqual(settings.read(1), system.bytes)
    }

    func testLegacyInvoiceTransferRecordsAndReport() throws {
        guard let path = ProcessInfo.processInfo.environment["ACAS_LEGACY_EVIDENCE"] else {
            throw XCTSkip("ACAS_LEGACY_EVIDENCE にレガシー証跡の展開先を指定してください。")
        }
        let run = URL(fileURLWithPath: path).appending(path: "runs/PL-414-post-confirmed-input")
        let prefix = "ledgers/acas/"
        let database = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: database) }
        let store = try FileStore(path: database)
        func read(_ name: String) throws -> Data { try Data(contentsOf: run.appending(path: name)) }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: read("before-records/records.json"))
        try store.writeRaw(prefix + "system.dat", Array(try read("before-files/" + prefix + "system.dat")))
        for (name, length) in [("pinvoice.dat", 9), ("purchled.dat", 7)] {
            let file = try XCTUnwrap(snapshot.files[prefix + name])
            for row in file.records.values {
                let bytes = FileStore.bytes(hex: row.hex)
                XCTAssertTrue(store.write(prefix + name, key: Array(bytes.prefix(length)), data: bytes))
            }
        }
        let timestamp = try JSONDecoder().decode(Timestamp.self, from: Data(try read("terminal.cast").prefix { $0 != 0x0a }))
        let date = Date(timeIntervalSince1970: timestamp.timestamp)
        let transfer = PurchaseTransfer(BusinessContext(store: store, timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)),
                                                         now: { date }))
        let before = EvidenceComparison.snapshot(store)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(database, &db), SQLITE_OK)
        let sql = "CREATE TRIGGER reject_invoice BEFORE UPDATE ON records WHEN NEW.file LIKE '%/pinvoice.dat' BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try transfer.postPending()) {
            guard case PurchaseTransfer.Failure.saveFailed = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(EvidenceComparison.snapshot(store), before)
        XCTAssertFalse(store.exists(prefix + "posting.dat"))
        XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_invoice", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try transfer.postPending(), ["200001"])
        let diff = try JSONDecoder().decode(Diff.self, from: read("record-diff.json"))
        XCTAssertEqual(diff.changes.count, 4)
        for change in diff.changes {
            let expected = try XCTUnwrap(change.after).hex
            let result: [UInt8]?
            if change.file.hasSuffix("/posting.dat") {
                let posting = RelativeFile(store, path: change.file, recordSize: 98)
                result = posting.read(try XCTUnwrap(Int(change.key)))
            } else {
                let key = change.file.hasSuffix("/pinvoice.dat") ? Array(FileStore.bytes(hex: expected).prefix(9))
                    : Array(change.key.utf8)
                result = store.read(change.file, key: key)
            }
            XCTAssertEqual(result.map(FileStore.hex), expected, change.file)
        }
        XCTAssertEqual(store.readRaw(prefix + "prt-1").map(Data.init(_:)), try read("files/" + prefix + "prt-1"))
        let openItems = store.all(prefix + "openitm5.dat")
        let item = try XCTUnwrap(openItems.first)
        XCTAssertEqual(openItems.count, 1)
        XCTAssertEqual(item.data.count, 109)
        XCTAssertNotNil(try read("files/" + prefix + "openitm5.dat").range(of: Data(item.data)))
        let settings = RelativeFile(store, path: prefix + "system.dat", recordSize: 1024)
        let state = Record(SystemLayout.layout, bytes: try XCTUnwrap(settings.read(1)))
        XCTAssertEqual(state.int("p-flag-i"), 2)
        XCTAssertEqual(state.raw("file-statuses")[28], 0x31)

        var shortPage = state
        shortPage.setInt("page-lines", 8)
        try settings.write(1, shortPage.bytes)
        let invoicePath = prefix + "pinvoice.dat"
        let header = try XCTUnwrap(store.all(invoicePath).first { $0.key.last == 0 })
        var next = Record(PeriodRecords.pihLayout, bytes: header.data)
        next.setInt("invoice", next.int("invoice") + 1)
        next["status"] = "P"
        let nextBytes = next.bytes + header.data.dropFirst(next.bytes.count)
        XCTAssertTrue(store.write(invoicePath, key: Array(nextBytes.prefix(9)), data: nextBytes))
        XCTAssertFalse(try transfer.postPending().isEmpty)
        let report = try XCTUnwrap(store.readRaw(prefix + "prt-1"))
        let pageBreak = try XCTUnwrap(report.firstIndex(of: 0x0c))
        XCTAssertTrue(report[(pageBreak + 1)...].starts(with: "PL060".utf8))
    }

    private struct Timestamp: Decodable { let timestamp: Double }
    private struct Raw: Decodable { let hex: String }
    private struct Snapshot: Decodable {
        struct File: Decodable { let records: [String: Raw] }
        let files: [String: File]
    }
    private struct Diff: Decodable {
        struct Change: Decodable {
            let file: String
            let key: String
            let after: Raw?
        }
        let changes: [Change]
    }
}
