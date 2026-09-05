import XCTest
@testable import PaceCore

final class CoreTypesTests: XCTestCase {
    func testLaneKindDisplayNames() {
        XCTAssertEqual(LaneKind.session.displayName, "Current session")
        XCTAssertEqual(LaneKind.allModelsWeek.displayName, "All models · week")
        XCTAssertEqual(LaneKind.fableWeek.displayName, "Fable · week")
    }

    func testLaneKindIsHashable() {
        let set: Set<LaneKind> = [.session, .session, .fableWeek]
        XCTAssertEqual(set.count, 2)
    }

    func testLaneUsageEquality() {
        let date = Date(timeIntervalSince1970: 0)
        let a = LaneUsage(kind: .session, percentUsed: 21, resetDate: date, windowLength: nil)
        let b = LaneUsage(kind: .session, percentUsed: 21, resetDate: date, windowLength: nil)
        XCTAssertEqual(a, b)
    }

    func testFetchStatusEquality() {
        XCTAssertEqual(FetchStatus.parseError("x"), FetchStatus.parseError("x"))
        XCTAssertNotEqual(FetchStatus.parseError("x"), FetchStatus.parseError("y"))
        XCTAssertNotEqual(FetchStatus.ok, FetchStatus.needsLogin)
        XCTAssertNotEqual(FetchStatus.needsLogin, FetchStatus.navigationFailed("x"))
    }

    func testLaneSeverityMapsServerStringsAndUnknowns() {
        XCTAssertEqual(LaneSeverity(rawServerValue: "critical"), .critical)
        XCTAssertEqual(LaneSeverity(rawServerValue: "exceeded"), .exceeded)
        XCTAssertEqual(LaneSeverity(rawServerValue: "warning"), .warning)
        XCTAssertEqual(LaneSeverity(rawServerValue: "normal"), .normal)
        // Unknown strings must degrade to normal, never crash — the endpoint is
        // undocumented and severity vocabulary can grow.
        XCTAssertEqual(LaneSeverity(rawServerValue: "melting"), .normal)
        XCTAssertEqual(LaneSeverity(rawServerValue: nil), .normal)
    }

    func testLaneSeverityAlarming() {
        XCTAssertTrue(LaneSeverity.critical.isAlarming)
        XCTAssertTrue(LaneSeverity.exceeded.isAlarming)
        XCTAssertFalse(LaneSeverity.warning.isAlarming)
        XCTAssertFalse(LaneSeverity.normal.isAlarming)
    }

    func testLaneUsageDefaultsPreserveV1CallSites() {
        let lane = LaneUsage(kind: .session, percentUsed: 10, resetDate: Date(), windowLength: 5 * 3600)
        XCTAssertEqual(lane.severity, .normal)
        XCTAssertNil(lane.displayNameOverride)
    }

    func testLaneUsageDisplayNameOverride() {
        // The override must actually flow through — a renamed model relabels the
        // lane. Using a DIFFERENT name than the kind's default so an
        // implementation that ignores the override can't pass this vacuously.
        let lane = LaneUsage(kind: .fableWeek, percentUsed: 10, resetDate: Date(), windowLength: nil,
                             severity: .warning, displayNameOverride: "Meridian")
        XCTAssertEqual(lane.effectiveDisplayName, "Meridian · week")
        let plain = LaneUsage(kind: .fableWeek, percentUsed: 10, resetDate: Date(), windowLength: nil)
        XCTAssertEqual(plain.effectiveDisplayName, "Fable · week")
    }
}
