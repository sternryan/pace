import XCTest
@testable import PaceCore

final class PacingEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // fixed clock

    func lane(_ kind: LaneKind, used: Int, windowLength: TimeInterval, elapsed: TimeInterval) -> LaneUsage {
        LaneUsage(kind: kind, percentUsed: used, resetDate: now.addingTimeInterval(windowLength - elapsed),
                  windowLength: windowLength, severity: .normal)
    }
    func snap(_ p: ProviderID, lanes: [LaneUsage] = [], laneState: LaneState? = nil,
              burn: BurnSeries? = nil, error: ProviderError? = nil, source: SnapshotSource = .api) -> ProviderSnapshot {
        ProviderSnapshot(provider: p, fetchedAt: now, source: source, lanes: lanes, laneState: laneState, burn: burn, error: error)
    }

    func testStatusBands() {
        // 20% used at 50% elapsed → onPace; 60% at 50% → ahead; 54% at 50% → onPace (5-pt slack); 100% → capped
        let l1 = lane(.session, used: 20, windowLength: 18000, elapsed: 9000)
        let l2 = lane(.session, used: 60, windowLength: 18000, elapsed: 9000)
        let l3 = lane(.session, used: 54, windowLength: 18000, elapsed: 9000)
        let l4 = lane(.session, used: 100, windowLength: 18000, elapsed: 9000)
        XCTAssertEqual(PaceCalculator.status(for: l1, now: now), .onPace)
        XCTAssertEqual(PaceCalculator.status(for: l2, now: now), .ahead)
        XCTAssertEqual(PaceCalculator.status(for: l3, now: now), .onPace)
        XCTAssertEqual(PaceCalculator.status(for: l4, now: now), .capped)
    }

    func testTooEarlyUnder15Minutes() {
        let l = lane(.session, used: 40, windowLength: 18000, elapsed: 600)
        XCTAssertEqual(PaceCalculator.status(for: l, now: now), .tooEarly)
    }

    func testProjectionUsesBurnRateWhenPresent() {
        // 50% used, 1h elapsed of a 5h window. Burn: 1,000,000 tokens attributed since window start,
        // trailing-hour rate = 1,000,000 tokens/h → 20,000 tokens per percent → 50 remaining % = 1h.
        let l = lane(.session, used: 50, windowLength: 18000, elapsed: 3600)
        let start = now.addingTimeInterval(-3600)
        let burn = BurnSeries(hourly: [HourBucket(start: start, provider: .claude, tokens: 1_000_000, costUSD: 1)],
                              daily: [], unparsedLines: 0)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l]), snap(.spend, burn: burn)], now: now)
        let v = report.windows.first { $0.kind == .session }!
        XCTAssertEqual(v.projectedCapAt!.timeIntervalSince(now), 3600, accuracy: 5)
        XCTAssertEqual(v.projectionBasis, .burnRate)
    }

    func testProjectionFallsBackToPercentRateWithoutBurn() {
        let l = lane(.session, used: 50, windowLength: 18000, elapsed: 3600)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        let v = report.windows.first { $0.kind == .session }!
        XCTAssertEqual(v.projectedCapAt!.timeIntervalSince(now), 3600, accuracy: 5)  // 50%/h → 1h
        XCTAssertEqual(v.projectionBasis, .percentRate)
    }

    func testProjectionClampedToResetsFirst() {
        let l = lane(.session, used: 10, windowLength: 18000, elapsed: 9000)   // 10% at 50% → caps after reset
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        let v = report.windows.first!
        XCTAssertNil(v.projectedCapAt)
        XCTAssertTrue(v.resetsFirst)
    }

    func testHeadlinePicksSoonestCap() {
        let a = lane(.session, used: 60, windowLength: 18000, elapsed: 9000)        // caps in 1.25h
        let b = lane(.codexWeek, used: 60, windowLength: 604800, elapsed: 302400)   // caps in 3.5d
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [a]), snap(.codex, lanes: [b])], now: now)
        XCTAssertEqual(report.headline?.kind, .session)
    }

    func testHeadlineWhenNothingAheadIsTightest() {
        let a = lane(.session, used: 30, windowLength: 18000, elapsed: 9000)   // -20
        let b = lane(.codexWeek, used: 45, windowLength: 604800, elapsed: 302400) // -5 → tightest
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [a]), snap(.codex, lanes: [b])], now: now)
        XCTAssertEqual(report.headline?.kind, .codexWeek)
        XCTAssertNil(report.advice)
    }

    func testAdviceBranches() {
        let ahead = lane(.fableWeek, used: 80, windowLength: 604800, elapsed: 302400)
        for (state, expected) in [(LaneState.serving, "move bulk/mechanical work to smithy (hearth:8085 local-heavy)"),
                                  (.leasedAway, "smithy GPU is leased; Codex is the next lane"),
                                  (.unreachable, "smithy unreachable, check before routing there")] {
            let r = PacingEngine.report(snapshots: [snap(.claude, lanes: [ahead]), snap(.smithy, laneState: state)], now: now)
            XCTAssertEqual(r.advice, expected, "\(state)")
        }
    }

    func testAdviceWhenCodexIsTheCappedOne() {
        let capped = lane(.codexWeek, used: 100, windowLength: 604800, elapsed: 302400)
        let r = PacingEngine.report(snapshots: [snap(.codex, lanes: [capped]), snap(.smithy, laneState: .leasedAway)], now: now)
        XCTAssertEqual(r.advice, "smithy GPU is leased; Claude is the next lane")
    }

    func testProviderStatusesAndStaleFlag() {
        let r = PacingEngine.report(snapshots: [snap(.claude, lanes: [], error: .transient("500"), source: .cache),
                                                snap(.smithy, laneState: .serving)], now: now)
        XCTAssertTrue(r.stale)
        XCTAssertEqual(r.providers.first { $0.provider == .claude }?.error, "500")
        XCTAssertEqual(r.providers.first { $0.provider == .claude }?.source, .cache)
    }

    func testVerdictLineFormat() {
        let l = lane(.fableWeek, used: 71, windowLength: 604800, elapsed: 326592) // 54%
        let r = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        XCTAssertTrue(r.windows[0].verdict.hasPrefix("Fable · week: 71% used, 54% elapsed, caps "))
    }
}
