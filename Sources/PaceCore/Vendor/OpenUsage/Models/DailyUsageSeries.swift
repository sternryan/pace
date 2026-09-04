// Vendored from robinebers/openusage@8321283f Sources/OpenUsage/Models/DailyUsageSeries.swift (MIT).
// Local edits listed in Sources/PaceCore/Vendor/VENDORED.md
import Foundation

/// A provider-neutral per-day token/cost series — the shared carrier every spend-tracking provider
/// funnels through `SpendTileMapper` (the Today / Yesterday / Last 30 Days tiles and the Usage Trend
/// chart).
///
/// Sources build it from very different inputs and hand `SpendTileMapper` the same shape so the tiles
/// render identically regardless of origin: Claude/Codex/Grok from their native log scanners, Cursor
/// from its usage CSV export.
///
/// These are internal types with no serialization impact: the local HTTP API serializes `MetricLine`,
/// not these.
struct DailyUsageEntry: Hashable, Sendable, Codable {
    var date: String
    var totalTokens: Int
    var costUSD: Double?
}

struct DailyUsageSeries: Hashable, Sendable, Codable {
    var daily: [DailyUsageEntry]
}

/// The calendar window shared by local scanners, combined iCloud history, and the usage trend.
/// `previousDays` excludes today, so 30 means today plus the previous 30 calendar days.
enum UsageHistoryWindow {
    static let previousDays = 30

    static func dayKeys(through now: Date, calendar: Calendar = .current) -> Set<String> {
        let today = calendar.startOfDay(for: now)
        return Set((0...previousDays).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
                .map { DailyUsageAccumulator.dayKey(from: $0, calendar: calendar) }
        })
    }
}

/// Token/cost totals for one model before a period collapses it into a spend row. Costs stay unrounded
/// here; `SpendTileMapper` snaps them to cents once for the displayed Today / Yesterday / Last 30 Days
/// breakdown, matching the spend-row totals.
///
/// `variants` carries the raw slugs folded into this entry when a provider groups by base model —
/// Cursor's thinking-effort/fast CSV slugs (`claude-opus-4-8-thinking-max` under `claude-opus-4-8`) —
/// and the models rolled into the `Other` row. Nil when the entry is exactly one raw model (the log
/// scanners' entries), so the hover panel knows there is no finer breakdown to offer.
struct ModelUsageEntry: Hashable, Sendable, Codable {
    static let unattributedModelName = "Unattributed"
    static let otherModelName = "Other"

    var model: String
    var totalTokens: Int
    var costUSD: Double?
    var variants: [ModelUsageVariant]? = nil
    /// Local edit (pace Task 8, not upstream): the priced line's own timestamp, set only on the
    /// per-message `LogUsageScan.entries` list the native scanners build for hourly burn-rate
    /// buckets. Nil on every day-bucketed `ModelUsageEntry` (the `DailyModelUsageEntry.models`
    /// breakdown), which has no single timestamp to carry.
    var timestamp: Date? = nil
}

/// One raw slug inside a grouped `ModelUsageEntry` — the "per thinking effort" line of the hover
/// panel's row tooltip.
struct ModelUsageVariant: Hashable, Sendable, Codable {
    var model: String
    var totalTokens: Int
    var costUSD: Double?
}

struct DailyModelUsageEntry: Hashable, Sendable, Codable {
    var date: String
    var models: [ModelUsageEntry]
}

struct ModelUsageSeries: Hashable, Sendable, Codable {
    var daily: [DailyModelUsageEntry]
}

/// The presentation-free daily history retained on a provider snapshot. The same normalized values
/// feed the local spend rows and, when explicitly classified as machine-local by the provider's
/// descriptor, the private iCloud sync file.
struct ProviderUsageHistory: Hashable, Sendable, Codable {
    var series: DailyUsageSeries
    var modelUsage: ModelUsageSeries?
    var unknownModelsByDay: [String: Set<String>]
    /// Optional for compatibility with histories saved before fallback estimation existed.
    var fallbackPricingModelsByDay: [String: Set<String>]?

    init(
        series: DailyUsageSeries,
        modelUsage: ModelUsageSeries? = nil,
        unknownModelsByDay: [String: Set<String>] = [:],
        fallbackPricingModelsByDay: [String: Set<String>]? = nil
    ) {
        self.series = series
        self.modelUsage = modelUsage
        self.unknownModelsByDay = unknownModelsByDay
        self.fallbackPricingModelsByDay = fallbackPricingModelsByDay
    }
}

/// A period-scoped, UI-ready breakdown attached to the same `.values` line as the spend row it explains.
/// The header total mirrors that row's values; individual model costs are rounded at this display boundary.
struct ModelUsageBreakdown: Hashable, Sendable, Codable {
    var totalTokens: Int
    var totalCostUSD: Double?
    var models: [ModelUsageEntry]
    var sourceNote: String
}

/// Daily token/cost series plus the per-day models the pricing sources couldn't price — the inputs
/// `SpendTileMapper.appendTokenUsage` needs to render the spend tiles with unknown-model warnings.
/// Shared result shape of the native log scanners (Claude, Codex).
struct LogUsageScan: Sendable {
    var series: DailyUsageSeries
    var modelUsage: ModelUsageSeries?
    /// `yyyy-MM-dd` day key → models without known pricing, whether excluded or estimated with a fallback.
    var unknownModelsByDay: [String: Set<String>]
    var fallbackPricingModelsByDay: [String: Set<String>]?
    /// Local edit (pace Task 8, not upstream): every priced usage line, timestamped, in scan order —
    /// upstream only carries day-bucketed totals (`series`/`modelUsage`), which can't build the
    /// hourly `BurnSeries` buckets pace's pacing engine needs for burn-rate projection. Populated by
    /// `ClaudeLogUsageScanner.aggregate`/`CodexLogUsageScanner.aggregate` alongside the existing
    /// per-day accumulation, from the same priced lines (unpriceable lines are excluded here too,
    /// matching the day-bucket invariant that every counted row is priced).
    var entries: [ModelUsageEntry] = []
    /// Local edit (pace Task 8, not upstream): count of session-log lines that failed to parse as
    /// JSON at all (a genuinely corrupt/foreign line), set by the scanner's `scan()` after unwrapping
    /// its parse results. Surfaced in the UI so a silent zero can't pass as "no bad data" (memory
    /// `feedback_self_alarming_monitors`: a scan that can't tell "no logs" from "logs I couldn't
    /// read" should say so, not report a plausible-looking figure).
    var unparsedLineCount: Int = 0

    init(
        series: DailyUsageSeries, modelUsage: ModelUsageSeries? = nil,
        unknownModelsByDay: [String: Set<String>], fallbackPricingModelsByDay: [String: Set<String>]? = nil,
        entries: [ModelUsageEntry] = [], unparsedLineCount: Int = 0
    ) {
        self.series = series
        self.modelUsage = modelUsage
        self.unknownModelsByDay = unknownModelsByDay
        self.fallbackPricingModelsByDay = fallbackPricingModelsByDay
        self.entries = entries
        self.unparsedLineCount = unparsedLineCount
    }
}
