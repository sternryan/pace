import XCTest
@testable import PaceCore

final class PaceFormatterTests: XCTestCase {
    func testProjectionLabelCapBeforeReset() {
        let reset = Date(timeIntervalSince1970: 1_787_300_000)
        let cap = reset.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(PaceFormatter.projectionLabel(capDate: cap, resetDate: reset, capBeforeReset: true),
                       "~2h before reset")
    }

    func testProjectionLabelResetsFirstSaysSo() {
        // The projection's answer to "do I need to care?" — when the reset
        // arrives before the projected cap, say that instead of an alarm.
        let reset = Date(timeIntervalSince1970: 1_787_300_000)
        let cap = reset.addingTimeInterval(3 * 3600)
        XCTAssertEqual(PaceFormatter.projectionLabel(capDate: cap, resetDate: reset, capBeforeReset: false),
                       "after reset — resets first")
    }

    func testAgeLabel() {
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        XCTAssertEqual(PaceFormatter.ageLabel(since: now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(PaceFormatter.ageLabel(since: now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(PaceFormatter.ageLabel(since: now.addingTimeInterval(-3 * 86400), now: now), "3d ago")
    }
}
