import Foundation
import AppKit
import Observation
import PaceCore

enum DataSourceMode: String {
    case api, browser
}

@Observable
@MainActor
final class AppState {
    private(set) var paceReadings: [PaceReading] = []
    private(set) var status: FetchStatus = .ok
    private(set) var lastSuccessAt: Date?
    private(set) var latestSnapshot: UsageSnapshot?
    private(set) var isShowingCachedData = false
    /// Upgrades browser → api on manual refresh if Claude Code credentials
    /// appear (the user installed Claude Code while Pace was running). Never
    /// downgrades — an expired token is a remediation message, not a mode
    /// switch.
    private(set) var mode: DataSourceMode

    // Mode-dependent default; a user-customized value still wins (see
    // migration note in init). API mode polls faster because a refresh is
    // one small JSON GET, not a WebView page load.
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    private let store = KeychainCredentialStore()
    private var source: UsageSource
    private var scrapeSource: ScrapeUsageSource? // non-nil only in browser mode
    private var timer: Timer?
    private var postLoginPollTask: Task<Void, Never>?
    private var isFetching = false // timer + manual refresh can overlap; scrape has its own guard, API needs this one

    init(source: UsageSource? = nil, mode: DataSourceMode? = nil) {
        let resolvedMode = mode ?? (store.hasAnyItem() ? .api : .browser)
        self.mode = resolvedMode

        if let source {
            self.source = source
            self.scrapeSource = source as? ScrapeUsageSource
        } else if resolvedMode == .api {
            self.source = ApiUsageSource(store: store)
            self.scrapeSource = nil
        } else {
            let scrape = ScrapeUsageSource()
            self.source = scrape
            self.scrapeSource = scrape
        }

        // v1 wrote refreshInterval unconditionally, so an existing 360 can't
        // be told apart from "user chose 360" — migrate ONCE (guarded by a
        // marker key), otherwise every launch would clobber a deliberately
        // chosen 360 back to the API-mode default.
        let defaults = UserDefaults.standard
        let modeDefault: TimeInterval = resolvedMode == .api ? 120 : 360
        let stored = defaults.double(forKey: "refreshInterval")
        if !defaults.bool(forKey: "didMigrateRefreshIntervalV2") {
            defaults.set(true, forKey: "didMigrateRefreshIntervalV2")
            self.refreshInterval = (stored > 0 && stored != 360) ? stored : modeDefault
            defaults.set(self.refreshInterval, forKey: "refreshInterval")
        } else {
            self.refreshInterval = stored > 0 ? stored : modeDefault
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

    /// Timer-driven. No mode re-evaluation — the spec re-evaluates mode on
    /// MANUAL refresh only, so browser-mode users don't pay a Keychain
    /// attribute scan on the MainActor every tick.
    private func scheduledRefresh() {
        Task { await performFetch() }
    }

    /// User-initiated. Re-evaluates mode first, upgrade-only (the user may
    /// have installed Claude Code while Pace was running). Never during an
    /// open sign-in — yanking the scraper mid-login would orphan the flow.
    func refreshNow() {
        if mode == .browser, scrapeSource?.fetcher.isPresentingLogin != true, store.hasAnyItem() {
            postLoginPollTask?.cancel()
            let retiring = scrapeSource
            mode = .api
            source = ApiUsageSource(store: store)
            scrapeSource = nil
            // The WKWebView session existed solely for Pace's scraping; the
            // API owns the data now, so drop the stored claude.ai cookies
            // rather than leaving them on disk with no UI to clear them.
            Task { await retiring?.fetcher.clearSession() }
        }
        Task { await performFetch() }
    }

    private func performFetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let result = await source.fetch() else { return } // skipped — leave state as-is
        switch result {
        case .success(let snapshot):
            applySnapshot(snapshot, fromCache: false)
        case .failure(let failure):
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
        if !fromCache { lastSuccessAt = snapshot.fetchedAt }
    }

    // MARK: browser-mode only

    func presentLogin() {
        guard let fetcher = scrapeSource?.fetcher else { return }
        fetcher.presentLoginWindow()
        // Poll on a short cadence right after sign-in instead of waiting for
        // the next scheduled tick — the one moment a slow cadence hurts.
        // scrapeCurrentPageOutcome() reads the page without navigating, so
        // watching for sign-in completion can't destroy the sign-in itself.
        postLoginPollTask?.cancel()
        postLoginPollTask = Task { @MainActor in
            while fetcher.isPresentingLogin {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { return }
                guard fetcher.isPresentingLogin else { return }
                if let outcome = await fetcher.scrapeCurrentPageOutcome() {
                    fetcher.hideLoginWindow()
                    if case .success(let lanes) = outcome {
                        applySnapshot(UsageSnapshot(lanes: lanes, extraUsage: nil, fetchedAt: Date()),
                                      fromCache: false)
                    }
                    return
                }
            }
        }
    }

    func openClaudeUsagePage() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    func signOut() {
        guard let fetcher = scrapeSource?.fetcher else { return }
        Task {
            await fetcher.clearSession()
            status = .needsLogin
        }
    }

    var lastSuccessLabel: String {
        guard let lastSuccessAt else { return "not yet updated" }
        let minutes = max(0, Int(Date().timeIntervalSince(lastSuccessAt)) / 60)
        return minutes == 0 ? "updated just now" : "updated \(minutes)m ago"
    }
}
