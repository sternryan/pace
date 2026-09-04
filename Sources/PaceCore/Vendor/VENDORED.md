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
| Providers/Claude/ClaudeLogUsageScanner.swift | Sources/OpenUsage/Providers/Claude/ClaudeLogUsageScanner.swift | header only |
| Providers/Codex/CodexLogFileParser.swift | Sources/OpenUsage/Providers/Codex/CodexLogFileParser.swift | header only |
| Providers/Codex/CodexLogUsageScanner.swift | Sources/OpenUsage/Providers/Codex/CodexLogUsageScanner.swift | header only |
| Providers/Codex/CodexLogUsageScanner+Pricing.swift | Sources/OpenUsage/Providers/Codex/CodexLogUsageScanner+Pricing.swift | header only |
| Providers/Codex/CodexUsagePricing.swift | Sources/OpenUsage/Providers/Codex/CodexUsagePricing.swift | header only |
| Pricing/ModelPricing.swift | Sources/OpenUsage/Pricing/ModelPricing.swift | header only |
| Pricing/ModelPricingStore.swift | Sources/OpenUsage/Pricing/ModelPricingStore.swift | header only |
| Pricing/ModelRates.swift | Sources/OpenUsage/Pricing/ModelRates.swift | header only |
| Pricing/PricingCatalog.swift | Sources/OpenUsage/Pricing/PricingCatalog.swift | header only |
| Pricing/PricingCatalogCodecs.swift | Sources/OpenUsage/Pricing/PricingCatalogCodecs.swift | header only |
| Pricing/PricingFallbackOptions.swift | Sources/OpenUsage/Pricing/PricingFallbackOptions.swift | header only |
| Pricing/PricingSupplement.swift | Sources/OpenUsage/Pricing/PricingSupplement.swift | header only |
| Models/DailyUsageSeries.swift | Sources/OpenUsage/Models/DailyUsageSeries.swift | header only |
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

`swift build` emits 6 "converting non-Sendable function value to '@Sendable ...' may introduce data
races" warnings from vendored code, unchanged from upstream (not introduced by any local edit):

- `Pricing/ModelPricingStore.swift:43,45` (`now: Date.init`, `bundledData: ModelPricingStore.bundledResourceData`)
- `Providers/Claude/ClaudeLogUsageScanner.swift:92,104,114` (`parse: Self.parseFile`)
- `Providers/Codex/CodexLogUsageScanner.swift:97` (`parse: Self.parseFile`)

Upstream builds under Swift 6 strict concurrency (macOS 15 target); under this package's language
mode 5 / macOS 14 target the same static-method references to non-`@Sendable` closures surface as
warnings rather than passing silently. No behavior difference — left as-is per the task brief
("warnings introduced by vendored code are acceptable ONLY if listed here with the reason").
