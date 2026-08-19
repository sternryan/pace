import XCTest
@testable import PaceCore

final class SnapshotCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pace-cache-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveThenLoadRoundTrips() {
        let cache = SnapshotCache(directory: directory)
        let snapshot = UsageSnapshot(
            lanes: [LaneUsage(kind: .session, percentUsed: 40,
                              resetDate: Date(timeIntervalSince1970: 1_787_204_000),
                              windowLength: 5 * 3600)],
            extraUsage: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_787_200_000))
        cache.save(snapshot)
        XCTAssertEqual(cache.load(), snapshot)
    }

    func testLoadWithNoFileReturnsNil() {
        XCTAssertNil(SnapshotCache(directory: directory).load())
    }

    func testCorruptFileReturnsNilRatherThanCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("last-usage.json"))
        XCTAssertNil(SnapshotCache(directory: directory).load())
    }
}
