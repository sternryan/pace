import XCTest
@testable import PaceCore

final class BurnSeriesTests: XCTestCase {
    // Fix round 1, finding #3: `rate` used to look only at whichever bucket's
    // wall-clock hour contained `now`, so at 10:05 the trailing hour
    // 09:05–10:05 saw just 5 minutes of the 10:00 bucket. Pro-rate by the
    // actual overlap instead.
    func testRateProRatesBucketsAcrossHourBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // treat as 10:05
        let nineAM = HourBucket(start: now.addingTimeInterval(-3900), provider: .claude, tokens: 3600, costUSD: 0)  // 09:00
        let tenAM = HourBucket(start: now.addingTimeInterval(-300), provider: .claude, tokens: 3600, costUSD: 0)    // 10:00
        let series = BurnSeries(hourly: [nineAM, tenAM], daily: [], unparsedLines: 0)

        let rate = series.rate(for: .claude, now: now, window: 3600)

        // 3300s of the 09:00 bucket (3300 tokens) + 300s of the 10:00 bucket
        // (300 tokens) = 3600 tokens over a 3600s window = 1.0 tokens/s.
        XCTAssertEqual(rate, 1.0, accuracy: 0.01)
    }

    func testTokensUsesTheSameOverlapWeightingAsRate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nineAM = HourBucket(start: now.addingTimeInterval(-3900), provider: .claude, tokens: 3600, costUSD: 0)
        let tenAM = HourBucket(start: now.addingTimeInterval(-300), provider: .claude, tokens: 3600, costUSD: 0)
        let series = BurnSeries(hourly: [nineAM, tenAM], daily: [], unparsedLines: 0)

        let tokens = series.tokens(for: .claude, from: now.addingTimeInterval(-3600), to: now)

        XCTAssertEqual(tokens, 3600)
    }

    func testTokensAndRateIgnoreOtherProviders() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bucket = HourBucket(start: now.addingTimeInterval(-1800), provider: .codex, tokens: 5000, costUSD: 0)
        let series = BurnSeries(hourly: [bucket], daily: [], unparsedLines: 0)

        XCTAssertEqual(series.tokens(for: .claude, from: now.addingTimeInterval(-3600), to: now), 0)
        XCTAssertEqual(series.rate(for: .claude, now: now, window: 3600), 0)
    }
}
