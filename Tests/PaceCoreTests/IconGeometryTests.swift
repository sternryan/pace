import XCTest
@testable import PaceCore

final class IconGeometryTests: XCTestCase {
    func testGeometryWithKnownWindow() {
        let lane = LaneUsage(kind: .fableWeek, percentUsed: 45, resetDate: Date(), windowLength: 7 * 24 * 3600)
        let reading = PaceReading(lane: lane, percentElapsed: 47, isAheadOfPace: false, projectedCapDate: nil)
        let geo = IconGeometry.barGeometry(for: reading)
        XCTAssertEqual(geo.fillFraction, 0.45, accuracy: 0.001)
        if let tickFraction = geo.tickFraction {
            XCTAssertEqual(tickFraction, 0.47, accuracy: 0.001)
        } else {
            XCTFail("Expected tickFraction to be present")
        }
        XCTAssertFalse(geo.isHot)
    }

    func testGeometryWithUnknownWindow() {
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: Date(), windowLength: nil)
        let reading = PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false, projectedCapDate: nil)
        let geo = IconGeometry.barGeometry(for: reading)
        XCTAssertEqual(geo.fillFraction, 0.70, accuracy: 0.001)
        XCTAssertNil(geo.tickFraction)
    }

    func testGeometryMarksHotWhenAheadOfPace() {
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: Date(), windowLength: 5 * 3600)
        let reading = PaceReading(lane: lane, percentElapsed: 40, isAheadOfPace: true, projectedCapDate: Date())
        let geo = IconGeometry.barGeometry(for: reading)
        XCTAssertTrue(geo.isHot)
    }
}
