import XCTest
@testable import PaceCore

final class CodexSessionUsageSourceTests: XCTestCase {
    func testReadsLatestRateLimitsFromNewestFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let line = #"{"payload":{"rate_limits":{"primary":{"used_percent":42,"window_minutes":300,"resets_at":1800003600},"secondary":{"used_percent":90,"window_minutes":10080,"resets_at":1800300000}}}}"#
        try (line + "\n").write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let src = CodexSessionUsageSource(sessionsDirectory: dir)
        let lanes = src.latestLanes(now: now)!
        XCTAssertEqual(lanes.map(\.kind), [.codexSession, .codexWeek])
        XCTAssertEqual(lanes[0].percentUsed, 42)
        XCTAssertEqual(lanes[1].percentUsed, 90)
    }

    func testEmptyDirectoryReturnsNil() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNil(CodexSessionUsageSource(sessionsDirectory: dir).latestLanes(now: Date()))
    }
}
