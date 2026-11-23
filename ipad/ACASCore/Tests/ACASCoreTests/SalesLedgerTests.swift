import SQLite3
import XCTest
@testable import ACASCore

final class SalesLedgerTests: XCTestCase {
    func testInitialCustomerSetupCreatesLedgersAndSetsCompanyFlags() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let ledger = SalesLedger(context)
        var system = Record(SystemLayout.layout)
        system["usera"] = "ACAS"
        system["sales-ledger"] = "N"
        system["sl-delim"] = "\\"
        system["file-statuses"] = String(repeating: "0", count: 32)
        try SalesInvoices(context).systemFile.write(1, system.bytes)
        XCTAssertFalse(store.exists(SalesProofRecords.salesFile(store).path))
        XCTAssertFalse(store.exists(ledger.deliveryFile.path))
        var contact = InitialCustomerSetup.Contact()
        contact.code = "TEST01"
        contact.name = "得意先"
        contact.address = "東京"
        let before = store.snapshot()
        XCTAssertThrowsError(try InitialCustomerSetup(context).add(contact)) {
            XCTAssertEqual($0 as? InitialCustomerSetup.Error, .invalidAddress)
        }
        XCTAssertEqual(store.snapshot(), before)
        contact.address = "東京\\日本"
        try InitialCustomerSetup(context).add(contact)
        XCTAssertEqual(store.kind(SalesProofRecords.salesFile(store).path), "indexed")
        XCTAssertEqual(store.kind(ledger.deliveryFile.path), "indexed")
        XCTAssertEqual(try ledger.customer(code: contact.code + String(XCTUnwrap(Maps09.checkDigit(contact.code)))).name, contact.name)
        system["sales-ledger"] = "Y"
        var flags = system.raw("file-statuses")
        flags[11] = 0x31
        flags[13] = 0x31
        system.setRaw("file-statuses", flags)
        XCTAssertEqual(try ledger.systemRecord().bytes, system.bytes)
        let code = contact.code + String(try XCTUnwrap(Maps09.checkDigit(contact.code)))
        var saved = try ledger.customer(code: code)
        saved.phone = "0123456789"
        try ledger.update(saved)
        XCTAssertEqual(try ledger.customer(code: code).phone, saved.phone)
    }

    func testAgeingRefusesOnlyPendingPaymentFlagOneWhenOpenItemsAreRegistered() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let file = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var system = Record(SystemLayout.layout)
        var statuses = system.raw("file-statuses")
        statuses[18] = 0x31
        system.setRaw("file-statuses", statuses)
        store.createIndexed(SalesOpenItems.path)
        for (flag, expected) in [(1, SalesReceivableOpening.Refusal.pendingPayments), (2, nil)] {
            system.setInt("s-flag-p", Int64(flag))
            try file.write(1, system.bytes)
            let before = store.snapshot()
            XCTAssertEqual(try SalesReceivableOpening.ageing.refusal(in: context), expected)
            XCTAssertEqual(store.snapshot(), before)
        }
    }

    func testFailedNotesWriteRollsBackRegistrationAndAllowsRetry() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        let store = try FileStore(path: path)
        let ledger = SalesLedger(BusinessContext(store: store))
        let systemFile = RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024)
        var system = Record(SystemLayout.layout)
        system["sl-delim"] = "\\"
        try systemFile.write(1, system.bytes)
        let before = store.snapshot()
        var customer = try ledger.newCustomer()
        customer.code = "TEST01"
        customer.name = "登録先"
        customer.address1 = "東京\\日本"
        customer.deliveryAddress1 = "大阪\\日本"
        customer.notes1 = "備考"
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, """
            CREATE TRIGGER reject_notes BEFORE INSERT ON records
            WHEN NEW.file = 'ledgers/acas/delivery.dat' AND hex(substr(NEW.key, 1, 1)) = '4E'
            BEGIN SELECT RAISE(ABORT, 'blocked'); END;
            """, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try ledger.register(customer)) { error in
            XCTAssertEqual(error as? SalesLedger.Error, .deliveryWriteFailed)
        }
        XCTAssertEqual(store.snapshot(), before)

        XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER reject_notes", nil, nil, nil), SQLITE_OK)
        let saved = try ledger.register(customer)
        XCTAssertEqual(try ledger.customer(code: saved.code).notes1, "備考")
    }

    func testAddressDelimiterOnlyMatchesAtCharacterBoundary() throws {
        let store = try FileStore()
        let ledger = SalesLedger(BusinessContext(store: store))
        var system = Record(SystemLayout.layout)
        system["sl-delim"] = "\\"
        try RelativeFile(store, path: "ledgers/acas/system.dat", recordSize: 1024).write(1, system.bytes)
        var customer = try ledger.newCustomer()
        customer.code = "TEST01"
        customer.name = "テスト"
        customer.address1 = "ソ"
        XCTAssertThrowsError(try ledger.register(customer)) { error in
            XCTAssertEqual(error as? SalesLedger.Error, .invalidAddress)
        }
        customer.address1 = "ソ\\1\\2\\3\\4"
        let saved = try ledger.register(customer)
        XCTAssertEqual(saved.address1, customer.address1)
    }
}
