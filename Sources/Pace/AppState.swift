import Foundation
import os
import AppKit
import Observation
import PaceCore

enum DataSourceMode: String {
    case api
}

@Observable
@MainActor
final class AppState {
    private(set) var paceReadings: [PaceReading] = []
    private(set) var status: FetchStatus = .ok
    private(set) var lastSuccessAt: Date?
    private(set) var latestSnapshot: UsageSnapshot?
    private(set) var isShowingCachedData = false
    private(set) var mode: DataSourceMode = .api

    // API mode polls faster because a refresh is one small JSON GET, not a
    // WebView page load.
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    private let store = KeychainCredentialStore()
    private let cache = SnapshotCache(directory: SnapshotCache.defaultDirectory())
    private var source: ClaudeUsageFetching
    private var timer: Timer?
    private var isFetching = false // timer + manual refresh can overlap
    static let log = Logger(subsystem: "com.sternryan.pace", category: "fetch")

    private var notificationGovernor = NotificationGovernor()
    private let notifier = PaceNotifier()

    init(source: ClaudeUsageFetching? = nil) {
        self.source = source ?? ApiUsageSource(store: store)

        // v1 wrote refreshInterval unconditionally, so an existing 360 can't
        // be told apart from "user chose 360" — migrate ONCE (guarded by a
        // marker key), otherwise every launch would clobber a deliberately
        // chosen 360 back to the API-mode default.
        let defaults = UserDefaults.standard
        let modeDefault: TimeInterval = 120
        let stored = defaults.double(forKey: "refreshInterval")
        if !defaults.bool(forKey: "didMigrateRefreshIntervalV2") {
            defaults.set(true, forKey: "didMigrateRefreshIntervalV2")
            self.refreshInterval = (stored > 0 && stored != 360) ? stored : modeDefault
            defaults.set(self.refreshInterval, forKey: "refreshInterval")
        } else {
            self.refreshInterval = stored > 0 ? stored : modeDefault
        }

        // Render last-good numbers immediately on launch; the first live
        // fetch replaces them. fromCache: true — cache-loaded data must never
        // notify or be re-written to the cache it just came from,
        // regardless of how fresh it is. The UI labels it with its age.
        if let cached = cache.load() {
            applySnapshot(cached, fromCache: true)
        }

        startTimer()
        refreshNow()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduledRefresh() }
        }
    }

    private func scheduledRefresh() {
        Task { await performFetch() }
    }

    /// User-initiated refresh.
    func refreshNow() {
        Task { await performFetch() }
    }

    private func performFetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let result = await source.fetch() else { return } // skipped — leave state as-is
        switch result {
        case .success(let snapshot):
            Self.log.info("fetch ok: \(snapshot.lanes.count, privacy: .public) lane(s)")
            applySnapshot(snapshot, fromCache: false)
        case .failure(let failure):
            // Failures are otherwise invisible: the UI keeps rendering the
            // last-good numbers, so a silently-stuck fetch loop looks healthy.
            // Log the status (never the token) so `log show --predicate
            // 'subsystem == "com.sternryan.pace"'` can diagnose it.
            Self.log.error("fetch failed: \(String(describing: failure), privacy: .public)")
            status = failure
            // Last-known readings stay rendered; mark them as cached so the
            // dropdown can label their age honestly.
            if latestSnapshot != nil { isShowingCachedData = true }
        }
    }

    /// fromCache is provenance: cache-loaded data must never re-fire
    /// notifications (a relaunch would re-announce an alarm the user already
    /// saw) and must never be written back to the cache it came from. Age is
    /// separate — the UI labels any cached data with its fetchedAt age.
    func applySnapshot(_ snapshot: UsageSnapshot, fromCache: Bool) {
        latestSnapshot = snapshot
        paceReadings = snapshot.lanes.map { PaceCalculator.reading(for: $0, now: Date()) }
        status = .ok
        isShowingCachedData = fromCache
        if !fromCache {
            lastSuccessAt = snapshot.fetchedAt
            cache.save(snapshot)
        }
        // Cached data must never notify — a relaunch would re-announce an
        // alarm the user already saw. fromCache is the provenance flag;
        // `stale` is only about age.
        if !fromCache {
            let alerts = notificationGovernor.alertsFor(readings: paceReadings)
            if !alerts.isEmpty {
                Task { @MainActor in
                    for alert in alerts { await notifier.post(alert) }
                }
            }
        }
    }

    func openClaudeUsagePage() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    var lastSuccessLabel: String {
        guard let lastSuccessAt else { return "not yet updated" }
        let minutes = max(0, Int(Date().timeIntervalSince(lastSuccessAt)) / 60)
        return minutes == 0 ? "updated just now" : "updated \(minutes)m ago"
    }
}
