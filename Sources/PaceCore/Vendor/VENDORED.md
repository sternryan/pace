# Vendored code

Upstream: https://github.com/robinebers/openusage @ 8321283f61335b9e1d942c61f38de042a431a0a6 (MIT, see LICENSE).
Re-vendor by diffing each file against that commit, never by re-copying blind.

Brief's Step 1 copy list named `JSONLScanCacheStore+Coordination.swift`; the actual upstream file
at that commit is `Providers/JSONLScanCacheCoordination.swift` — vendored that file under its real
name (see the trimmed-content row below).

| Local path | Upstream path | Local edits |
|---|---|---|
| LICENSE | LICENSE | none |
| Providers/IncrementalJSONLScanner.swift | Sources/OpenUsage/Providers/IncrementalJSONLScanner.swift | header only |
| Providers/JSONLScanCacheStore.swift | Sources/OpenUsage/Providers/JSONLScanCacheStore.swift | header only |
| Providers/JSONLScanCacheCoordination.swift | Sources/OpenUsage/Providers/JSONLScanCacheCoordination.swift | header, plus removed `enum PersistentJSONLScanCaches` (its `flushPendingWrites()` calls `GrokLogUsageScanner`/`PiUsageScanner`, providers out of scope for this task); kept `JSONLParsePermitPool`, which `IncrementalJSONLScanner` needs |
| Providers/DailyUsageAccumulator.swift | Sources/OpenUsage/Providers/DailyUsageAccumulator.swift | header only |
| Providers/JSONLStreamingReader.swift | Sources/OpenUsage/Providers/JSONLStreamingReader.swift | header only (pulled in for `JSONLStatelessParserState`/`JSONLStreamingReader`, referenced by `IncrementalJSONLScanner`, not in the brief's Step 1 list) |
| Providers/UsageLogReadFailureReporter.swift | Sources/OpenUsage/Providers/UsageLogReadFailureReporter.swift | header only (pulled in for `IncrementalJSONLScanner`'s `readFailureReporter`; brief said "under Services/" but it actually lives in Providers/) |
| Providers/Claude/ClaudeLogUsageScanner.swift | Sources/OpenUsage/Providers/Claude/ClaudeLogUsageScanner.swift | header, plus Task 8's `EntryOrUnparsed` wrapper / unparsed-line counting / per-message `entries` (see Task 8 section below) |
| Providers/Codex/CodexLogFileParser.swift | Sources/OpenUsage/Providers/Codex/CodexLogFileParser.swift | header, plus Task 8's `EventOrUnparsed` wrapper / unparsed-line counting (see Task 8 section below) |
| Providers/Codex/CodexLogUsageScanner.swift | Sources/OpenUsage/Providers/Codex/CodexLogUsageScanner.swift | header, plus Task 8's `EventOrUnparsed` wrapper / unparsed-line counting (see Task 8 section below) |
| Providers/Codex/CodexLogUsageScanner+Pricing.swift | Sources/OpenUsage/Providers/Codex/CodexLogUsageScanner+Pricing.swift | header, plus Task 8's per-event `entries` accumulation (see Task 8 section below) |
| Providers/Codex/CodexUsagePricing.swift | Sources/OpenUsage/Providers/Codex/CodexUsagePricing.swift | header only |
| Pricing/ModelPricing.swift | Sources/OpenUsage/Pricing/ModelPricing.swift | header only |
| Pricing/ModelPricingStore.swift | Sources/OpenUsage/Pricing/ModelPricingStore.swift | header only |
| Pricing/ModelRates.swift | Sources/OpenUsage/Pricing/ModelRates.swift | header only |
| Pricing/PricingCatalog.swift | Sources/OpenUsage/Pricing/PricingCatalog.swift | header only |
| Pricing/PricingCatalogCodecs.swift | Sources/OpenUsage/Pricing/PricingCatalogCodecs.swift | header only |
| Pricing/PricingFallbackOptions.swift | Sources/OpenUsage/Pricing/PricingFallbackOptions.swift | header only |
| Pricing/PricingSupplement.swift | Sources/OpenUsage/Pricing/PricingSupplement.swift | header only |
| Models/DailyUsageSeries.swift | Sources/OpenUsage/Models/DailyUsageSeries.swift | header, plus Task 8's `ModelUsageEntry.timestamp` / `LogUsageScan.entries` / `LogUsageScan.unparsedLineCount` additions (see Task 8 section below) |
| Services/HTTPClient.swift | Sources/OpenUsage/Services/HTTPClient.swift | header only |
| Services/ProxyConfig.swift | Sources/OpenUsage/Services/ProxyConfig.swift | header only (pulled in for `HTTPClient`'s `ProxyConfig.current`, not in the brief's Step 1 list) |
| Support/ProviderParse.swift | Sources/OpenUsage/Support/ProviderParse.swift | header only |
| Support/OpenUsageISO8601.swift | Sources/OpenUsage/Support/OpenUsageISO8601.swift | header only (pulled in for `ClaudeLogUsageScanner`/`CodexLogFileParser` timestamp parsing, not in the brief's Step 1 list) |

## Local shims (not vendored — no upstream row)

Upstream's `ProviderSnapshot`/`MetricLine` (Models/) and `TextFileAccessing`/`KeychainAccessing`/
`LocalTextFileAccessor`/`SecurityKeychainAccessor` (Services/) were named in the brief as things a
prior survey flagged as possibly needed, but nothing in the files actually vendored above
references them — they were never copied and there is no `OUProviderSnapshot` rename to record;
the name collision the brief anticipated did not arise.

| Local path | Why it exists | What it replaces |
|---|---|---|
| Services/EnvironmentReading.swift | `ClaudeLogUsageScanner`/`CodexLogUsageScanner` take an `EnvironmentReading` and default to `ProcessEnvironmentReader()`. Upstream's version (`Services/SystemClients.swift`) also consults a captured login-shell snapshot (`LoginShellEnvironment`, `ShellEnvironmentSnapshotStore`) for Finder/Dock-launched apps — app-lifecycle infra out of scope here. This shim reads only `ProcessInfo.processInfo.environment`, which is everything PaceCore's `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`XDG_CONFIG_HOME` lookups need. Also carries `expandHome(_:)`, copied verbatim from the same upstream file (no logic change, self-contained). | `protocol EnvironmentReading`, `struct ProcessEnvironmentReader`, `func expandHome` in `Sources/OpenUsage/Services/SystemClients.swift` |
| Support/AppLog.swift | Every vendored file logs through `AppLog`/`LogTag`, and `HTTPClient`/`ModelPricingStore` also reference `LogRedaction.bodyPreview`/`.redactURL` and `Bundle.openUsageResources`. Upstream's real versions are a full app-lifecycle logging facility (`~/Library/Logs/OpenUsage/OpenUsage.log`, a user-configurable level floor, `LogFile`, `LogLevelSetting`) and an app-bundle resource locator (`ContainingAppBundle`, packaged-`.app` `Contents/Resources` search) — both out of scope for PaceCore per its CLAUDE.md ("PaceCore stays free of AppKit and WebKit"). This shim is a bare `os.Logger` pass-through for the tags actually used (`.cache`, `.http`, `.config`, `.keychain`, `.refresh`, `.plugin(_:)`) plus no-op stand-ins for `LogRedaction.bodyPreview`/`.redactURL` and `Bundle.openUsageResources` (the latter always misses, by design — PaceCore never bundles the pricing JSON snapshots and constructs pricing via `ModelPricing.empty` / `PricingSupplement`'s in-memory initializer instead of `ModelPricingStore.bundledResourceData`). | `enum AppLog`, `enum LogTag`, `enum LogRedaction` in `Sources/OpenUsage/Support/AppLog.swift` and `Sources/OpenUsage/Support/LogRedaction.swift`; `extension Bundle { static let openUsageResources }` in `Sources/OpenUsage/Support/ResourceBundle.swift` |

## Package.swift

`Sources/PaceCore` target gained `exclude: ["Vendor/OpenUsage/LICENSE"]` so SwiftPM does not warn
about an unhandled resource file.

## Known upstream Sendable-closure warnings

`swift build` emits 5 "converting non-Sendable function value to '@Sendable ...' may introduce data
races" warnings from vendored code, unchanged from upstream (not introduced by any local edit):

- `Pricing/ModelPricingStore.swift:43,45` (`now: Date.init`, `bundledData: ModelPricingStore.bundledResourceData`)
- `Providers/Claude/ClaudeLogUsageScanner.swift:104,116,126` (`parse: Self.parseFile`)

Upstream builds under Swift 6 strict concurrency (macOS 15 target); under this package's language
mode 5 / macOS 14 target the same static-method references to non-`@Sendable` closures surface as
warnings rather than passing silently. No behavior difference — left as-is per the task brief
("warnings introduced by vendored code are acceptable ONLY if listed here with the reason").

Task 8 dropped the sixth (`Providers/Codex/CodexLogUsageScanner.swift`, formerly line 97) rather
than carrying it forward: that call site (the empty-files early-return branch of `scan()`) now
passes a closure literal instead of a bare `Self.parseFile` reference, which the compiler treats as
already conforming to `@Sendable` — see the Task 8 section below for why that call site changed
shape at all.

## Task 8: hourly burn-rate entries + unparsed-line count (pace `SpendProvider`)

`SpendProvider` (`Sources/PaceCore/SpendProvider.swift`, not vendored) needs two things neither
scanner exposed upstream, confirmed absent by direct inspection of `Models/DailyUsageSeries.swift`
at the vendored commit: (1) per-message timestamped usage rows — upstream's `LogUsageScan` only
carries day-bucketed totals (`series`/`modelUsage`), which can't build the hourly `BurnSeries`
buckets the pacing engine needs for burn-rate projection; (2) a count of lines that failed to parse
at all, so a silent zero can't pass as "no bad data" (memory `feedback_self_alarming_monitors`).
Both were added as the smallest edit that keeps every existing call site and behavior unchanged:

- **`Models/DailyUsageSeries.swift`**
  - `ModelUsageEntry` gained `var timestamp: Date? = nil` — nil on every existing (day-bucketed)
    use of the type; set only on the new per-message rows described below.
  - `LogUsageScan` gained `var entries: [ModelUsageEntry] = []` (every priced usage line, timestamped,
    in scan order) and `var unparsedLineCount: Int = 0`, both defaulted so the existing memberwise
    `init` call sites (`DailyUsageAccumulator.build()`) keep compiling unchanged; the two new fields
    are populated separately, after `build()` returns, by each scanner's `aggregate`/`scan`.

- **`Providers/Claude/ClaudeLogUsageScanner.swift`**
  - Added `struct EntryOrUnparsed: Codable, Sendable { var entry: Entry? }` and changed the actor's
    `scanner`/`sharedScanner`/`init(incrementalScanner:)` from `IncrementalJSONLScanner<Entry>` to
    `IncrementalJSONLScanner<EntryOrUnparsed>`. The incremental scanner's on-disk/in-memory cache is
    keyed on `Item`, so "this line was garbage" has to travel through the same `[Item]` pipeline as
    the real entries — a side-channel counter would be silently dropped on a cache hit for an
    unchanged file. `sharedScanner`'s `schemaVersion` bumped 1 -> 2 (the persisted record shape
    changed, so an old on-disk cache is correctly treated as a schema mismatch and rebuilt, per the
    existing `IncrementalJSONLScanner` doc comment on that field).
  - `parseFile(_:)` now returns `[EntryOrUnparsed]`. A line with no `"usage":{` marker was and stays
    a silent skip (the overwhelming majority of a session file — user turns, tool results, etc.,
    which are valid JSON); the change is that such a line is now also checked with the new
    `isUnparsableLine(_:)` helper, and only counted (`EntryOrUnparsed(entry: nil)`) when it is
    **not** valid JSON at all — a genuinely corrupt/foreign line. A non-blank line that already had a
    "usage" marker and decodes into zero/one/many entries is wrapped as before, unchanged in count or
    content.
  - `scan()` unwraps the scanner's `[EntryOrUnparsed]` result into `[Entry]` (fed to the existing
    `dedup`/`aggregate` unchanged) plus `wrapped.count - entries.count`, written onto the returned
    `LogUsageScan.unparsedLineCount`.
  - `aggregate(entries:since:pricing:)` now also builds `entries: [ModelUsageEntry]` — one row per
    successfully priced input `Entry` (same day/model/cost values already computed for
    `accumulator.add`, plus the entry's own `timestamp`), appended into the returned scan's
    `entries` field. Unpriceable entries are excluded from `entries` exactly as they already were
    from `accumulator`/`unknownModelsByDay`, so the two stay consistent ("every counted row is
    priced").

- **`Providers/Codex/CodexLogUsageScanner.swift`** — the same shape as Claude, for parity (production
  `SpendProvider` treats both scanners' `LogUsageScan` uniformly):
  - Added `struct EventOrUnparsed: Codable, Sendable { var event: Event? }`; `scanner`/
    `sharedScanner`/`init(incrementalScanner:)` retyped to `IncrementalJSONLScanner<EventOrUnparsed>`;
    `sharedScanner`'s `schemaVersion` bumped 3 -> 4.
  - `scan()`'s empty-files early-return branch (previously `parse: Self.parseFile`, which returned
    `[Event]`) now passes `{ Self.parseFile($0).map { EventOrUnparsed(event: $0) } }` to match the
    scanner's new `Item` type — this discard call only exists to let an empty scan clear a stale
    cache identity, so wrapping every result as non-nil is correct (there's nothing to mark
    unparsed on an intentionally-empty file list).
  - The main scan path's `scanner.items(..., initialState: CodexLogFileParser(), parse: { data,
    state in state.parse(data) })` result is unwrapped the same way as Claude's: `wrapped.compactMap
    (\.event)` plus a difference count onto `LogUsageScan.unparsedLineCount`.
  - The standalone `static func parseFile(_ data: Data) -> [Event]` helper (unused by `scan()`
    itself — dead code kept for API parity, not called anywhere in this repo) now does
    `parser.parse(data).compactMap(\.event)` to keep its own return type (`[Event]`) unchanged
    now that `CodexLogFileParser.parse` returns `[EventOrUnparsed]`.

- **`Providers/Codex/CodexLogFileParser.swift`**
  - `parse(_:)` now returns `[CodexLogUsageScanner.EventOrUnparsed]`. Mirrors Claude's rule exactly:
    a line matching none of the parser's known line-type markers (`turn_context`, `session_meta`,
    `task_started`, `thread_settings_applied`, `token_count`) was and stays a silent skip (the
    overwhelming majority of a rollout); it is now additionally checked against the new
    `isUnparsableLine(_:)` helper and counted only when not valid JSON at all. A line that DOES
    match a marker but fails the immediate `JSONSerialization.jsonObject` decode (previously a bare
    `continue`) is now also counted — a corrupt line that costs a real, matched log-line type. Every
    other existing `continue` (turn-context/session-meta/tier/replay-gate bookkeping lines that
    decode fine but legitimately produce no event) is untouched and still uncounted. The one
    real `Event` append at the bottom is wrapped as `.init(event: ...)`.

- **`Providers/Codex/CodexLogUsageScanner+Pricing.swift`**
  - `aggregate(events:since:pricing:fallbackModel:)` gained the same per-priced-event `entries:
    [ModelUsageEntry]` accumulation as Claude's `aggregate`, appended onto the returned scan's
    `entries` field alongside the unchanged `accumulator.add` call.

No test doubles the pricing feed's network dependency here — `SpendProviderTests` instead
constructs a `ModelPricing` directly from an in-memory `PricingCatalog` entry (bypassing
`ModelPricingStore` entirely) via `SpendProvider`'s internal `pricing:` init parameter, since
`ModelPricing.empty` prices nothing and PaceCore intentionally ships no bundled pricing JSON (see
the `Support/AppLog.swift` row above).
