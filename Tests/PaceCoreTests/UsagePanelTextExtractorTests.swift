import XCTest
@testable import PaceCore

final class UsagePanelTextExtractorTests: XCTestCase {
    let sample = """
    Plan usage limits Max (5x)

    Current session
    Resets in 3 hr 53 min
    21% used

    Weekly limits
    Fable 5 is still included with your Max plan.

    All models
    Resets Sat 2:00 PM
    16% used

    Fable
    Resets Sat 2:00 PM
    21% used
    """

    func testExtractsAllThreeLanes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!

        let lanes = UsagePanelTextExtractor.extractLanes(from: sample, now: now, sessionWindowLength: nil)

        XCTAssertNotNil(lanes)
        guard let lanes else { return }
        XCTAssertEqual(lanes.count, 3)

        let session = lanes.first { $0.kind == .session }
        XCTAssertEqual(session?.percentUsed, 21)
        XCTAssertNil(session?.windowLength)

        let allModels = lanes.first { $0.kind == .allModelsWeek }
        XCTAssertEqual(allModels?.percentUsed, 16)
        XCTAssertEqual(allModels?.windowLength, 7 * 24 * 3600)

        let fable = lanes.first { $0.kind == .fableWeek }
        XCTAssertEqual(fable?.percentUsed, 21)
    }

    /// Verbatim capture from claude.ai's live Usage panel, recorded in
    /// docs/superpowers/research/live-usage-page-notes.md. The only real bytes
    /// this project has from the page it depends on — the design-time fixture
    /// above is a reconstruction and is missing the banner/footer lines.
    func testExtractsFromRealCapturedPanelText() {
        let realCapture = """
        Plan usage limits
        Max (5x)
        Current session
        Resets in 2 hr 5 min
        65% used
        Weekly limits

        Fable 5 is still included with your Max plan.
        If you see a prompt to set up usage credits for it, restart Claude Code.
        Learn more about usage limits
        All models
        Resets Sat 2:00 PM
        20% used
        Fable
        Resets Sat 2:00 PM
        25% used
        Last updated: less than a minute ago
        """
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!

        // 5 * 3600 is what production passes (SessionWindow.confirmedLength).
        let lanes = UsagePanelTextExtractor.extractLanes(from: realCapture, now: now, sessionWindowLength: 5 * 3600)

        XCTAssertNotNil(lanes)
        guard let lanes else { return }
        XCTAssertEqual(lanes.count, 3)

        let session = lanes.first { $0.kind == .session }
        XCTAssertEqual(session?.percentUsed, 65)
        XCTAssertEqual(session?.windowLength, 5 * 3600)
        XCTAssertEqual(session?.resetDate, now.addingTimeInterval(2 * 3600 + 5 * 60))

        XCTAssertEqual(lanes.first { $0.kind == .allModelsWeek }?.percentUsed, 20)
        XCTAssertEqual(lanes.first { $0.kind == .fableWeek }?.percentUsed, 25)
    }

    func testReturnsNilWhenAnchorMissing() {
        let broken = "Current session\nResets in 3 hr 53 min\n21% used"
        XCTAssertNil(UsagePanelTextExtractor.extractLanes(from: broken, now: Date(), sessionWindowLength: nil))
    }

    func testBoundaryPercentValues() {
        let boundarySample = """
        Current session
        Resets in 3 hr 53 min
        0% used

        All models
        Resets Sat 2:00 PM
        100% used

        Fable
        Resets Sat 2:00 PM
        50% used
        """
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!

        let lanes = UsagePanelTextExtractor.extractLanes(from: boundarySample, now: now, sessionWindowLength: nil)

        XCTAssertEqual(lanes?.first { $0.kind == .session }?.percentUsed, 0)
        XCTAssertEqual(lanes?.first { $0.kind == .allModelsWeek }?.percentUsed, 100)
    }
}
