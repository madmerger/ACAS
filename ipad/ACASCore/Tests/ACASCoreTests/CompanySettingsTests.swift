import ACASCore
import XCTest

final class CompanySettingsTests: XCTestCase {
    func testCreditDaysCannotExceedTheLegacyInputWidth() throws {
        let setup = CompanySetup(BusinessContext(store: try FileStore()))
        var settings = setup.settings
        try settings.setNumber(99, for: "sl-credit")
        XCTAssertThrowsError(try settings.setNumber(120, for: "sl-credit"))
        XCTAssertEqual(settings.number("sl-credit"), 99)
    }

    func testSettingsCodesNormalizeLowercaseLikeLegacyInput() throws {
        let setup = CompanySetup(BusinessContext(store: try FileStore()))
        var settings = setup.settings
        for (key, input, expected) in [("p-c", "p", "P"), ("p-c-level", "r", "R"),
                                       ("stk-period-cur", "q", "Q"), ("stk-period-dat", "y", "Y"),
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
        XCTAssertNotNil(Data(report).range(of: Data(address.prefix(43))))
    }
}
