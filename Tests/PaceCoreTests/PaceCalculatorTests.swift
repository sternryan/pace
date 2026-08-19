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
        // Projections now exist for on- and behind-pace lanes too. At exactly
        // on pace the cap lands exactly ON the reset, so it is not "before".
        XCTAssertNotNil(reading.projectedCapDate)
        XCTAssertEqual(reading.capBeforeReset, false)
    }

    func testBehindPaceProjectsAfterReset() {
        let windowLength: TimeInterval = 7 * 24 * 3600
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(2 * 24 * 3600) // 5/7 elapsed = ~71%
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 20, resetDate: resetDate, windowLength: windowLength)

        let reading = PaceCalculator.reading(for: lane, now: now)

        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNotNil(reading.projectedCapDate)
        XCTAssertEqual(reading.capBeforeReset, false)
    }

    func testNoAheadOfPaceVerdictInFirstTenMinutes() {
        // v1 live bug: at minute one, 1% used > 0% elapsed turned the icon red
        // on trivial usage. Suppress the verdict until the window has history.
        let now = Date()
        let lane = LaneUsage(kind: .session, percentUsed: 5,
                             resetDate: now.addingTimeInterval(5 * 3600 - 60), // 1 min elapsed
                             windowLength: 5 * 3600)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertFalse(reading.isAlarmed)
        XCTAssertNil(reading.projectedCapDate)
    }

    func testAheadOfPaceStillFiresAfterGuardWindow() {
        let now = Date()
        let lane = LaneUsage(kind: .session, percentUsed: 50,
                             resetDate: now.addingTimeInterval(5 * 3600 - 30 * 60), // 30 min elapsed
                             windowLength: 5 * 3600)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertTrue(reading.isAheadOfPace)
        XCTAssertTrue(reading.isAlarmed)
        XCTAssertNotNil(reading.projectedCapDate)
        XCTAssertEqual(reading.capBeforeReset, true) // 50% in 30min caps long before 5h
    }

    func testServerSeverityForcesAlarmEvenWhenBehindPace() {
        let now = Date()
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 10,
                             resetDate: now.addingTimeInterval(3 * 24 * 3600), // ~57% elapsed, 10% used
                             windowLength: 7 * 24 * 3600, severity: .critical)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertFalse(reading.isAheadOfPace) // local math says fine
        XCTAssertTrue(reading.isAlarmed)      // server says critical — server wins
    }

    func testBehindPaceLaneGetsResetsFirstProjection() {
        // 20% used at 25% elapsed of a 7-day window: behind pace, so the
        // projected cap lands AFTER the reset — the projection exists to say
        // "you don't need to care". (For an ahead-of-pace lane, cap-before-reset
        // is always true by construction, so this calming state only occurs on
        // behind-pace lanes.)
        let now = Date()
        let windowLength: TimeInterval = 7 * 24 * 3600
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 20,
                             resetDate: now.addingTimeInterval(windowLength * 0.75),
                             windowLength: windowLength)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNotNil(reading.projectedCapDate)
        XCTAssertEqual(reading.capBeforeReset, false)
    }

    func testAheadOfPaceLaneProjectsCapBeforeReset() {
        let now = Date()
        let windowLength: TimeInterval = 7 * 24 * 3600
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 40,
                             resetDate: now.addingTimeInterval(windowLength * 0.75),
                             windowLength: windowLength)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertTrue(reading.isAheadOfPace)
        XCTAssertEqual(reading.capBeforeReset, true)
    }

    func testResetLabelUnderADay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lane = LaneUsage(kind: .session, percentUsed: 21, resetDate: now.addingTimeInterval(3 * 3600 + 53 * 60), windowLength: nil)
        XCTAssertEqual(PaceFormatter.resetLabel(for: lane, now: now), "resets in 3h 53m")
    }
}
