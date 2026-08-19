import XCTest
@testable import PaceCore

final class UsageSnapshotTests: XCTestCase {
    private func sampleSnapshot(fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            lanes: [
                LaneUsage(kind: .session, percentUsed: 67, resetDate: fetchedAt.addingTimeInterval(3600),
                          windowLength: 5 * 3600, severity: .warning),
                LaneUsage(kind: .fableWeek, percentUsed: 60, resetDate: fetchedAt.addingTimeInterval(86400),
                          windowLength: 7 * 24 * 3600, displayNameOverride: "Fable")
            ],
            extraUsage: ExtraUsage(dollarsUsed: 12.34, isEnabled: true),
            fetchedAt: fetchedAt
        )
    }

    func testRoundTripsThroughJSON() throws {
        let snapshot = sampleSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testDecodeToleratesUnknownFields() throws {
        // Forward-compat: a snapshot written by a NEWER Pace with extra keys
        // must still load — the cache must never brick a downgrade/upgrade.
        let snapshot = sampleSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        object["futureField"] = ["nested": true]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNoThrow(try JSONDecoder().decode(UsageSnapshot.self, from: data))
    }

}
