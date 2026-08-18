import XCTest
@testable import PaceCore

final class CoreTypesTests: XCTestCase {
    func testLaneKindDisplayNames() {
        XCTAssertEqual(LaneKind.session.displayName, "Current session")
        XCTAssertEqual(LaneKind.allModelsWeek.displayName, "All models · week")
        XCTAssertEqual(LaneKind.fableWeek.displayName, "Fable · week")
    }

    func testLaneKindIsHashable() {
        let set: Set<LaneKind> = [.session, .session, .fableWeek]
        XCTAssertEqual(set.count, 2)
    }

    func testLaneUsageEquality() {
        let date = Date(timeIntervalSince1970: 0)
        let a = LaneUsage(kind: .session, percentUsed: 21, resetDate: date, windowLength: nil)
        let b = LaneUsage(kind: .session, percentUsed: 21, resetDate: date, windowLength: nil)
        XCTAssertEqual(a, b)
    }

    func testFetchStatusEquality() {
        XCTAssertEqual(FetchStatus.parseError("x"), FetchStatus.parseError("x"))
        XCTAssertNotEqual(FetchStatus.parseError("x"), FetchStatus.parseError("y"))
        XCTAssertNotEqual(FetchStatus.ok, FetchStatus.needsLogin)
        XCTAssertNotEqual(FetchStatus.needsLogin, FetchStatus.navigationFailed("x"))
    }
}
