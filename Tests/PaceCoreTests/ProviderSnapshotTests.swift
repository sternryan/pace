import XCTest
@testable import PaceCore

final class ProviderSnapshotTests: XCTestCase {
    func testLaneKindHasCodexAndOverageCases() {
        XCTAssertEqual(LaneKind.codexSession.rawValue, "codexSession")
        XCTAssertEqual(LaneKind.codexWeek.rawValue, "codexWeek")
        XCTAssertEqual(LaneKind.overage.rawValue, "overage")
        XCTAssertEqual(LaneKind.codexSession.displayName, "Codex 5h")
        XCTAssertEqual(LaneKind.codexSession.provider, .codex)
        XCTAssertEqual(LaneKind.fableWeek.provider, .claude)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snap = ProviderSnapshot(provider: .smithy, fetchedAt: Date(timeIntervalSince1970: 1_000),
                                    source: .api, lanes: [], laneState: .leasedAway, burn: nil,
                                    error: .transient("timeout"))
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(ProviderSnapshot.self, from: data)
        XCTAssertEqual(back, snap)
    }

    func testLaneStateHasExactlyThreeCases() {
        XCTAssertEqual(LaneState.allCases.map(\.rawValue), ["serving", "leasedAway", "unreachable"])
    }
}
