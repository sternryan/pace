import XCTest
@testable import PaceCore

final class SmithyProviderTests: XCTestCase {
    func data(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
    }
    func testServingWhenLaneReadyAndLeaseFree() throws {
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: try data("smithy-lease-free")), .serving)
    }
    func testLeasedAwayWhenLeaseHeldOrWedged() throws {
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: try data("smithy-lease-held")), .leasedAway)
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: Data(#"{"state":"wedged"}"#.utf8)), .leasedAway)
    }
    func testUnreachableWhenLaneNotServingOrMalformed() throws {
        let notServing = Data(#"{"data":[{"id":"local-heavy","smithy":{"serving_now":false,"candidates":[]}}]}"#.utf8)
        XCTAssertEqual(SmithyProvider.map(models: notServing, lease: try data("smithy-lease-free")), .unreachable)
        XCTAssertEqual(SmithyProvider.map(models: Data("garbage".utf8), lease: try data("smithy-lease-free")), .unreachable)
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: nil), .unreachable)
    }
    func testFetchAgainstDeadPortIsUnreachableNotServing() async {
        let p = SmithyProvider(schedulerModelsURL: URL(string: "http://127.0.0.1:1/v1/models")!,
                               leaseURL: URL(string: "http://127.0.0.1:1/lease")!)
        let s = await p.fetch(now: Date())
        XCTAssertEqual(s.laneState, .unreachable)
        XCTAssertNotNil(s.error)
    }
}
