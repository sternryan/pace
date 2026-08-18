import Foundation
import WebKit
import PaceCore

protocol UsageFetcherDelegate: AnyObject {
    func usageFetcher(_ fetcher: UsageFetcher, didProduce lanes: [LaneUsage])
    func usageFetcher(_ fetcher: UsageFetcher, didFailWith status: FetchStatus)
}

enum SessionWindow {
    /// Confirmed via Anthropic's support docs (Task 6 research):
    /// https://support.claude.com/en/articles/9797557-usage-limit-best-practices
    /// "...how much of your plan's five-hour session limit you've used thus far"
    /// Applies to Pro/Max/Team/seat-based Enterprise plans.
    static let confirmedLength: TimeInterval? = 5 * 3600
}

@MainActor
final class UsageFetcher: NSObject {
    weak var delegate: UsageFetcherDelegate?

    private let webView: WKWebView
    private let window: NSWindow
    private var isRefreshing = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Pace — Sign in to claude.ai"
        window.contentView = webView
        window.setIsVisible(false)
        super.init()
    }

    func refresh() async {
        // Guards against an overlapping fetch (e.g. the 6-min timer firing
        // again while a slow scrape is still mid-flight) tearing the
        // WKWebView's navigation state — see review finding on Task 9.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let url = URL(string: "https://claude.ai/new") else { return }
        webView.load(URLRequest(url: url))
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        switch await clickThroughToUsagePanel() {
        case .reachedUsagePanel:
            break
        case .notSignedIn:
            delegate?.usageFetcher(self, didFailWith: .needsLogin)
            return
        case .navigationBroke(let step):
            delegate?.usageFetcher(self, didFailWith: .navigationFailed("Couldn't find the \(step) button — claude.ai's UI may have changed"))
            return
        }

        guard let panelText = await readUsagePanelText(), !panelText.isEmpty else {
            delegate?.usageFetcher(self, didFailWith: .parseError("Usage panel text not found"))
            return
        }

        guard let lanes = UsagePanelTextExtractor.extractLanes(
            from: panelText, now: Date(), sessionWindowLength: SessionWindow.confirmedLength
        ) else {
            delegate?.usageFetcher(self, didFailWith: .parseError("Could not parse usage panel text"))
            return
        }

        delegate?.usageFetcher(self, didProduce: lanes)
    }

    func presentLoginWindow() {
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
    }

    func hideLoginWindow() {
        window.setIsVisible(false)
    }

    func clearSession() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await webView.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    enum NavigationResult {
        case reachedUsagePanel
        /// The avatar/profile button itself couldn't be found or clicked —
        /// that button only renders when signed in, so its absence is the
        /// most likely explanation. Maps to FetchStatus.needsLogin.
        case notSignedIn
        /// The avatar step succeeded (so you ARE signed in) but a later step
        /// broke — maps to FetchStatus.navigationFailed, never needsLogin,
        /// since the "sign in" remediation would be wrong here.
        case navigationBroke(step: String)
    }

    /// Clicks an element matching `selector` via `.click()` in JS. Returns
    /// whether the element was found and clicked.
    private func clickElement(matching selector: String) async -> Bool {
        let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
          const el = document.querySelector('\(escaped)');
          if (el) { el.click(); return true; }
          return false;
        })();
        """
        return (try? await webView.evaluateJavaScript(script) as? Bool) ?? false
    }

    /// Selectors confirmed live against claude.ai's DOM in Task 6's research
    /// (docs/superpowers/research/live-usage-page-notes.md), preferred over
    /// text matching since they don't depend on the signed-in user's display
    /// name or on Settings/Usage label text staying stable.
    private func clickThroughToUsagePanel() async -> NavigationResult {
        let avatarOpened = await clickElement(matching: "[data-testid=\"user-menu-button\"]")
        guard avatarOpened else { return .notSignedIn }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let settingsOpened = await clickElement(matching: "[data-testid=\"user-menu-settings\"]")
        guard settingsOpened else { return .navigationBroke(step: "Settings") }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let usageOpened = await clickElement(matching: "[data-testid=\"usage-settings\"] button")
        try? await Task.sleep(nanoseconds: 500_000_000)
        return usageOpened ? .reachedUsagePanel : .navigationBroke(step: "Usage")
    }

    private func readUsagePanelText() async -> String? {
        try? await webView.evaluateJavaScript("document.body.innerText") as? String
    }
}
