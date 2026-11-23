import ACASCore
import SQLite3
import XCTest

final class MasterSetupTests: XCTestCase {
    func testContactCanBeRetriedAfterCompanyStatusWriteFails() throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: location) }
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: false)
        let path = location.appendingPathComponent("acas.sqlite").path
        let store = try FileStore(path: path)
        let context = BusinessContext(store: store)
        try CompanySetup(context).save(name: "TEST BUSINESS")
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, """
            CREATE TRIGGER fail_system_write BEFORE INSERT ON files
            WHEN NEW.name LIKE '%/system.dat' BEGIN SELECT RAISE(ABORT, 'test'); END
            """, nil, nil, nil), SQLITE_OK)
        var contact = MasterContact()
        contact.code = "CUST01"
        let service = MasterSetup(context)
        XCTAssertThrowsError(try service.add(contact, as: .customer))
        XCTAssertFalse(store.exists("ledgers/acas/salesled.dat"))
        XCTAssertFalse(store.exists("ledgers/acas/delivery.dat"))
        XCTAssertEqual(sqlite3_exec(database, "DROP TRIGGER fail_system_write", nil, nil, nil), SQLITE_OK)
        try service.add(contact, as: .customer)
        XCTAssertEqual(store.count("ledgers/acas/salesled.dat"), 1)
    }

    func testContactKeysDefaultsAndRecords() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt, now: { Date(timeIntervalSince1970: 1_795_407_600) })
        let service = MasterSetup(context)
        var contact = MasterContact()
        contact.code = "cust01"
        contact.name = "ALPHA CUSTOMER"
        contact.address = "1 TEST ROAD"
        contact.address2 = "LONDON"
        contact.phone = "01234567890"
        contact.email = "alpha@example.test"
        XCTAssertThrowsError(try service.add(contact, as: .customer))

        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST BUSINESS", for: "usera")
        try settings.setNumber(0, for: "sl-charges")
        try settings.setNumber(0, for: "sl-dunning")
        try settings.setNumber(10_000, for: "sl-limit")
        try setup.save(settings)
        try service.add(contact, as: .customer)
        let sales = try XCTUnwrap(store.read("ledgers/acas/salesled.dat", key: Array("CUST011".utf8)))
        XCTAssertEqual(sales.count, 300)
        XCTAssertEqual(Array(sales[193..<206]), Array("10000000".utf8) + [0, 0, 0] + Array("30".utf8))
        XCTAssertEqual(Array(sales[212..<216]), [0x10, 0x27, 0, 0])
        XCTAssertThrowsError(try service.add(contact, as: .customer))

        contact.code = "SUPP01"
        contact.email = ""
        contact.name = "ALPHA SUPPLIER"
        try service.add(contact, as: .supplier)
        let purchase = try XCTUnwrap(store.read("ledgers/acas/purchled.dat", key: Array("SUPP018".utf8)))
        XCTAssertEqual(purchase.count, 300)
        XCTAssertEqual(Array(purchase[7..<9]), Array("10".utf8))
        XCTAssertEqual(Array(purchase[226..<230]), Array(sales[244..<248]))
    }

    func testStockFixedWidthAmountsAndUniqueAbbreviation() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var settings = setup.settings
        try settings.setText("TEST BUSINESS", for: "usera")
        try settings.setNumber(1, for: "stk-averaging")
        try setup.save(settings, printReport: true)
        let report = try XCTUnwrap(store.readRaw(CompanySetup.reportPath))
        let service = MasterSetup(context)
        var item = MasterStockItem()
        item.code = "item001"
        item.abbreviation = "itm001"
        item.name = "ALPHA WIDGET"
        item.location = "BIN-A"
        item.held = 10
        item.reorderPoint = 2
        item.reorderQuantity = 5
        item.retail = 1_200
        item.cost = 50_000
        try service.add(item)
        let bytes = try XCTUnwrap(store.read("ledgers/acas/stockctl.dat", key: Array("ITEM001      ".utf8)))
        XCTAssertEqual(bytes.count, 400)
        XCTAssertEqual(Array(bytes[128..<136]), [0, 0, 0, 2, 0, 0, 0, 5])
        XCTAssertEqual(Array(bytes[144..<148]), [0, 0, 0, 10])
        XCTAssertEqual(Array(bytes[152..<169]), [0, 0, 1, 0x20, 0x0F, 0, 0, 0, 0x50, 0, 0x0F, 0, 0, 0, 5, 0, 0x0F])
        XCTAssertEqual(setup.settings.text("stock-control"), "Y")
        XCTAssertEqual(setup.settings.text("file-statuses"), "00000000001010100000000000000000")
        XCTAssertEqual(store.all("ledgers/acas/analysis.dat").count, 16)
        XCTAssertEqual(store.readRaw(CompanySetup.reportPath), report)
        item.code = "ITEM002"
        XCTAssertThrowsError(try service.add(item))
    }
}
