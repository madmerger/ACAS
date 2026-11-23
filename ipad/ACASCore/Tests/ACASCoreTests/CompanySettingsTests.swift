import ACASCore
import XCTest

final class CompanySettingsTests: XCTestCase {
    func testInitialRecordPrecedesSettingsAndReport() throws {
        let store = try FileStore()
        let setup = CompanySetup(BusinessContext(store: store))
        var draft = setup.settings
        try draft.setText("TEST", for: "usera")
        try draft.setText("Test Street", for: "address-1")
        try draft.setNumber(1, for: "level-1")
        try draft.setNumber(1, for: "scycle")

        try setup.prepareInitialRecord(draft)
        XCTAssertEqual(setup.name, "TEST")
        XCTAssertEqual(setup.settings.number("level-1"), 1)
        XCTAssertEqual(setup.settings.number("scycle"), 0)
        XCTAssertEqual(setup.settings.text("address-1"), "")
        XCTAssertNil(store.readRaw(CompanySetup.reportPath))

        try setup.save(draft, printReport: true)
        XCTAssertEqual(setup.settings.number("scycle"), 1)
        XCTAssertEqual(setup.settings.text("address-1"), "Test Street")
        XCTAssertNotNil(store.readRaw(CompanySetup.reportPath))
    }

    func testCreditDaysCannotExceedTheLegacyInputWidth() throws {
        let setup = CompanySetup(BusinessContext(store: try FileStore()))
        var settings = setup.settings
        try settings.setNumber(99, for: "sl-credit")
        XCTAssertThrowsError(try settings.setNumber(120, for: "sl-credit"))
        XCTAssertEqual(settings.number("sl-credit"), 99)
    }

    func testInitialConfirmationPreservesMasterRegistrationStatus() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        let setup = CompanySetup(context)
        var draft = setup.settings
        try draft.setText("TEST", for: "usera")
        try draft.setText("Test Street", for: "address-1")
        try setup.prepareInitialRecord(draft)
        var contact = MasterContact()
        contact.code = "CUST01"
        contact.name = "ALPHA CUSTOMER"
        try MasterSetup(context).add(contact, as: .customer)
        let statuses = setup.settings.text("file-statuses")
        XCTAssertEqual(setup.settings.text("sales-ledger"), "Y")

        try setup.save(draft)
        XCTAssertEqual(setup.settings.text("sales-ledger"), "Y")
        XCTAssertEqual(setup.settings.text("file-statuses"), statuses)
        XCTAssertEqual(setup.settings.text("address-1"), "Test Street")
    }

    func testSettingsCodesNormalizeLowercaseLikeLegacyInput() throws {
        let setup = CompanySetup(BusinessContext(store: try FileStore()))
        var settings = setup.settings
        for (key, input, expected) in [("p-c", "p", "P"), ("p-c-level", "r", "R"),
                                       ("stk-period-cur", "q", "Q"), ("stk-period-dat", "y", "Y"),
                                       ("sl-vat-printed", "y", "Y"), ("sl-vat-printed", "n", "N"),
                                       ("usera", "Business", "Business")] {
            try settings.setText(input, for: key)
            XCTAssertEqual(settings.text(key), expected)
        }
    }

    func testReportKeepsLegacyAddressBytesWhenCountryOverflows() throws {
        let store = try FileStore()
        let setup = CompanySetup(BusinessContext(store: store))
        var settings = setup.settings
        try settings.setText("TEST", for: "usera")
        try settings.setText(String(repeating: "東", count: 12), for: "address-4")
        try settings.setText("1234567890", for: "post-code")
        try settings.setText("日本日本", for: "country")
        try setup.save(settings, printReport: true)
        let report = try XCTUnwrap(store.readRaw(CompanySetup.reportPath))
        let address = SJIS.encode(String(repeating: "東", count: 12) + ",1234567890,日本日本", size: 44)
        let lines = report.split(separator: 10, omittingEmptySubsequences: false)
        let line = try XCTUnwrap(lines.dropFirst(9).first)
        let expected = [UInt8](repeating: 32, count: 27) + address.prefix(43)
            + SJIS.encode("Alphabetic Ledger Index not Selected", size: 50)
            + [UInt8](repeating: 32, count: 12)
        XCTAssertEqual(Array(line), expected)
    }
}
