import XCTest
@testable import PaceCore

private struct StubProvider: Provider {
    let id: ProviderID; let snapshot: ProviderSnapshot
    func fetch(now: Date) async -> ProviderSnapshot { snapshot }
}

/// Sleeps `sleepMillis` on its `sleepOnCall`-th invocation (1-based), returns
/// immediately every other call. Used to make one `refresh()` call slower
/// than another that races it, without needing two different coordinators.
private final class ConditionalSleepProvider: Provider, @unchecked Sendable {
    let id: ProviderID
    private let source: SnapshotSource
    private let lock = NSLock()
    private var callIndex = 0
    private let sleepOnCall: Int
    private let sleepMillis: UInt64

    init(id: ProviderID, source: SnapshotSource = .api, sleepOnCall: Int, sleepMillis: UInt64) {
        self.id = id; self.source = source; self.sleepOnCall = sleepOnCall; self.sleepMillis = sleepMillis
    }

    func fetch(now: Date) async -> ProviderSnapshot {
        let idx: Int = lock.withLock { callIndex += 1; return callIndex }
        if idx == sleepOnCall { try? await Task.sleep(nanoseconds: sleepMillis * 1_000_000) }
        return ProviderSnapshot(provider: id, fetchedAt: now, source: source, lanes: [])
    }
}

/// Sleeps every call. Used to hold a single in-flight refresh open long
/// enough to cancel it mid-flight.
private struct AlwaysSleepingProvider: Provider {
    let id: ProviderID
    let sleepMillis: UInt64
    func fetch(now: Date) async -> ProviderSnapshot {
        try? await Task.sleep(nanoseconds: sleepMillis * 1_000_000)
        return ProviderSnapshot(provider: id, fetchedAt: now, source: .api, lanes: [])
    }
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

    func testOlderRefreshDoesNotOverwriteNewer() async {
        let t1 = Date(timeIntervalSince1970: 1_800_000_000)
        let t2 = t1.addingTimeInterval(60)
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var calls = 0
            func next() -> Int { lock.withLock { calls += 1; return calls } }
        }
        let counter = Counter()
        let clock: @Sendable () -> Date = { counter.next() == 1 ? t1 : t2 }
        // The first refresh() call (A) sleeps 200ms before its snapshot
        // comes back; the second (B), which reads a later clock value,
        // returns immediately and should win even though A is still in
        // flight when B publishes.
        let provider = ConditionalSleepProvider(id: .claude, sleepOnCall: 1, sleepMillis: 200)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let c = RefreshCoordinator(providers: [provider], store: ReportStore(directory: dir), clock: clock)

        async let a: PaceReport = c.refresh()
        async let b: PaceReport = c.refresh()
        _ = await (a, b)

        XCTAssertEqual(c.latest?.generatedAt, t2)
        XCTAssertEqual(ReportStore(directory: dir).load()?.generatedAt, t2)
    }

    func testCancelledRefreshDoesNotPublishOrPersist() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let provider = AlwaysSleepingProvider(id: .claude, sleepMillis: 200)
        let c = RefreshCoordinator(providers: [provider], store: ReportStore(directory: dir), clock: { now })

        XCTAssertNil(c.latest)
        XCTAssertNil(ReportStore(directory: dir).load())

        let task = Task { await c.refresh() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        _ = await task.value

        XCTAssertNil(c.latest)
        XCTAssertNil(ReportStore(directory: dir).load())
    }
}
