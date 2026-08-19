import Foundation
import PaceCore

/// Fallback source for claude.ai users without Claude Code: wraps the v1
/// WKWebView scraper. Only ever constructed in browser mode, so API-mode
/// users never pay the WebView's memory or lifecycle cost.
@MainActor
final class ScrapeUsageSource: UsageSource {
    let fetcher: UsageFetcher

    // Default is built inside the init: a MainActor-isolated default argument
    // expression can't be evaluated from a nonisolated context in Swift 5.9.
    init(fetcher: UsageFetcher? = nil) {
        self.fetcher = fetcher ?? UsageFetcher()
    }

    func fetch() async -> Result<UsageSnapshot, FetchStatus>? {
        switch await fetcher.fetchSnapshot() {
        case .success(let lanes):
            return .success(UsageSnapshot(lanes: lanes, extraUsage: nil, fetchedAt: Date()))
        case .failure(let status):
            return .failure(status)
        case .skipped:
            return nil // login window up or scrape in flight — leave state as-is
        }
    }
}
