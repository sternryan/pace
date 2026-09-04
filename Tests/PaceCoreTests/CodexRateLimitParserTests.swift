import XCTest
@testable import PaceCore

final class CodexRateLimitParserTests: XCTestCase {
    func testDecodesPrimaryAndSecondaryWindowsFromLatestEvent() throws {
        let jsonl = #"""
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1787167473},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1787768673}}}}
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":13.6,"window_minutes":300,"resets_at":1787167473},"secondary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1787768673}}}}
        """#

        let snapshot = try XCTUnwrap(CodexRateLimitParser.snapshot(fromJSONLines: jsonl,
                                                                     now: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.codexSession, .codexWeek])
        XCTAssertEqual(snapshot.lanes.map(\.percentUsed), [14, 42])
        XCTAssertEqual(snapshot.lanes.map(\.effectiveDisplayName), ["Codex 5h", "Codex · week"])
        XCTAssertEqual(snapshot.lanes.map(\.windowLength), [18_000, 604_800])
    }

    func testDecodesAnAccountWithOnlyOneActiveWindow() throws {
        let jsonl = #"""
        {"payload":{"rate_limits":{"primary":{"used_percent":7,"window_minutes":10080,"resets_at":1787167473},"secondary":null}}}
        """#
        let snapshot = try XCTUnwrap(CodexRateLimitParser.snapshot(fromJSONLines: jsonl))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.codexWeek])
        XCTAssertEqual(snapshot.lanes.first?.effectiveDisplayName, "Codex · week")
    }

    func testIgnoresEventsWithoutRateLimits() {
        XCTAssertNil(CodexRateLimitParser.snapshot(fromJSONLines: "{\"payload\":{\"type\":\"message\"}}"))
    }
}
