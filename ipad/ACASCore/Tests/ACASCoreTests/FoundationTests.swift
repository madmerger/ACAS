import Foundation
import SQLite3
import XCTest
@testable import ACASCore

final class FoundationTests: XCTestCase {
    func testSnapshotsReadLogicalRecordsAndExcludeReports() throws {
        let store = try FileStore()
        let before = EvidenceComparison.snapshot(store)
        let setup = CompanySetup(BusinessContext(store: store))
        try setup.save(name: "テスト会社")
        XCTAssertEqual(setup.name, "テスト会社")
        try store.writeRaw("ledgers/acas/prt-1", [0, 15])

        let changes = EvidenceComparison.diff(before: before, after: EvidenceComparison.snapshot(store))
        XCTAssertEqual(changes.map(\.key), ["00000001", "00000002", "00000003", "00000004"])
        XCTAssertTrue(changes.allSatisfy { $0.before == nil && $0.after?.count == 2048 })
        XCTAssertTrue(EvidenceComparison.reportsAgree(["ledgers/acas/prt-1": "000f"], in: store))
        XCTAssertFalse(EvidenceComparison.reportsAgree(["ledgers/acas/prt-1": "000e"], in: store))

        let populated = EvidenceComparison.snapshot(store)
        try setup.save(name: "更新後")
        let revisions = EvidenceComparison.diff(before: populated, after: EvidenceComparison.snapshot(store))
        XCTAssertEqual(revisions.map(\.key), ["00000001"])
        XCTAssertThrowsError(try setup.save(name: String(repeating: "社", count: 17)))
    }

    func testCompanySavePropagatesSQLiteWriteFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ACAS.sqlite").path
        let store = try FileStore(path: path)
        let setup = CompanySetup(BusinessContext(store: store))
        try setup.save(name: "保存済み")

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = "CREATE TRIGGER reject_save BEFORE UPDATE ON files BEGIN SELECT RAISE(ABORT, 'blocked'); END"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try setup.save(name: "更新後")) { error in
            XCTAssertEqual((error as? FileStore.DatabaseError)?.code, SQLITE_CONSTRAINT)
        }
        XCTAssertEqual(setup.name, "保存済み")
    }

    func testFileStoreThrowsWhenDatabaseCannotBeOpened() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ACAS.sqlite").path
        XCTAssertThrowsError(try FileStore(path: path)) { error in
            XCTAssertEqual((error as? FileStore.DatabaseError)?.code, SQLITE_CANTOPEN)
        }
    }

    func testFileStoreThrowsWhenSchemaCannotBeInitialized() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("SQLite ではないファイル".utf8).write(to: url)
        XCTAssertThrowsError(try FileStore(path: url.path)) { error in
            XCTAssertEqual((error as? FileStore.DatabaseError)?.code, SQLITE_NOTADB)
        }
    }

    func testSeedRollsBackWhenIndexedRecordIsNotInserted() throws {
        let store = try FileStore()
        try store.writeRaw("existing.dat", [0x10])
        XCTAssertTrue(store.write("existing-index.dat", key: [0x01], data: [0x20]))
        let before = store.snapshot()
        let duplicate = Data("""
            {"files":{"seed.dat":{"type":"indexed","records":[["01","20"],["01","30"]]}}}
            """.utf8)

        XCTAssertThrowsError(try store.load(seed: duplicate)) { error in
            XCTAssertEqual(error as? FileStore.SeedError, .indexedRecordNotInserted(file: "seed.dat", key: "01"))
        }
        XCTAssertEqual(store.snapshot(), before)

        let valid = Data("""
            {"files":{"seed.dat":{"type":"indexed","records":[["01","40"]]}}}
            """.utf8)
        try store.load(seed: valid)
        XCTAssertEqual(store.snapshot(), ["seed.dat": ["01": "40"]])
    }

    func testCheckDigitUsesLegacyAlphabet() {
        XCTAssertEqual(Maps09.checkDigit("K9P34Y"), 2)
        XCTAssertTrue(Maps09.verify("K9P34Y2"))
        XCTAssertNil(Maps09.checkDigit("!!!!!!"))
    }
}
