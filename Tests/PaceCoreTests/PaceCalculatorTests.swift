import XCTest
@testable import PaceCore

final class PaceCalculatorTests: XCTestCase {
    func testUnknownWindowLengthProducesNoTickOrProjection() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: now.addingTimeInterval(3600), windowLength: nil)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertNil(reading.percentElapsed)
        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNil(reading.projectedCapDate)
    }

    func testAheadOfPaceComputesProjectionBeforeReset() {
        // 7-day window, reset in 4 days (so 3 of 7 days elapsed = ~43%), 70% used -> ahead.
        let windowLength: TimeInterval = 7 * 24 * 3600
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(4 * 24 * 3600)
        let lane = LaneUsage(kind: .fableWeek, percentUsed: 70, resetDate: resetDate, windowLength: windowLength)

        let reading = PaceCalculator.reading(for: lane, now: now)

        XCTAssertEqual(reading.percentElapsed, 42) // 3/7 days, truncated
        XCTAssertTrue(reading.isAheadOfPace)
        XCTAssertNotNil(reading.projectedCapDate)
        XCTAssertLessThan(reading.projectedCapDate!, resetDate)
    }

    func testExactlyOnPaceIsNotAhead() {
        // percentUsed == percentElapsed exactly is the boundary of "ahead" —
        // the comparison is strictly `>`, so equal must NOT count as ahead.
        let windowLength: TimeInterval = 7 * 24 * 3600
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(windowLength / 2) // exactly 50% elapsed
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 50, resetDate: resetDate, windowLength: windowLength)

        let reading = PaceCalculator.reading(for: lane, now: now)

        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNil(reading.projectedCapDate)
    }

    func testBehindPaceHasNoProjection() {
        let windowLength: TimeInterval = 7 * 24 * 3600
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(2 * 24 * 3600) // 5/7 elapsed = ~71%
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 20, resetDate: resetDate, windowLength: windowLength)

        let reading = PaceCalculator.reading(for: lane, now: now)

        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNil(reading.projectedCapDate)
    }

    func testResetLabelUnderADay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lane = LaneUsage(kind: .session, percentUsed: 21, resetDate: now.addingTimeInterval(3 * 3600 + 53 * 60), windowLength: nil)
        XCTAssertEqual(PaceFormatter.resetLabel(for: lane, now: now), "resets in 3h 53m")
    }

    func testProjectionLabel() {
        let resetDate = Date(timeIntervalSince1970: 10 * 3600)
        let capDate = resetDate.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(PaceFormatter.projectionLabel(capDate: capDate, resetDate: resetDate), "~2h before reset")
    }
}
