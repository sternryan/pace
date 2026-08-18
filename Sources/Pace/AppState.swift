import Foundation
import AppKit
import Observation
import PaceCore

@Observable
@MainActor
final class AppState {
    private(set) var paceReadings: [PaceReading] = []
    private(set) var status: FetchStatus = .needsLogin
    private(set) var lastSuccessAt: Date?
    // 6 minutes — Global Constraints default. Persisted so it survives
    // relaunch instead of silently resetting every time (review finding).
    var refreshInterval: TimeInterval = 360 {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    private let fetcher: UsageFetcher
    private var timer: Timer?
    private var postLoginPollTask: Task<Void, Never>?

    init(fetcher: UsageFetcher? = nil) {
        self.fetcher = fetcher ?? UsageFetcher()
        self.fetcher.delegate = self
        let storedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        if storedInterval > 0 { refreshInterval = storedInterval }
        startTimer()
        refreshNow()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    func refreshNow() {
        Task { await fetcher.refresh() }
    }

    func presentLogin() {
        fetcher.presentLoginWindow()
        // Poll on a short cadence right after sign-in instead of waiting for
        // the next scheduled 6-min tick — the one moment a slow refresh
        // cadence actually hurts (review finding, cross-model).
        //
        // scrapeCurrentPage(), not refresh(): refresh() reloads the WKWebView,
        // which is the very page the user is signing into (C1). The loop runs
        // for as long as the window is up rather than a fixed 15 iterations, so
        // a slow sign-in can't finish just after the poll gave up and leave the
        // window stranded on screen (I5).
        postLoginPollTask?.cancel()
        postLoginPollTask = Task { @MainActor in
            while fetcher.isPresentingLogin {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { return }
                // The user may have closed the window while we slept.
                guard fetcher.isPresentingLogin else { return }
                if await fetcher.scrapeCurrentPage() {
                    fetcher.hideLoginWindow()
                    return
                }
            }
        }
    }

    func openClaudeUsagePage() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    func signOut() {
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

extension AppState: UsageFetcherDelegate {
    // Both AppState and UsageFetcher are @MainActor, so these write synchronously
    // in the caller's actor hop — no deferred Task, no window where a caller can
    // observe the pre-call state after the call returned (review finding I5).
    func usageFetcher(_ fetcher: UsageFetcher, didProduce lanes: [LaneUsage]) {
        paceReadings = lanes.map { PaceCalculator.reading(for: $0, now: Date()) }
        status = .ok
        lastSuccessAt = Date()
    }

    func usageFetcher(_ fetcher: UsageFetcher, didFailWith status: FetchStatus) {
        self.status = status
        // paceReadings intentionally left as the last-known values.
    }
}
