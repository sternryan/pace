import SwiftUI
import PaceCore

@Observable
@MainActor
final class AppState {
    private(set) var report: PaceReport?
    private(set) var lastRefreshAt: Date?
    /// Set when the loopback server failed to bind (e.g. port 6737 already
    /// taken by another instance) — the app still runs and polls providers,
    /// but the CLI/statusline lose the in-process refresh path. F6: this
    /// used to be swallowed by `try?` and never surfaced anywhere.
    private(set) var serverError: String?

    var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            coordinator.start(interval: refreshInterval)
        }
    }

    /// nil = headline (auto)
    var pinnedKind: LaneKind? {
        didSet { UserDefaults.standard.set(pinnedKind?.rawValue, forKey: "pinnedKind") }
    }

    let coordinator: RefreshCoordinator
    private let server: LoopbackServer

    init(coordinator: RefreshCoordinator? = nil) {
        let c = coordinator ?? RefreshCoordinator.live()
        self.coordinator = c

        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        refreshInterval = stored > 0 ? stored : 120
        pinnedKind = UserDefaults.standard.string(forKey: "pinnedKind").flatMap(LaneKind.init(rawValue:))

        report = c.latest

        server = LoopbackServer(
            report: { [weak c] in c?.latest },
            refresh: { [weak c] in await c?.refresh() }
        )

        c.onReport = { [weak self] r in
            Task { @MainActor in
                self?.report = r
                self?.lastRefreshAt = r.generatedAt
            }
        }

        do {
            try server.start()
        } catch {
            serverError = "\(error)"
        }
        c.start(interval: refreshInterval)
    }

    func refreshNow() {
        Task { await coordinator.refresh() }
    }

    /// What the menubar pin shows.
    var pinned: WindowVerdict? {
        guard let r = report else { return nil }
        if let k = pinnedKind, let w = r.windows.first(where: { $0.kind == k }) { return w }
        return r.headline
    }

    var isStale: Bool {
        guard let r = report else { return true }
        return r.stale || Date().timeIntervalSince(r.generatedAt) > ReportStore.staleAfter
    }
}
