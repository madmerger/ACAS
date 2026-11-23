import Foundation
import XCTest
@testable import ACASCore

final class FoundationTests: XCTestCase {
    func testSnapshotsReadLogicalRecordsAndExcludeReports() throws {
        let store = FileStore()
        let before = EvidenceComparison.snapshot(store)
        let setup = CompanySetup(BusinessContext(store: store))
        try setup.save(name: "テスト会社")
        XCTAssertEqual(setup.name, "テスト会社")
        store.writeRaw("ledgers/acas/prt-1", [0, 15])

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

    func testCheckDigitUsesLegacyAlphabet() {
        XCTAssertEqual(Maps09.checkDigit("K9P34Y"), 2)
        XCTAssertTrue(Maps09.verify("K9P34Y2"))
        XCTAssertNil(Maps09.checkDigit("!!!!!!"))
    }
}
