import XCTest
@testable import ACASCore

final class SalesAnalysisTests: XCTestCase {
    func testUnconfiguredPageLengthDoesNotProduceEmptyAnalysisPage() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        try CompanySetup(context).save(name: "TEST")
        let service = SalesAnalysis(context)
        try service.prepare()

        XCTAssertEqual(try service.printTotals()?.map(\.code.group), ["a", "v", "z"])
        let report = try XCTUnwrap(store.readRaw(SalesAnalysis.exportPath))
        XCTAssertFalse(report.contains(0x0c))
    }

    func testDistinguishesOverlongAndUnsupportedDescriptionsAndPrintCodes() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store)
        try CompanySetup(context).save(name: "TEST")
        let service = SalesAnalysis(context)
        try service.prepare()
        let name = String(repeating: "売", count: 12)
        try service.save(group: "A", account: 1, description: name, printCode: "売A")
        let saved = try XCTUnwrap(service.codes().first { $0.group == "A" })
        XCTAssertEqual(saved.description, name)
        XCTAssertEqual(saved.printCode, "売A")

        let before = store.snapshot()
        let invalidFields: [(String, String, SalesAnalysis.Error)] = [
            (name + "売", "売A", .invalidDescription),
            (name, "売上", .invalidPrintCode),
            ("😀", "売A", .unsupportedDescription),
            (name, "😀", .unsupportedPrintCode),
        ]
        for (description, printCode, expected) in invalidFields {
            XCTAssertThrowsError(try service.save(group: "A", account: 1, description: description,
                                                  printCode: printCode, replacing: true)) {
                XCTAssertEqual($0 as? SalesAnalysis.Error, expected)
            }
            XCTAssertEqual(store.snapshot(), before)
        }
    }

    func testSetupAndRegistrationPreserveLegacyLayouts() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let files = SalesInvoices(context)
        var system = Record(SystemLayout.layout)
        system["file-statuses"] = String(repeating: "0", count: 32)
        system.setInt("page-lines", 60)
        system.setInt("s-flag-a", 1)
        try files.systemFile.write(1, system.bytes)
        let service = SalesAnalysis(context)

        try service.prepare()
        XCTAssertEqual(try service.codes().count, 8)
        XCTAssertEqual(try service.codes(allLedgers: true).count, 16)
        XCTAssertEqual(Set(store.all(SalesPosting.analysisPath).map { $0.data.count }), [36])
        XCTAssertEqual(Set(store.all(SalesPosting.valuePath).map { $0.data.count }), [66])
        XCTAssertThrowsError(try service.save(group: "A1", account: 400_001, description: "", printCode: "")) {
            XCTAssertEqual($0 as? SalesAnalysis.Error, .missingGroup)
        }
        try service.save(group: "A", account: 400_001, description: "国内売上", printCode: "A")
        let key = Array("SA ".utf8)
        let row = try XCTUnwrap(store.read(SalesPosting.analysisPath, key: key))
        XCTAssertEqual(Array(row.prefix(9)), Array("SA 400001".utf8))
        XCTAssertNil(store.read(SalesPosting.valuePath, key: key))
        XCTAssertThrowsError(try service.save(group: "A1", account: 400_001, description: "", printCode: "")) {
            XCTAssertEqual($0 as? SalesAnalysis.Error, .groupUsed)
        }
        XCTAssertTrue(try service.printCodes(allLedgers: false).contains { $0.group == "A" && $0.description == "国内売上" })
        XCTAssertTrue(try XCTUnwrap(store.readRaw(SalesAnalysis.exportPath)).starts(with: Array("SL070 (3.01.11)".utf8)))
        XCTAssertEqual(try service.printTotals()?.map(\.code.group), ["a", "v", "z"])
        XCTAssertEqual(try files.settings().int("s-flag-a"), 0)
        XCTAssertTrue(try XCTUnwrap(store.readRaw(SalesAnalysis.exportPath)).starts(with: Array("SL130 (3.01.07)".utf8)))
        try service.delete(group: "A")
        XCTAssertNil(store.read(SalesPosting.analysisPath, key: key))
    }

    func testStatus39RecordIsNotOverwritten() throws {
        let store = try FileStore()
        let context = BusinessContext(store: store, timeZone: .gmt)
        let files = SalesInvoices(context)
        var system = Record(SystemLayout.layout)
        system["file-statuses"] = String(repeating: "0", count: 14) + "1"
        try files.systemFile.write(1, system.bytes)
        let bytes = Array(repeating: UInt8(0x20), count: 66)
        XCTAssertTrue(store.write(SalesPosting.analysisPath, key: Array("SA ".utf8), data: bytes))
        let before = store.snapshot()
        let service = SalesAnalysis(context)
        XCTAssertThrowsError(try service.validateRegistration()) {
            XCTAssertEqual($0 as? SalesAnalysis.Error, .invalidLayout)
        }
        try service.prepare()
        XCTAssertThrowsError(try service.codes()) { XCTAssertEqual($0 as? SalesAnalysis.Error, .invalidLayout) }
        XCTAssertThrowsError(try service.save(group: "A", account: 400_001, description: "", printCode: ""))
        XCTAssertEqual(store.snapshot(), before)
    }
}
