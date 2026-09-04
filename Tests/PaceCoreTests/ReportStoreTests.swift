import XCTest
@testable import PaceCore

final class ReportStoreTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func report(at t: Date) -> PaceReport {
        PaceReport(generatedAt: t, headline: nil, advice: nil, windows: [], laneState: nil, burn: nil, providers: [], stale: false)
    }

    func testSaveIsAtomicAndReloads() throws {
        let dir = tmp(); let store = ReportStore(directory: dir)
        let r = report(at: Date(timeIntervalSince1970: 1_000))
        try store.save(r)
        XCTAssertEqual(store.load(), r)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("report.json.tmp").path))
    }

    func testLoadWithAgeMarksStaleAfterTenMinutes() throws {
        let store = ReportStore(directory: tmp())
        let t0 = Date(timeIntervalSince1970: 1_000)
        try store.save(report(at: t0))
        XCTAssertEqual(store.loadWithAge(now: t0.addingTimeInterval(599))?.isStale, false)
        XCTAssertEqual(store.loadWithAge(now: t0.addingTimeInterval(601))?.isStale, true)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(ReportStore(directory: tmp()).load())
    }

    func testSavedFileDoesNotEscapeSlashes() throws {
        let dir = tmp(); let store = ReportStore(directory: dir)
        let t = Date(timeIntervalSince1970: 1_000)
        let r = PaceReport(generatedAt: t, headline: nil, advice: "move bulk/mechanical work to smithy (hearth:8085 local-heavy)",
                           windows: [], laneState: nil, burn: nil, providers: [], stale: false)
        try store.save(r)
        let text = try String(contentsOf: dir.appendingPathComponent("report.json"), encoding: .utf8)
        XCTAssertTrue(text.contains("move bulk/mechanical work to smithy (hearth:8085 local-heavy)"))
    }
}
