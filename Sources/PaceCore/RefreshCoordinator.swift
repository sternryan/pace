import Foundation

public final class RefreshCoordinator: @unchecked Sendable {
    private let providers: [any Provider]
    private let store: ReportStore
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var _latest: PaceReport?
    private var mainTask: Task<Void, Never>?
    private var smithyTask: Task<Void, Never>?
    private var lastSnapshots: [ProviderID: ProviderSnapshot] = [:]
    public var onReport: (@Sendable (PaceReport) -> Void)?

    public var latest: PaceReport? { lock.withLock { _latest } }

    public init(providers: [any Provider], store: ReportStore = ReportStore(directory: ReportStore.defaultDirectory()),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.providers = providers; self.store = store; self.clock = clock
        _latest = store.load()
    }

    public static func live() -> RefreshCoordinator {
        RefreshCoordinator(providers: [ClaudeProvider(), CodexProvider(), SmithyProvider(), SpendProvider()])
    }

    @discardableResult
    public func refresh(only: Set<ProviderID>? = nil) async -> PaceReport {
        let now = clock()
        let targets = providers.filter { only?.contains($0.id) ?? true }
        let fresh = await withTaskGroup(of: ProviderSnapshot.self) { group -> [ProviderSnapshot] in
            for p in targets { group.addTask { await p.fetch(now: now) } }
            var out: [ProviderSnapshot] = []; for await s in group { out.append(s) }; return out
        }
        let merged: [ProviderSnapshot] = lock.withLock {
            for s in fresh { lastSnapshots[s.provider] = s }
            return Array(lastSnapshots.values).sorted { $0.provider.rawValue < $1.provider.rawValue }
        }
        let report = PacingEngine.report(snapshots: merged, now: now)
        try? store.save(report)
        lock.withLock { _latest = report }
        onReport?(report)
        return report
    }

    public func start(interval: TimeInterval = 120, smithyInterval: TimeInterval = 60) {
        stop()
        mainTask = Task { [weak self] in
            while !Task.isCancelled { await self?.refresh(); try? await Task.sleep(nanoseconds: UInt64(interval * 1e9)) }
        }
        smithyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(smithyInterval * 1e9))
            while !Task.isCancelled { await self?.refresh(only: [.smithy]); try? await Task.sleep(nanoseconds: UInt64(smithyInterval * 1e9)) }
        }
    }

    public func stop() { mainTask?.cancel(); smithyTask?.cancel(); mainTask = nil; smithyTask = nil }

    deinit { stop() }
}
