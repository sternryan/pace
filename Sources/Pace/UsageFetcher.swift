import Foundation
import WebKit
import PaceCore

/// MainActor-isolated so a delegate call lands its state mutation before the
/// calling `refresh()`/`scrapeCurrentPage()` returns. A `nonisolated` protocol
/// forces conformers to hop through an unstructured Task, which made the
/// post-login poll read a stale `status` (review finding I5).
@MainActor
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
    /// True while the sign-in window is on screen. There is only one WKWebView,
    /// so navigating it during sign-in throws away whatever the user has typed
    /// (review finding C1) — every navigating path checks this first.
    private(set) var isPresentingLogin = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pace — Sign in to claude.ai"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.setIsVisible(false)
        super.init()
        window.delegate = self
    }

    func refresh() async {
        // Never reload the page the user is signing into.
        guard !isPresentingLogin else { return }
        // Guards against an overlapping fetch (e.g. the 6-min timer firing
        // again while a slow scrape is still mid-flight) tearing the
        // WKWebView's navigation state — see review finding on Task 9.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let url = URL(string: "https://claude.ai/new") else { return }
        webView.load(URLRequest(url: url))
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        await scrape()
    }

    /// Reads whatever the WKWebView is already showing, without navigating —
    /// the post-login poll's detection mechanism, so watching for sign-in
    /// completion can't destroy the sign-in itself.
    /// Returns true once the page is past claude.ai's sign-in gate, whether or
    /// not the panel then parsed, so the caller knows sign-in finished.
    @discardableResult
    func scrapeCurrentPage() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        return await scrape()
    }

    @discardableResult
    private func scrape() async -> Bool {
        switch await clickThroughToUsagePanel() {
        case .reachedUsagePanel:
            break
        case .notSignedIn:
            delegate?.usageFetcher(self, didFailWith: .needsLogin)
            return false
        case .navigationBroke(let step):
            delegate?.usageFetcher(self, didFailWith: .navigationFailed("Couldn't find the \(step) button — claude.ai's UI may have changed"))
            return true
        }

        guard let panelText = await readUsagePanelText(), !panelText.isEmpty else {
            delegate?.usageFetcher(self, didFailWith: .parseError("Usage panel text not found"))
            return true
        }

        guard let lanes = UsagePanelTextExtractor.extractLanes(
            from: panelText, now: Date(), sessionWindowLength: SessionWindow.confirmedLength
        ) else {
            delegate?.usageFetcher(self, didFailWith: .parseError("Could not parse usage panel text"))
            return true
        }

        delegate?.usageFetcher(self, didProduce: lanes)
        return true
    }

    func presentLoginWindow() {
        isPresentingLogin = true
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        // LSUIElement apps aren't brought forward by makeKeyAndOrderFront alone,
        // so without this the sign-in window opens behind whatever the user is in.
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLoginWindow() {
        isPresentingLogin = false
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
        guard let body = try? await webView.evaluateJavaScript("document.body.innerText") as? String else { return nil }
        return Self.slicedToUsagePanel(body)
    }

    /// `document.body.innerText` covers the whole page including the left
    /// conversation sidebar, and the extractor takes the first line-anchored
    /// match of each lane anchor — so a chat titled exactly "Fable" would win
    /// over the real lane header. Slice from the panel's own heading, which is
    /// how Task 6's research captured this text in the first place. Stable text
    /// anchor, same category as the lane anchors, not a churn-prone class name.
    static func slicedToUsagePanel(_ bodyText: String) -> String {
        guard let anchor = bodyText.range(of: "Plan usage limits") else { return bodyText }
        return String(bodyText[anchor.lowerBound...])
    }
}

extension UsageFetcher: NSWindowDelegate {
    /// The user can close the sign-in window themselves now that it has a close
    /// button — clear the flag so scheduled refreshes resume.
    func windowWillClose(_ notification: Notification) {
        isPresentingLogin = false
    }
}
