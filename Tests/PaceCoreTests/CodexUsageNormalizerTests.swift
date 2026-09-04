import XCTest
@testable import PaceCore

final class CodexUsageNormalizerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture() throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: "codex-wham-usage", withExtension: "json", subdirectory: "Fixtures")!)
    }
    func testMapsPrimaryAndSecondaryWindows() throws {
        let lanes = CodexUsageNormalizer.lanes(fromJSON: try fixture(), now: now)!
        XCTAssertEqual(lanes.map(\.kind), [.codexSession, .codexWeek])
        XCTAssertEqual(lanes[0].percentUsed, 37)
        XCTAssertEqual(lanes[0].windowLength, 18000)
        XCTAssertEqual(lanes[0].resetDate, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(lanes[1].percentUsed, 100)
        XCTAssertEqual(lanes[1].severity, .exceeded)
    }
    func testResetAfterSecondsUsedWhenResetAtMissing() {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":5,"reset_after_seconds":120,"limit_window_seconds":18000}}}"#.data(using: .utf8)!
        let lanes = CodexUsageNormalizer.lanes(fromJSON: json, now: now)!
        XCTAssertEqual(lanes[0].resetDate, now.addingTimeInterval(120))
    }
    func testGarbageReturnsNil() {
        XCTAssertNil(CodexUsageNormalizer.lanes(fromJSON: Data("nope".utf8), now: now))
        XCTAssertNil(CodexUsageNormalizer.lanes(fromJSON: Data("{}".utf8), now: now))
    }
}
