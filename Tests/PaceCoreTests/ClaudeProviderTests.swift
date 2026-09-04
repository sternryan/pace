import XCTest
@testable import PaceCore

private struct FakeSource: ClaudeUsageFetching {
    let result: Result<UsageSnapshot, FetchStatus>?
    func fetch() async -> Result<UsageSnapshot, FetchStatus>? { result }
}

final class ClaudeProviderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testSuccessMapsLanesAndOverage() async {
        let lanes = [LaneUsage(kind: .session, percentUsed: 10, resetDate: now.addingTimeInterval(3600), windowLength: 18000)]
        let snap = UsageSnapshot(lanes: lanes, extraUsage: ExtraUsage(dollarsUsed: 12.5, isEnabled: true), fetchedAt: now)
        let s = await ClaudeProvider(source: FakeSource(result: .success(snap))).fetch(now: now)
        XCTAssertEqual(s.source, .api); XCTAssertNil(s.error)
        XCTAssertEqual(s.lanes.map(\.kind), [.session, .overage])
        XCTAssertEqual(s.lanes[1].percentUsed, 12)     // ⚠ divisor unverified (spec §8) — label in UI
    }
    func testTokenExpiredIsNeedsLoginWithCache() async {
        let p = ClaudeProvider(source: FakeSource(result: .failure(.tokenExpired)))
        let s = await p.fetch(now: now)
        XCTAssertEqual(s.error, .needsLogin("open Claude Code to refresh sign-in"))
        XCTAssertEqual(s.source, .cache)
    }
}
