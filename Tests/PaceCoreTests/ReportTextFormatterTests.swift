import XCTest
@testable import PaceCore

final class ReportTextFormatterTests: XCTestCase {
    func testRendersHeadlineAdviceAndWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let v = WindowVerdict(kind: .fableWeek, provider: .claude, percentUsed: 71, percentElapsed: 54, resetsAt: now.addingTimeInterval(86400),
                              status: .ahead, projectedCapAt: now.addingTimeInterval(3600), resetsFirst: false, projectionBasis: .burnRate,
                              source: .api, fetchedAt: now, verdict: "Fable · week: 71% used, 54% elapsed, caps 14:10 at this rate (resets Fri 09:00)")
        let r = PaceReport(generatedAt: now, headline: v, advice: "move bulk/mechanical work to smithy (hearth:8085 local-heavy)",
                           windows: [v], laneState: .serving, burn: nil,
                           providers: [ProviderStatus(provider: .claude, source: .api, fetchedAt: now, error: nil)], stale: false)
        let text = ReportTextFormatter.render(r, now: now)
        XCTAssertTrue(text.contains("HEADLINE  Fable · week: 71% used"))
        XCTAssertTrue(text.contains("ADVICE    move bulk/mechanical work to smithy"))
        XCTAssertTrue(text.contains("smithy    serving"))
        XCTAssertTrue(text.contains("claude    api"))
    }
}
