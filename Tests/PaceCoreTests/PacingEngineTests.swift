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

    // Fix round 1, finding #1: BurnSeries.hourly only covers a trailing
    // window (documented as 8 days). A weekly lane's "since window start"
    // burn attribution must not trust a series that doesn't reach back that
    // far — it collapses into a false, wildly-inflated rate.
    func testWeeklyLaneWithOnlySixHoursOfBurnFallsBackToPercentRate() {
        let l = lane(.fableWeek, used: 50, windowLength: 604800, elapsed: 302400) // 3.5 days elapsed of 7
        let buckets = (1...6).map { h in
            HourBucket(start: now.addingTimeInterval(-Double(h) * 3600), provider: .claude, tokens: 50_000, costUSD: 1)
        }
        let burn = BurnSeries(hourly: buckets, daily: [], unparsedLines: 0)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l]), snap(.spend, burn: burn)], now: now)
        let v = report.windows.first { $0.kind == .fableWeek }!
        XCTAssertEqual(v.projectionBasis, .percentRate)
    }

    // F4: burn attribution is per provider, not per model — a scoped lane
    // like fableWeek shares its provider's token stream with every other
    // Claude lane, so it can never trust burnRate, even when the burn
    // series comfortably spans the window.
    func testFableWeekAlwaysUsesPercentRateEvenWithFullBurnCoverage() {
        let l = lane(.fableWeek, used: 10, windowLength: 604800, elapsed: 3600)
        let burn = BurnSeries(hourly: [HourBucket(start: now.addingTimeInterval(-3600), provider: .claude, tokens: 100_000, costUSD: 1)],
                              daily: [], unparsedLines: 0)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l]), snap(.spend, burn: burn)], now: now)
        let v = report.windows.first { $0.kind == .fableWeek }!
        XCTAssertEqual(v.projectionBasis, .percentRate)
    }

    // Fix round 1, finding #2: a duplicate provider in the snapshot list must
    // not trap Dictionary(uniqueKeysWithValues:) — keep the fresher one.
    func testDuplicateProviderSnapshotsKeepTheFresherOne() {
        let older = ProviderSnapshot(provider: .claude, fetchedAt: now.addingTimeInterval(-60), source: .api,
                                     lanes: [lane(.session, used: 10, windowLength: 18000, elapsed: 9000)])
        let newer = ProviderSnapshot(provider: .claude, fetchedAt: now, source: .api,
                                     lanes: [lane(.session, used: 99, windowLength: 18000, elapsed: 9000)])
        let report = PacingEngine.report(snapshots: [older, newer], now: now)
        XCTAssertEqual(report.windows.count, 1)
        XCTAssertEqual(report.windows.first?.percentUsed, 99)
    }

    // F1: the overage lane's "percentUsed" is a raw dollar figure, not a
    // pace percent — it must never read ahead, never get a headline slot,
    // and never drive advice.
    func testOverageLaneIsAlwaysOnPaceNeverHeadlineNoAdvice() {
        let overage = LaneUsage(kind: .overage, percentUsed: 150, resetDate: .distantFuture, windowLength: nil)
        let session = lane(.session, used: 30, windowLength: 18000, elapsed: 9000) // behind pace, not ahead
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [session, overage])], now: now)
        let overageWindow = report.windows.first { $0.kind == .overage }!
        XCTAssertEqual(overageWindow.status, .onPace)
        XCTAssertNil(overageWindow.projectedCapAt)
        XCTAssertEqual(overageWindow.verdict, "Extra usage: $150 used (unverified ÷100 of raw credits)")
        XCTAssertNotEqual(report.headline?.kind, .overage)
        XCTAssertNil(report.advice)
    }

    // S1: server severity forces the alarm even when local pace math is calm.
    func testExceededSeverityPromotesOnPaceToAhead() {
        let l = LaneUsage(kind: .session, percentUsed: 30, resetDate: now.addingTimeInterval(9000),
                          windowLength: 18000, severity: .exceeded)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        XCTAssertEqual(report.windows.first?.status, .ahead)
        XCTAssertEqual(report.windows.first?.severity, .exceeded)
    }

    // F8: two lanes of the same kind (e.g. a race between a live fetch and a
    // local fallback both reporting codexSession) must collapse to one row.
    func testDuplicateLaneKindsAreDeduped() {
        let a = lane(.codexSession, used: 40, windowLength: 18000, elapsed: 9000)
        let b = lane(.codexSession, used: 90, windowLength: 18000, elapsed: 9000)
        let report = PacingEngine.report(snapshots: [snap(.codex, lanes: [a, b])], now: now)
        XCTAssertEqual(report.windows.filter { $0.kind == .codexSession }.count, 1)
        XCTAssertEqual(report.windows.first { $0.kind == .codexSession }?.percentUsed, 40)
    }
}
