import XCTest
@testable import PaceCore

final class LoopbackServerTests: XCTestCase {
    func testServesReportAnd404sElsewhere() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = PaceReport(generatedAt: now, headline: nil, advice: nil, windows: [], laneState: .serving, burn: nil, providers: [], stale: false)
        let server = LoopbackServer(port: 0, report: { report }, refresh: { report })   // port 0 = ephemeral, exposes .boundPort
        try server.start()
        defer { server.stop() }
        let port = try await server.boundPort()
        let (data, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/report")!)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(PaceReport.self, from: data), report)
        let (_, r404) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/nope")!)
        XCTAssertEqual((r404 as? HTTPURLResponse)?.statusCode, 404)
    }
}
