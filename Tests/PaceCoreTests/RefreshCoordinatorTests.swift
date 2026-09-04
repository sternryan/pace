import XCTest
@testable import PaceCore

private struct StubProvider: Provider {
    let id: ProviderID; let snapshot: ProviderSnapshot
    func fetch(now: Date) async -> ProviderSnapshot { snapshot }
}

final class RefreshCoordinatorTests: XCTestCase {
    func testRefreshRunsAllProvidersAndPersists() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // resetDate/windowLength chosen (50% elapsed, like the brief's 9000/18000)
        // so PaceCalculator's projected-cap arithmetic (100 * elapsed / percentUsed)
        // lands on a whole second: with the brief's original 9000/18000 it produces
        // a fractional-second Date, and ReportStore's whole-second ISO-8601 round
        // trip then breaks `ReportStore.load() == r` on a value neither this test
        // nor RefreshCoordinator controls. See task-10-report.md for detail.
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: now.addingTimeInterval(7000), windowLength: 14000)
        let providers: [any Provider] = [
            StubProvider(id: .claude, snapshot: ProviderSnapshot(provider: .claude, fetchedAt: now, source: .api, lanes: [lane])),
            StubProvider(id: .smithy, snapshot: ProviderSnapshot(provider: .smithy, fetchedAt: now, source: .api, lanes: [], laneState: .serving))
        ]
        let c = RefreshCoordinator(providers: providers, store: ReportStore(directory: dir), clock: { now })
        let r = await c.refresh()
        XCTAssertEqual(r.headline?.kind, .session)
        XCTAssertEqual(r.advice, "move bulk/mechanical work to smithy (hearth:8085 local-heavy)")
        XCTAssertEqual(ReportStore(directory: dir).load(), r)
        XCTAssertEqual(c.latest, r)
    }

    func testOneFailingProviderDoesNotBlankOthers() async {
        let now = Date()
        let lane = LaneUsage(kind: .codexSession, percentUsed: 5, resetDate: now.addingTimeInterval(9000), windowLength: 18000)
        let providers: [any Provider] = [
            StubProvider(id: .claude, snapshot: ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: [], error: .transient("500"))),
            StubProvider(id: .codex, snapshot: ProviderSnapshot(provider: .codex, fetchedAt: now, source: .api, lanes: [lane]))
        ]
        let c = RefreshCoordinator(providers: providers, store: ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), clock: { now })
        let r = await c.refresh()
        XCTAssertEqual(r.windows.map(\.kind), [.codexSession])
        XCTAssertTrue(r.stale)
    }
}
