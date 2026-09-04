import Foundation

/// Turns the vendored Claude/Codex session-log scanners into a `BurnSeries` — hourly and daily
/// token/cost buckets — for the pacing engine's burn-rate projection.
///
/// `claudeHome`/`codexHome` are home-style directories: the Claude scanner appends `.claude/projects`
/// itself (or honors `CLAUDE_CONFIG_DIR`/`XDG_CONFIG_HOME` from `environment` first), and the Codex
/// scanner appends `.codex/sessions` (or honors `CODEX_HOME`). Both default to the real home
/// directory so production callers see the user's actual logs; tests pass an isolated temp directory.
public final class SpendProvider: Provider, @unchecked Sendable {
    public let id: ProviderID = .spend

    private let claudeHome: URL
    private let codexHome: URL
    private let environment: EnvironmentReading
    /// Set only when the caller wants a fixed, network-free pricing snapshot (tests, and any other
    /// caller that has already resolved rates). Production leaves this nil and pulls a live snapshot
    /// from `pricingStore` instead, so real dollar costs track LiteLLM/models.dev without needing a
    /// bundled pricing catalog (PaceCore intentionally ships none — see Vendor/VENDORED.md).
    private let pricingOverride: ModelPricing?
    private let pricingStore: ModelPricingStore?

    /// Public entry point. `environment`/`pricing` (below) are internal-only knobs — `EnvironmentReading`
    /// and `ModelPricing` are internal vendored types, so a `public` init can't take them directly
    /// without making that vendored surface public too. Tests reach the internal init via
    /// `@testable import PaceCore`.
    public convenience init(
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheDirectory: URL = SnapshotCache.defaultDirectory().appendingPathComponent("log-scan-cache")
    ) {
        self.init(
            claudeHome: claudeHome, codexHome: codexHome, cacheDirectory: cacheDirectory,
            environment: ProcessEnvironmentReader(), pricing: nil
        )
    }

    /// Test/internal entry point: overrides the environment lookup (so a fixture's temp directory
    /// isn't shadowed by a real `CLAUDE_CONFIG_DIR`/`CODEX_HOME` in the ambient process environment)
    /// and/or injects a fixed, network-free `ModelPricing` snapshot in place of the live store.
    init(
        claudeHome: URL,
        codexHome: URL,
        cacheDirectory: URL = SnapshotCache.defaultDirectory().appendingPathComponent("log-scan-cache"),
        environment: EnvironmentReading,
        pricing: ModelPricing?
    ) {
        self.claudeHome = claudeHome
        self.codexHome = codexHome
        self.environment = environment
        self.pricingOverride = pricing
        self.pricingStore = pricing == nil ? ModelPricingStore(cacheDirectory: cacheDirectory) : nil
    }

    public func fetch(now: Date) async -> ProviderSnapshot {
        let pricing = await currentPricing()
        let claudeScanner = ClaudeLogUsageScanner(environment: environment, homeDirectory: { self.claudeHome })
        let codexScanner = CodexLogUsageScanner(environment: environment, homeDirectory: { self.codexHome })
        async let claudeScan = claudeScanner.scan(daysBack: 30, now: now, pricing: pricing)
        async let codexScan = codexScanner.scan(daysBack: 30, now: now, pricing: pricing)
        let (claude, codex) = await (claudeScan, codexScan)

        var hourly: [HourBucket] = []
        var daily: [DayBucket] = []
        var unparsedLines = 0
        for (scan, providerID) in [(claude, ProviderID.claude), (codex, ProviderID.codex)] {
            guard let scan else { continue }
            unparsedLines += scan.unparsedLineCount
            hourly += Self.hourly(from: scan, provider: providerID, now: now)
            daily += Self.daily(from: scan, provider: providerID)
        }

        let burn = BurnSeries(hourly: hourly, daily: daily, unparsedLines: unparsedLines)
        let error: ProviderError? = (claude == nil && codex == nil)
            ? .parseError("no session logs readable") : nil
        return ProviderSnapshot(provider: .spend, fetchedAt: now, source: .localFallback, lanes: [], burn: burn, error: error)
    }

    private func currentPricing() async -> ModelPricing {
        if let pricingOverride { return pricingOverride }
        return await pricingStore?.current() ?? .empty
    }

    /// Groups `scan.entries` (priced, timestamped usage lines) into hour buckets truncated to the
    /// top of the hour, covering the trailing 8 days so weekly pacing windows stay attributable
    /// (Task 2 ruling — `daily` below stays a separate 30-day window for the day tiles).
    static func hourly(from scan: LogUsageScan, provider: ProviderID, now: Date) -> [HourBucket] {
        let floor = now.addingTimeInterval(-8 * 86400)
        let grouped = Dictionary(grouping: scan.entries.filter { entry in
            guard let timestamp = entry.timestamp else { return false }
            return timestamp >= floor
        }) { entry -> Date in
            let hourStart = (entry.timestamp!.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            return Date(timeIntervalSince1970: hourStart)
        }
        return grouped.map { start, entries in
            HourBucket(
                start: start, provider: provider,
                tokens: entries.reduce(0) { $0 + $1.totalTokens },
                costUSD: entries.reduce(0.0) { $0 + ($1.costUSD ?? 0) }
            )
        }.sorted { $0.start < $1.start }
    }

    /// Groups the scan's own day-bucketed totals (`scan.series`, already local-calendar-keyed by the
    /// vendored accumulator) into `DayBucket`s — no need to re-derive days from `entries`.
    static func daily(from scan: LogUsageScan, provider: ProviderID) -> [DayBucket] {
        scan.series.daily.map { day in
            DayBucket(day: day.date, provider: provider, tokens: day.totalTokens, costUSD: day.costUSD ?? 0)
        }.sorted { $0.day < $1.day }
    }
}
