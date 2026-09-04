import XCTest
@testable import PaceCore

/// Minimal request stub so `SmithyProvider.fetch` can be exercised end-to-end
/// (not just `map`) against fixed bodies, without a live scheduler/lease host.
final class StubURLProtocol: URLProtocol {
    static var responses: [URL: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let data = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

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
    // F2: a held/wedged lease wins even when the scheduler reports serving_now: false —
    // the lease is the more authoritative "not available to you" signal.
    func testLeasedAwayWinsOverNotServingScheduler() throws {
        let notServing = Data(#"{"data":[{"id":"local-heavy","smithy":{"serving_now":false,"candidates":[]}}]}"#.utf8)
        XCTAssertEqual(SmithyProvider.map(models: notServing, lease: try data("smithy-lease-held")), .leasedAway)
        XCTAssertEqual(SmithyProvider.map(models: nil, lease: try data("smithy-lease-held")), .leasedAway)
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
    // F3: both GETs succeed but the lane isn't actually serving — this must
    // surface as an error, not silently read as an unreachable-with-no-reason.
    func testFetchWithBothGetsSucceedingButNotServingSetsError() async throws {
        let modelsURL = URL(string: "http://smithy-test.invalid/v1/models")!
        let leaseURL = URL(string: "http://smithy-test.invalid/lease")!
        StubURLProtocol.responses = [
            modelsURL: Data(#"{"data":[{"id":"local-heavy","smithy":{"serving_now":false,"candidates":[]}}]}"#.utf8),
            leaseURL: try data("smithy-lease-free"),
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let p = SmithyProvider(schedulerModelsURL: modelsURL, leaseURL: leaseURL, session: URLSession(configuration: config))
        let s = await p.fetch(now: Date())
        XCTAssertEqual(s.laneState, .unreachable)
        XCTAssertEqual(s.error?.message, "local-heavy not serving")
    }
}
