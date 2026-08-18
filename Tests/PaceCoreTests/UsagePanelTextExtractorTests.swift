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
