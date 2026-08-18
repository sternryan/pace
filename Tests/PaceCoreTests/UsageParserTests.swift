import XCTest
@testable import PaceCore

final class UsageParserTests: XCTestCase {
    func testParsePercent() {
        XCTAssertEqual(UsageParser.parsePercent("21% used"), 21)
        XCTAssertEqual(UsageParser.parsePercent("16% used"), 16)
        XCTAssertEqual(UsageParser.parsePercent("100% used"), 100)
        XCTAssertNil(UsageParser.parsePercent("no percent here"))
    }

    func testParseRelativeReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = UsageParser.parseRelativeReset("Resets in 3 hr 53 min", now: now)
        XCTAssertEqual(result, now.addingTimeInterval(3 * 3600 + 53 * 60))
    }

    func testParseRelativeResetMinutesOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = UsageParser.parseRelativeReset("Resets in 45 min", now: now)
        XCTAssertEqual(result, now.addingTimeInterval(45 * 60))
    }

    func testParseRelativeResetReturnsNilForUnrelatedText() {
        XCTAssertNil(UsageParser.parseRelativeReset("Resets Sat 2:00 PM", now: Date()))
    }

    func testParseWeekdayReset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Tuesday 2026-08-18 12:00 UTC
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!
        let result = UsageParser.parseWeekdayReset("Resets Sat 2:00 PM", now: now, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 14))!
        XCTAssertEqual(result, expected)
    }
}
