# Pace v3 Unified Pacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `~/pace` into one menubar app + CLI + statusline feed that shows Claude and Codex window usage vs reset, projects the cap time from real burn rate, and says whether the free smithy lane can absorb the work.

**Architecture:** One SwiftPM package. `PaceCore` (library, tested) holds four `Provider`s (Claude, Codex, Smithy, Spend), a pure `PacingEngine` that joins their snapshots into a `PaceReport`, an atomic `ReportStore`, and a loopback HTTP server. `Pace` (menubar app) and `pace` (CLI) are thin shells over one `RefreshCoordinator`. A shell script reads the report file for the Claude Code statusline.

**Tech Stack:** Swift 5.9 tools / Swift 6.3 compiler in language mode 5, macOS 14+, SwiftUI `MenuBarExtra`, Foundation `URLSession`, `Network.framework` `NWListener` for loopback, XCTest. Vendored MIT code from `robinebers/openusage` @ `8321283f61335b9e1d942c61f38de042a431a0a6`.

**Spec:** `docs/superpowers/specs/2026-09-04-pace-v3-unified-pacing-design.md`

## Global Constraints

- Lanes for THIS project (Ryan, 2026-09-04): smithy local (`hearth:8085/v1`, model `local-heavy`) and Claude subscription tiers only. **NO Codex** — the weekly cap is exhausted. Never run `codex exec` for any task here.
- macOS 14.0 deployment target (`platforms: [.macOS(.v14)]`), `swift-tools-version:5.9`. Deviation from spec §3 ("Swift 6 language mode"): stay in language mode 5 to avoid a strict-concurrency migration of pace v2; vendored Swift-6 code compiles under mode 5.
- Existing `LaneKind`/`LaneUsage`/`UsageSnapshot`/`PaceCalculator` are extended, not replaced. Spec's `UsageWindow` is `LaneUsage`.
- No telemetry, no Sparkle, no iCloud, no ntfy, no frontier-model call anywhere in the app (spec §7).
- Every vendored file: header comment `// Vendored from robinebers/openusage@8321283f <upstream path> (MIT). Local edits listed in Sources/PaceCore/Vendor/VENDORED.md`.
- Commit after every task. Commit messages have NO `Claude-Session:` trailer (house rule 10). Push only at the end of Task 16 after the grader.
- Test command: `make test` from repo root, and `swift test --package-path ~/pace` from `$HOME` (spec §6.1 wants two directories).
- Undocumented endpoints: `https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`), `https://chatgpt.com/backend-api/wham/usage`. Local log scanning is the fallback for SPEND only, never for limits.
- Keychain: per-(service,account) limit-one reads only. `kSecMatchLimitAll` + `kSecReturnData` is errSecParam (-50).
- Smithy facts (verified live 2026-09-04): scheduler `GET http://100.85.83.97:8085/v1/models` → `data[]` with `id == "local-heavy"`, `smithy.serving_now: Bool`, `smithy.candidates[].{node,status,endpoint}`; anvil lease server `GET http://100.122.29.52:8001/lease` → `{"state":"free"|"held"|"wedged", ...}`. Tri-state output, never two.
- Swift TCC/Keychain callbacks need `@Sendable` (LEARNINGS.md); Swift 5.9 tools reject MainActor-isolated default args in nonisolated inits (use optional param + `?? T()` inside).

---

## File map

| Path | Responsibility | Task |
|---|---|---|
| `Package.swift` | add `PaceCLI` target, test resources | 1 |
| `Sources/PaceCore/LaneKind.swift` | add `codexSession`, `codexWeek`, `overage` | 1 |
| `Sources/PaceCore/ProviderSnapshot.swift` | `ProviderID`, `SnapshotSource`, `LaneState`, `ProviderError`, `ProviderSnapshot`, `Provider` protocol | 1 |
| `Sources/PaceCore/BurnSeries.swift` | `HourBucket`, `DayBucket`, `BurnSeries` | 1 |
| `Sources/PaceCore/PaceReport.swift` | `WindowVerdict`, `ProviderStatus`, `PaceReport` | 2 |
| `Sources/PaceCore/PacingEngine.swift` | pure join: snapshots → `PaceReport` | 2 |
| `Sources/PaceCore/PaceCalculator.swift` | add `tooEarly`/`onPace`/`ahead`/`capped` status + slack | 2 |
| `Sources/PaceCore/ReportStore.swift` | atomic write/read of `report.json`, stale flag | 3 |
| `Sources/PaceCore/CodexRateLimitParser.swift` | moved from codex-pace | 4 |
| `Sources/PaceCore/CodexSessionUsageSource.swift` | moved from codex-pace, made a `Provider` fallback | 4 |
| `Sources/PaceCore/CodexAuthStore.swift` | reads `~/.codex/auth.json`, refresh | 5 |
| `Sources/PaceCore/CodexUsageClient.swift` | `wham/usage` GET + token refresh | 5 |
| `Sources/PaceCore/CodexUsageNormalizer.swift` | response → `[LaneUsage]` | 5 |
| `Sources/PaceCore/CodexProvider.swift` | API first, session-file fallback | 5 |
| `Sources/PaceCore/SmithyProvider.swift` | two GETs → `LaneState` | 6 |
| `Sources/PaceCore/Vendor/OpenUsage/**` | scanner, cache, log scanners, pricing, HTTP client | 7 |
| `Sources/PaceCore/Vendor/VENDORED.md` | file list, upstream commit, local edits | 7 |
| `Sources/PaceCore/SpendProvider.swift` | vendored scanners → `BurnSeries` | 8 |
| `Sources/PaceCore/KeychainCredentialStore.swift` | moved from `Sources/Pace` | 9 |
| `Sources/PaceCore/ClaudeProvider.swift` | wraps `ApiUsageSource` as a `Provider` | 9 |
| `Sources/PaceCore/RefreshCoordinator.swift` | runs providers, engine, store | 10 |
| `Sources/PaceCore/LoopbackServer.swift` | `127.0.0.1:6737/v1/report` | 11 |
| `Sources/PaceCLI/main.swift` | `pace`, `--json`, `--refresh` | 12 |
| `Sources/Pace/AppState.swift`, `MenuView.swift`, `IconRenderer.swift`, `PreferencesView.swift`, `PaceApp.swift` | UI over `RefreshCoordinator` | 13 |
| `Scripts/pace-statusline-segment.sh` + `~/.claude/hooks/gsd-statusline.js` | statusline segment | 14 |
| `~/codex-pace` retirement | archive, remove app, login item | 15 |
| `README.md`, `TODOS.md`, live verification, grader | | 16 |

Deleted in Task 9: `Sources/Pace/ScrapeUsageSource.swift`, `UsageFetcher.swift`, `Sources/PaceCore/UsagePanelTextExtractor.swift`, `UsageParser.swift`, their tests, and the `browser` `DataSourceMode`.

---

### Task 1: Core types and package layout

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/PaceCore/LaneKind.swift`
- Create: `Sources/PaceCore/ProviderSnapshot.swift`
- Create: `Sources/PaceCore/BurnSeries.swift`
- Create: `Sources/PaceCLI/main.swift` (placeholder body that only prints `pace v3`; replaced in Task 12)
- Test: `Tests/PaceCoreTests/ProviderSnapshotTests.swift`

**Interfaces:**
- Produces: `ProviderID`, `SnapshotSource`, `LaneState`, `ProviderError`, `ProviderSnapshot`, `Provider`, `HourBucket`, `DayBucket`, `BurnSeries`, new `LaneKind` cases.

- [ ] **Step 1: Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .executable(name: "Pace", targets: ["Pace"]),
        .executable(name: "pace-cli", targets: ["PaceCLI"])
    ],
    targets: [
        .target(name: "PaceCore"),
        .executableTarget(name: "Pace", dependencies: ["PaceCore"]),
        .executableTarget(name: "PaceCLI", dependencies: ["PaceCore"]),
        .testTarget(name: "PaceCoreTests", dependencies: ["PaceCore"],
                    resources: [.copy("Fixtures")])
    ]
)
```

Create `Tests/PaceCoreTests/Fixtures/.gitkeep` and `Sources/PaceCLI/main.swift` containing `print("pace v3")`.

- [ ] **Step 2: Failing test**

```swift
import XCTest
@testable import PaceCore

final class ProviderSnapshotTests: XCTestCase {
    func testLaneKindHasCodexAndOverageCases() {
        XCTAssertEqual(LaneKind.codexSession.rawValue, "codexSession")
        XCTAssertEqual(LaneKind.codexWeek.rawValue, "codexWeek")
        XCTAssertEqual(LaneKind.overage.rawValue, "overage")
        XCTAssertEqual(LaneKind.codexSession.displayName, "Codex 5h")
        XCTAssertEqual(LaneKind.codexSession.provider, .codex)
        XCTAssertEqual(LaneKind.fableWeek.provider, .claude)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snap = ProviderSnapshot(provider: .smithy, fetchedAt: Date(timeIntervalSince1970: 1_000),
                                    source: .api, lanes: [], laneState: .leasedAway, burn: nil,
                                    error: .transient("timeout"))
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(ProviderSnapshot.self, from: data)
        XCTAssertEqual(back, snap)
    }

    func testLaneStateHasExactlyThreeCases() {
        XCTAssertEqual(LaneState.allCases.map(\.rawValue), ["serving", "leasedAway", "unreachable"])
    }
}
```

- [ ] **Step 3: Run** `swift test --filter ProviderSnapshotTests` → FAIL (types missing).

- [ ] **Step 4: Implement**

`LaneKind.swift` — add cases and a provider accessor:

```swift
public enum LaneKind: String, CaseIterable, Hashable, Sendable, Codable {
    case session, allModelsWeek, fableWeek, overage
    case codexSession, codexWeek

    public var displayName: String {
        switch self {
        case .session: return "5h session"
        case .allModelsWeek: return "All models · week"
        case .fableWeek: return "Fable · week"
        case .overage: return "Extra usage"
        case .codexSession: return "Codex 5h"
        case .codexWeek: return "Codex · week"
        }
    }

    public var provider: ProviderID {
        switch self {
        case .session, .allModelsWeek, .fableWeek, .overage: return .claude
        case .codexSession, .codexWeek: return .codex
        }
    }
}
```

(Keep the existing display strings for the three v2 cases exactly as they are in the file; only add the new ones.)

`ProviderSnapshot.swift`:

```swift
import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable { case claude, codex, smithy, spend }

public enum SnapshotSource: String, Codable, Sendable { case api, localFallback, cache }

/// Three states, never two (memory infra_silent_false_negative_lanes).
public enum LaneState: String, Codable, Sendable, CaseIterable { case serving, leasedAway, unreachable }

public enum ProviderError: Error, Equatable, Codable, Sendable {
    case needsLogin(String)       // human instruction, e.g. "open Claude Code"
    case transient(String)
    case parseError(String)
    case unreachable(String)

    public var message: String {
        switch self {
        case .needsLogin(let s), .transient(let s), .parseError(let s), .unreachable(let s): return s
        }
    }
}

public struct ProviderSnapshot: Equatable, Codable, Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    public let source: SnapshotSource
    public let lanes: [LaneUsage]
    public let laneState: LaneState?
    public let burn: BurnSeries?
    public let error: ProviderError?

    public init(provider: ProviderID, fetchedAt: Date, source: SnapshotSource, lanes: [LaneUsage],
                laneState: LaneState? = nil, burn: BurnSeries? = nil, error: ProviderError? = nil) {
        self.provider = provider; self.fetchedAt = fetchedAt; self.source = source
        self.lanes = lanes; self.laneState = laneState; self.burn = burn; self.error = error
    }
}

public protocol Provider: Sendable {
    var id: ProviderID { get }
    /// Never throws. Failures are reported inside the snapshot with `error` set
    /// and whatever lanes could still be produced (possibly from cache).
    func fetch(now: Date) async -> ProviderSnapshot
}
```

`BurnSeries.swift`:

```swift
import Foundation

public struct HourBucket: Equatable, Codable, Sendable {
    public let start: Date            // truncated to the hour, UTC
    public let provider: ProviderID   // .claude or .codex
    public let tokens: Int            // input + output + cache tokens
    public let costUSD: Double
    public init(start: Date, provider: ProviderID, tokens: Int, costUSD: Double) {
        self.start = start; self.provider = provider; self.tokens = tokens; self.costUSD = costUSD
    }
}

public struct DayBucket: Equatable, Codable, Sendable {
    public let day: String            // "YYYY-MM-DD" local
    public let provider: ProviderID
    public let tokens: Int
    public let costUSD: Double
    public init(day: String, provider: ProviderID, tokens: Int, costUSD: Double) {
        self.day = day; self.provider = provider; self.tokens = tokens; self.costUSD = costUSD
    }
}

public struct BurnSeries: Equatable, Codable, Sendable {
    public let hourly: [HourBucket]   // trailing 6 h
    public let daily: [DayBucket]     // trailing 30 d
    public let unparsedLines: Int     // surfaced in UI so a silent zero cannot pass as real
    public init(hourly: [HourBucket], daily: [DayBucket], unparsedLines: Int) {
        self.hourly = hourly; self.daily = daily; self.unparsedLines = unparsedLines
    }

    /// Tokens attributed to `provider` between `from` and `to` from the hourly buckets.
    public func tokens(for provider: ProviderID, from: Date, to: Date) -> Int {
        hourly.filter { $0.provider == provider && $0.start >= from && $0.start < to }
              .reduce(0) { $0 + $1.tokens }
    }

    /// Tokens per second for `provider` over the trailing `window` ending at `now`.
    public func rate(for provider: ProviderID, now: Date, window: TimeInterval = 3600) -> Double {
        let t = tokens(for: provider, from: now.addingTimeInterval(-window), to: now)
        return window > 0 ? Double(t) / window : 0
    }
}
```

- [ ] **Step 5: Run** `make test` → PASS (v2 tests still green; `CoreTypesTests.testLaneKindDisplayNames` may need the three new names appended — update it).

- [ ] **Step 6: Commit** `git add -A && git commit -m "feat(core): provider snapshot, burn series, codex/overage lane kinds"`

---

### Task 2: Pacing engine

**Files:**
- Modify: `Sources/PaceCore/PaceCalculator.swift`
- Create: `Sources/PaceCore/PaceReport.swift`
- Create: `Sources/PaceCore/PacingEngine.swift`
- Test: `Tests/PaceCoreTests/PacingEngineTests.swift`

**Interfaces:**
- Consumes: `LaneUsage`, `PaceReading`, `PaceCalculator.reading(for:now:)`, `ProviderSnapshot`, `BurnSeries`, `LaneState`.
- Produces: `PaceStatus`, `WindowVerdict`, `ProviderStatus`, `PaceReport`, `PacingEngine.report(snapshots:now:)`.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import PaceCore

final class PacingEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // fixed clock

    func lane(_ kind: LaneKind, used: Int, windowLength: TimeInterval, elapsed: TimeInterval) -> LaneUsage {
        LaneUsage(kind: kind, percentUsed: used, resetDate: now.addingTimeInterval(windowLength - elapsed),
                  windowLength: windowLength, severity: .normal)
    }
    func snap(_ p: ProviderID, lanes: [LaneUsage] = [], laneState: LaneState? = nil,
              burn: BurnSeries? = nil, error: ProviderError? = nil, source: SnapshotSource = .api) -> ProviderSnapshot {
        ProviderSnapshot(provider: p, fetchedAt: now, source: source, lanes: lanes, laneState: laneState, burn: burn, error: error)
    }

    func testStatusBands() {
        // 20% used at 50% elapsed → onPace; 60% at 50% → ahead; 54% at 50% → onPace (5-pt slack); 100% → capped
        let l1 = lane(.session, used: 20, windowLength: 18000, elapsed: 9000)
        let l2 = lane(.session, used: 60, windowLength: 18000, elapsed: 9000)
        let l3 = lane(.session, used: 54, windowLength: 18000, elapsed: 9000)
        let l4 = lane(.session, used: 100, windowLength: 18000, elapsed: 9000)
        XCTAssertEqual(PaceCalculator.status(for: l1, now: now), .onPace)
        XCTAssertEqual(PaceCalculator.status(for: l2, now: now), .ahead)
        XCTAssertEqual(PaceCalculator.status(for: l3, now: now), .onPace)
        XCTAssertEqual(PaceCalculator.status(for: l4, now: now), .capped)
    }

    func testTooEarlyUnder15Minutes() {
        let l = lane(.session, used: 40, windowLength: 18000, elapsed: 600)
        XCTAssertEqual(PaceCalculator.status(for: l, now: now), .tooEarly)
    }

    func testProjectionUsesBurnRateWhenPresent() {
        // 50% used, 1h elapsed of a 5h window. Burn: 1,000,000 tokens attributed since window start,
        // trailing-hour rate = 1,000,000 tokens/h → 20,000 tokens per percent → 50 remaining % = 1h.
        let l = lane(.session, used: 50, windowLength: 18000, elapsed: 3600)
        let start = now.addingTimeInterval(-3600)
        let burn = BurnSeries(hourly: [HourBucket(start: start, provider: .claude, tokens: 1_000_000, costUSD: 1)],
                              daily: [], unparsedLines: 0)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l]), snap(.spend, burn: burn)], now: now)
        let v = report.windows.first { $0.kind == .session }!
        XCTAssertEqual(v.projectedCapAt!.timeIntervalSince(now), 3600, accuracy: 5)
        XCTAssertEqual(v.projectionBasis, .burnRate)
    }

    func testProjectionFallsBackToPercentRateWithoutBurn() {
        let l = lane(.session, used: 50, windowLength: 18000, elapsed: 3600)
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        let v = report.windows.first { $0.kind == .session }!
        XCTAssertEqual(v.projectedCapAt!.timeIntervalSince(now), 3600, accuracy: 5)  // 50%/h → 1h
        XCTAssertEqual(v.projectionBasis, .percentRate)
    }

    func testProjectionClampedToResetsFirst() {
        let l = lane(.session, used: 10, windowLength: 18000, elapsed: 9000)   // 10% at 50% → caps after reset
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        let v = report.windows.first!
        XCTAssertNil(v.projectedCapAt)
        XCTAssertTrue(v.resetsFirst)
    }

    func testHeadlinePicksSoonestCap() {
        let a = lane(.session, used: 60, windowLength: 18000, elapsed: 9000)        // caps in 1.25h
        let b = lane(.codexWeek, used: 60, windowLength: 604800, elapsed: 302400)   // caps in 3.5d
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [a]), snap(.codex, lanes: [b])], now: now)
        XCTAssertEqual(report.headline?.kind, .session)
    }

    func testHeadlineWhenNothingAheadIsTightest() {
        let a = lane(.session, used: 30, windowLength: 18000, elapsed: 9000)   // -20
        let b = lane(.codexWeek, used: 45, windowLength: 604800, elapsed: 302400) // -5 → tightest
        let report = PacingEngine.report(snapshots: [snap(.claude, lanes: [a]), snap(.codex, lanes: [b])], now: now)
        XCTAssertEqual(report.headline?.kind, .codexWeek)
        XCTAssertNil(report.advice)
    }

    func testAdviceBranches() {
        let ahead = lane(.fableWeek, used: 80, windowLength: 604800, elapsed: 302400)
        for (state, expected) in [(LaneState.serving, "move bulk/mechanical work to smithy (hearth:8085 local-heavy)"),
                                  (.leasedAway, "smithy GPU is leased; Codex is the next lane"),
                                  (.unreachable, "smithy unreachable, check before routing there")] {
            let r = PacingEngine.report(snapshots: [snap(.claude, lanes: [ahead]), snap(.smithy, laneState: state)], now: now)
            XCTAssertEqual(r.advice, expected, "\(state)")
        }
    }

    func testAdviceWhenCodexIsTheCappedOne() {
        let capped = lane(.codexWeek, used: 100, windowLength: 604800, elapsed: 302400)
        let r = PacingEngine.report(snapshots: [snap(.codex, lanes: [capped]), snap(.smithy, laneState: .leasedAway)], now: now)
        XCTAssertEqual(r.advice, "smithy GPU is leased; Claude is the next lane")
    }

    func testProviderStatusesAndStaleFlag() {
        let r = PacingEngine.report(snapshots: [snap(.claude, lanes: [], error: .transient("500"), source: .cache),
                                                snap(.smithy, laneState: .serving)], now: now)
        XCTAssertTrue(r.stale)
        XCTAssertEqual(r.providers.first { $0.provider == .claude }?.error, "500")
        XCTAssertEqual(r.providers.first { $0.provider == .claude }?.source, .cache)
    }

    func testVerdictLineFormat() {
        let l = lane(.fableWeek, used: 71, windowLength: 604800, elapsed: 326592) // 54%
        let r = PacingEngine.report(snapshots: [snap(.claude, lanes: [l])], now: now)
        XCTAssertTrue(r.windows[0].verdict.hasPrefix("Fable · week: 71% used, 54% elapsed, caps "))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter PacingEngineTests` → FAIL.

- [ ] **Step 3: Implement**

Add to `PaceCalculator.swift`:

```swift
public enum PaceStatus: String, Codable, Sendable { case tooEarly, onPace, ahead, capped }

extension PaceCalculator {
    /// Spec §3.3: 15-minute guard, 5-point slack.
    public static let minimumElapsedForStatus: TimeInterval = 15 * 60
    public static let slackPercent = 5

    public static func elapsedFraction(for lane: LaneUsage, now: Date) -> Double? {
        guard let w = lane.windowLength, w > 0 else { return nil }
        let start = lane.resetDate.addingTimeInterval(-w)
        return max(0, min(now.timeIntervalSince(start), w)) / w
    }

    public static func status(for lane: LaneUsage, now: Date) -> PaceStatus {
        if lane.percentUsed >= 100 { return .capped }
        guard let w = lane.windowLength, w > 0 else { return .onPace }
        let start = lane.resetDate.addingTimeInterval(-w)
        let elapsed = now.timeIntervalSince(start)
        if elapsed < minimumElapsedForStatus { return .tooEarly }
        let elapsedPct = Int((max(0, min(elapsed, w)) / w) * 100)
        return lane.percentUsed > elapsedPct + slackPercent ? .ahead : .onPace
    }
}
```

`PaceReport.swift`:

```swift
import Foundation

public enum ProjectionBasis: String, Codable, Sendable { case burnRate, percentRate, none }

public struct WindowVerdict: Equatable, Codable, Sendable {
    public let kind: LaneKind
    public let provider: ProviderID
    public let percentUsed: Int
    public let percentElapsed: Int?
    public let resetsAt: Date
    public let status: PaceStatus
    public let projectedCapAt: Date?      // nil when resetsFirst, tooEarly, or no rate
    public let resetsFirst: Bool
    public let projectionBasis: ProjectionBasis
    public let source: SnapshotSource
    public let fetchedAt: Date
    public let verdict: String
}

public struct ProviderStatus: Equatable, Codable, Sendable {
    public let provider: ProviderID
    public let source: SnapshotSource
    public let fetchedAt: Date
    public let error: String?
}

public struct PaceReport: Equatable, Codable, Sendable {
    public let generatedAt: Date
    public let headline: WindowVerdict?
    public let advice: String?
    public let windows: [WindowVerdict]
    public let laneState: LaneState?
    public let burn: BurnSeries?
    public let providers: [ProviderStatus]
    public let stale: Bool
}
```

`PacingEngine.swift`:

```swift
import Foundation

public enum PacingEngine {
    static let minimumUsedForBurnProjection = 2

    public static func report(snapshots: [ProviderSnapshot], now: Date) -> PaceReport {
        let byProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        let burn = byProvider[.spend]?.burn
        let laneState = byProvider[.smithy]?.laneState

        var windows: [WindowVerdict] = []
        for p in [ProviderID.claude, .codex] {
            guard let s = byProvider[p] else { continue }
            for lane in s.lanes {
                windows.append(verdict(for: lane, snapshot: s, burn: burn, now: now))
            }
        }

        let headline = pickHeadline(windows)
        let advice = advice(for: headline, laneState: laneState)
        let providers = snapshots.map {
            ProviderStatus(provider: $0.provider, source: $0.source, fetchedAt: $0.fetchedAt, error: $0.error?.message)
        }
        let stale = snapshots.contains { $0.error != nil || $0.source == .cache }
        return PaceReport(generatedAt: now, headline: headline, advice: advice, windows: windows,
                          laneState: laneState, burn: burn, providers: providers, stale: stale)
    }

    static func verdict(for lane: LaneUsage, snapshot: ProviderSnapshot, burn: BurnSeries?, now: Date) -> WindowVerdict {
        let status = PaceCalculator.status(for: lane, now: now)
        let elapsedFrac = PaceCalculator.elapsedFraction(for: lane, now: now)
        let elapsedPct = elapsedFrac.map { Int($0 * 100) }

        var cap: Date? = nil
        var basis: ProjectionBasis = .none
        if status != .tooEarly, status != .capped, let w = lane.windowLength, w > 0 {
            let start = lane.resetDate.addingTimeInterval(-w)
            let remainingPct = Double(100 - lane.percentUsed)
            if let burn, lane.percentUsed >= minimumUsedForBurnProjection {
                let attributed = burn.tokens(for: lane.kind.provider, from: start, to: now)
                let ratePerSec = burn.rate(for: lane.kind.provider, now: now)
                if attributed > 0, ratePerSec > 0 {
                    let tokensPerPct = Double(attributed) / Double(lane.percentUsed)
                    cap = now.addingTimeInterval(remainingPct * tokensPerPct / ratePerSec)
                    basis = .burnRate
                }
            }
            if cap == nil, let r = Optional(PaceCalculator.reading(for: lane, now: now)), let c = r.projectedCapDate {
                cap = c; basis = .percentRate
            }
        }
        let resetsFirst = cap.map { $0 >= lane.resetDate } ?? false
        if resetsFirst { cap = nil }

        return WindowVerdict(kind: lane.kind, provider: lane.kind.provider, percentUsed: lane.percentUsed,
                             percentElapsed: elapsedPct, resetsAt: lane.resetDate, status: status,
                             projectedCapAt: cap, resetsFirst: resetsFirst, projectionBasis: basis,
                             source: snapshot.source, fetchedAt: snapshot.fetchedAt,
                             verdict: verdictLine(lane: lane, elapsedPct: elapsedPct, status: status,
                                                  cap: cap, resetsFirst: resetsFirst, now: now))
    }

    static func verdictLine(lane: LaneUsage, elapsedPct: Int?, status: PaceStatus, cap: Date?, resetsFirst: Bool, now: Date) -> String {
        let name = lane.effectiveDisplayName
        let elapsedText = elapsedPct.map { "\($0)% elapsed" } ?? "no window"
        let resetText = "resets " + PaceFormatter.shortClock(lane.resetDate, now: now)
        switch status {
        case .tooEarly: return "\(name): \(lane.percentUsed)% used, too early to judge (\(resetText))"
        case .capped:   return "\(name): capped (\(resetText))"
        case .ahead, .onPace:
            if let cap { return "\(name): \(lane.percentUsed)% used, \(elapsedText), caps \(PaceFormatter.shortClock(cap, now: now)) at this rate (\(resetText))" }
            if resetsFirst { return "\(name): \(lane.percentUsed)% used, \(elapsedText), \(resetText) first" }
            return "\(name): \(lane.percentUsed)% used, \(elapsedText) (\(resetText))"
        }
    }

    static func pickHeadline(_ windows: [WindowVerdict]) -> WindowVerdict? {
        let ahead = windows.filter { $0.status == .ahead || $0.status == .capped }
        if !ahead.isEmpty {
            return ahead.min { a, b in
                switch (a.projectedCapAt, b.projectedCapAt) {
                case let (x?, y?): return x != y ? x < y : a.percentUsed > b.percentUsed
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.percentUsed > b.percentUsed
                }
            }
        }
        return windows.filter { $0.status != .tooEarly }
            .max { ($0.percentUsed - ($0.percentElapsed ?? 0)) < ($1.percentUsed - ($1.percentElapsed ?? 0)) }
    }

    static func advice(for headline: WindowVerdict?, laneState: LaneState?) -> String? {
        guard let h = headline, h.status == .ahead || h.status == .capped else { return nil }
        let other = h.provider == .claude ? "Codex" : "Claude"
        switch laneState {
        case .serving?:     return "move bulk/mechanical work to smithy (hearth:8085 local-heavy)"
        case .leasedAway?:  return "smithy GPU is leased; \(other) is the next lane"
        case .unreachable?, nil: return "smithy unreachable, check before routing there"
        }
    }
}
```

Add to `PaceFormatter.swift`:

```swift
/// "14:10" if same local day as `now`, else "Thu 14:10".
public static func shortClock(_ date: Date, now: Date) -> String {
    let cal = Calendar.current
    let f = DateFormatter(); f.locale = .current
    f.dateFormat = cal.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
    return f.string(from: date)
}
```

- [ ] **Step 4: Run** `make test` → PASS. If `testVerdictLineFormat` fails on locale, pin `f.locale = Locale(identifier: "en_US_POSIX")` in `shortClock`.

- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(core): pacing engine with burn-rate projection, headline and lane advice"`

---

### Task 3: Report store

**Files:**
- Create: `Sources/PaceCore/ReportStore.swift`
- Test: `Tests/PaceCoreTests/ReportStoreTests.swift`

**Interfaces:**
- Consumes: `PaceReport`.
- Produces: `ReportStore(directory:)`, `.defaultDirectory()`, `.save(_:)`, `.load()`, `.loadWithAge(now:)`, `ReportStore.staleAfter`.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import PaceCore

final class ReportStoreTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func report(at t: Date) -> PaceReport {
        PaceReport(generatedAt: t, headline: nil, advice: nil, windows: [], laneState: nil, burn: nil, providers: [], stale: false)
    }

    func testSaveIsAtomicAndReloads() throws {
        let dir = tmp(); let store = ReportStore(directory: dir)
        let r = report(at: Date(timeIntervalSince1970: 1_000))
        try store.save(r)
        XCTAssertEqual(store.load(), r)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("report.json.tmp").path))
    }

    func testLoadWithAgeMarksStaleAfterTenMinutes() throws {
        let store = ReportStore(directory: tmp())
        let t0 = Date(timeIntervalSince1970: 1_000)
        try store.save(report(at: t0))
        XCTAssertEqual(store.loadWithAge(now: t0.addingTimeInterval(599))?.isStale, false)
        XCTAssertEqual(store.loadWithAge(now: t0.addingTimeInterval(601))?.isStale, true)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(ReportStore(directory: tmp()).load())
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ReportStore {
    public static let staleAfter: TimeInterval = 10 * 60
    public let fileURL: URL

    public init(directory: URL) { fileURL = directory.appendingPathComponent("report.json") }

    public static func defaultDirectory() -> URL { SnapshotCache.defaultDirectory() }

    public struct Loaded: Equatable { public let report: PaceReport; public let age: TimeInterval; public let isStale: Bool }

    public func save(_ report: PaceReport) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(report)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }

    public func load() -> PaceReport? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(PaceReport.self, from: data)
    }

    public func loadWithAge(now: Date) -> Loaded? {
        guard let r = load() else { return nil }
        let age = now.timeIntervalSince(r.generatedAt)
        return Loaded(report: r, age: age, isStale: age > Self.staleAfter)
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `git commit -am "feat(core): atomic report store with stale flag"`

---

### Task 4: Merge codex-pace's parser and session source

**Files:**
- Create: `Sources/PaceCore/CodexRateLimitParser.swift` (copy of `~/codex-pace/Sources/PaceCore/CodexRateLimitParser.swift`)
- Create: `Sources/PaceCore/CodexSessionUsageSource.swift` (from `~/codex-pace/Sources/Pace/CodexSessionUsageSource.swift`, moved into PaceCore, made `public`)
- Test: `Tests/PaceCoreTests/CodexRateLimitParserTests.swift` (copy of codex-pace's), `Tests/PaceCoreTests/CodexSessionUsageSourceTests.swift`

**Interfaces:**
- Produces: `CodexRateLimitParser.snapshot(fromJSONLines:now:) -> UsageSnapshot?` (unchanged), `CodexSessionUsageSource(sessionsDirectory:fileManager:)` with `public func latestLanes(now: Date) -> [LaneUsage]?`.

- [ ] **Step 1: Copy files and tests**

```bash
cp ~/codex-pace/Sources/PaceCore/CodexRateLimitParser.swift ~/pace/Sources/PaceCore/
cp ~/codex-pace/Tests/PaceCoreTests/CodexRateLimitParserTests.swift ~/pace/Tests/PaceCoreTests/
cp ~/codex-pace/Sources/Pace/CodexSessionUsageSource.swift ~/pace/Sources/PaceCore/
```

In the copied parser, map the two windows onto the NEW kinds: the window whose `window_minutes` ≤ 600 → `.codexSession`; the other → `.codexWeek`. (codex-pace mapped them onto `.session`/`.allModelsWeek` with `displayNameOverride`; drop the override.) Update the copied tests' expected kinds accordingly.

- [ ] **Step 2: Failing test for the session source**

```swift
import XCTest
@testable import PaceCore

final class CodexSessionUsageSourceTests: XCTestCase {
    func testReadsLatestRateLimitsFromNewestFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let line = #"{"payload":{"rate_limits":{"primary":{"used_percent":42,"window_minutes":300,"resets_at":1800003600},"secondary":{"used_percent":90,"window_minutes":10080,"resets_at":1800300000}}}}"#
        try (line + "\n").write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let src = CodexSessionUsageSource(sessionsDirectory: dir)
        let lanes = src.latestLanes(now: now)!
        XCTAssertEqual(lanes.map(\.kind), [.codexSession, .codexWeek])
        XCTAssertEqual(lanes[0].percentUsed, 42)
        XCTAssertEqual(lanes[1].percentUsed, 90)
    }

    func testEmptyDirectoryReturnsNil() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNil(CodexSessionUsageSource(sessionsDirectory: dir).latestLanes(now: Date()))
    }
}
```

- [ ] **Step 3: Adapt `CodexSessionUsageSource`**

Change it from a `UsageSource` returning `Result<UsageSnapshot, FetchStatus>?` into:

```swift
public final class CodexSessionUsageSource: @unchecked Sendable {
    private let sessionsDirectory: URL
    private let fileManager: FileManager

    public init(sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex/sessions", isDirectory: true),
                fileManager: FileManager = .default) {
        self.sessionsDirectory = sessionsDirectory; self.fileManager = fileManager
    }

    /// Newest 12 .jsonl files by mtime, first one that yields rate limits wins.
    public func latestLanes(now: Date) -> [LaneUsage]? {
        guard let files = try? recentFiles(limit: 12) else { return nil }
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let snap = CodexRateLimitParser.snapshot(fromJSONLines: text, now: now) else { continue }
            return snap.lanes
        }
        return nil
    }
    // keep codex-pace's existing recursive enumerate + mtime sort as `recentFiles(limit:)`
}
```

- [ ] **Step 4: Run** `make test` → PASS. **Step 5: Commit** `git add -A && git commit -m "feat(codex): merge rate-limit parser and session-file source from codex-pace"`

---

### Task 5: Codex auth, usage client, normalizer, provider

**Files:**
- Create: `Sources/PaceCore/CodexAuthStore.swift`, `CodexUsageClient.swift`, `CodexUsageNormalizer.swift`, `CodexProvider.swift`
- Create: `Tests/PaceCoreTests/Fixtures/codex-wham-usage.json`
- Test: `Tests/PaceCoreTests/CodexUsageNormalizerTests.swift`, `CodexAuthStoreTests.swift`, `CodexProviderTests.swift`

**Interfaces:**
- Consumes: `LaneUsage`, `LaneKind.codexSession/.codexWeek`, `CodexSessionUsageSource.latestLanes(now:)`, `Provider`.
- Produces: `CodexAuth`, `CodexAuthStore(fileURL:)`, `CodexUsageClient(session:)`, `CodexUsageNormalizer.lanes(fromJSON:now:)`, `CodexProvider`.

- [ ] **Step 1: Fixture** `Tests/PaceCoreTests/Fixtures/codex-wham-usage.json` (shape from openusage's mapper; values invented):

```json
{
  "plan_type": "plus",
  "rate_limit": {
    "primary_window":   { "used_percent": 37, "reset_at": 1800003600, "reset_after_seconds": 3600,  "limit_window_seconds": 18000 },
    "secondary_window": { "used_percent": 100, "reset_at": 1800300000, "reset_after_seconds": 300000, "limit_window_seconds": 604800 }
  },
  "credits": { "balance": 0, "has_credits": false }
}
```

- [ ] **Step 2: Failing tests**

```swift
import XCTest
@testable import PaceCore

final class CodexUsageNormalizerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture() throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: "codex-wham-usage", withExtension: "json", subdirectory: "Fixtures")!)
    }
    func testMapsPrimaryAndSecondaryWindows() throws {
        let lanes = CodexUsageNormalizer.lanes(fromJSON: try fixture(), now: now)!
        XCTAssertEqual(lanes.map(\.kind), [.codexSession, .codexWeek])
        XCTAssertEqual(lanes[0].percentUsed, 37)
        XCTAssertEqual(lanes[0].windowLength, 18000)
        XCTAssertEqual(lanes[0].resetDate, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(lanes[1].percentUsed, 100)
        XCTAssertEqual(lanes[1].severity, .exceeded)
    }
    func testResetAfterSecondsUsedWhenResetAtMissing() {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":5,"reset_after_seconds":120,"limit_window_seconds":18000}}}"#.data(using: .utf8)!
        let lanes = CodexUsageNormalizer.lanes(fromJSON: json, now: now)!
        XCTAssertEqual(lanes[0].resetDate, now.addingTimeInterval(120))
    }
    func testGarbageReturnsNil() {
        XCTAssertNil(CodexUsageNormalizer.lanes(fromJSON: Data("nope".utf8), now: now))
        XCTAssertNil(CodexUsageNormalizer.lanes(fromJSON: Data("{}".utf8), now: now))
    }
}

final class CodexAuthStoreTests: XCTestCase {
    func write(_ json: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: u, atomically: true, encoding: .utf8); return u
    }
    func testReadsTokensBlock() throws {
        let u = try write(#"{"auth_mode":"chatgpt","tokens":{"access_token":"A","refresh_token":"R","account_id":"acct"},"last_refresh":"2026-09-01T00:00:00Z"}"#)
        let auth = CodexAuthStore(fileURL: u).load()!
        XCTAssertEqual(auth.accessToken, "A"); XCTAssertEqual(auth.refreshToken, "R"); XCTAssertEqual(auth.accountID, "acct")
    }
    func testMissingFileIsNil() {
        XCTAssertNil(CodexAuthStore(fileURL: URL(fileURLWithPath: "/nonexistent/auth.json")).load())
    }
    func testNeedsRefreshWhenJWTExpiresWithinFiveMinutes() throws {
        // header.payload.sig with payload {"exp": now+60}
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = Data(#"{"exp":1800000060}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let auth = CodexAuth(accessToken: "h.\(payload).s", refreshToken: "R", accountID: nil, lastRefresh: nil)
        XCTAssertTrue(CodexAuthStore.needsRefresh(auth, now: now))
        let far = Data(#"{"exp":1800009999}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertFalse(CodexAuthStore.needsRefresh(CodexAuth(accessToken: "h.\(far).s", refreshToken: "R", accountID: nil, lastRefresh: nil), now: now))
    }
}

final class CodexProviderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testFallsBackToSessionFilesWhenAuthMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"payload":{"rate_limits":{"primary":{"used_percent":11,"window_minutes":300,"resets_at":1800003600}}}}"#
            .write(to: dir.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        let p = CodexProvider(authStore: CodexAuthStore(fileURL: URL(fileURLWithPath: "/nonexistent")),
                              client: CodexUsageClient(session: .shared),
                              sessions: CodexSessionUsageSource(sessionsDirectory: dir))
        let s = await p.fetch(now: now)
        XCTAssertEqual(s.source, .localFallback)
        XCTAssertEqual(s.lanes.first?.percentUsed, 11)
        XCTAssertEqual(s.error, .needsLogin("run `codex login`"))
    }
}
```

- [ ] **Step 3: Run** → FAIL.

- [ ] **Step 4: Implement**

`CodexAuthStore.swift`:

```swift
import Foundation

public struct CodexAuth: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountID: String?
    public let lastRefresh: Date?
    public init(accessToken: String, refreshToken: String?, accountID: String?, lastRefresh: Date?) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.accountID = accountID; self.lastRefresh = lastRefresh
    }
}

public struct CodexAuthStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL = CodexAuthStore.defaultURL()) { self.fileURL = fileURL }

    public static func defaultURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    public func load() -> CodexAuth? {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else { return nil }
        let last = (obj["last_refresh"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return CodexAuth(accessToken: access, refreshToken: tokens["refresh_token"] as? String,
                         accountID: tokens["account_id"] as? String, lastRefresh: last)
    }

    /// Rewrites only the `tokens` block and `last_refresh`; every other key is preserved.
    public func save(_ auth: CodexAuth) throws {
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]) ?? [:]
        var tokens = (obj["tokens"] as? [String: Any]) ?? [:]
        tokens["access_token"] = auth.accessToken
        if let r = auth.refreshToken { tokens["refresh_token"] = r }
        if let a = auth.accountID { tokens["account_id"] = a }
        obj["tokens"] = tokens
        obj["last_refresh"] = ISO8601DateFormatter().string(from: auth.lastRefresh ?? Date())
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// JWT `exp` minus 5 min; if no exp, refresh when `last_refresh` is older than 8 days.
    public static func needsRefresh(_ auth: CodexAuth, now: Date) -> Bool {
        if let exp = jwtExpiry(auth.accessToken) { return now >= exp.addingTimeInterval(-300) }
        if let last = auth.lastRefresh { return now.timeIntervalSince(last) > 8 * 86400 }
        return false
    }

    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
```

`CodexUsageClient.swift` (URLs, client id, headers from openusage's `CodexUsageClient.swift`):

```swift
import Foundation

public struct CodexUsageClient: Sendable {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    let session: URLSession

    public init(session: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 10; return URLSession(configuration: c)
    }()) { self.session = session }

    public enum Failure: Error, Equatable { case unauthorized, http(Int), transport(String) }

    public func fetchUsage(auth: CodexAuth) async -> Result<Data, Failure> {
        var req = URLRequest(url: Self.usageURL)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Pace", forHTTPHeaderField: "User-Agent")
        if let a = auth.accountID { req.setValue(a, forHTTPHeaderField: "ChatGPT-Account-Id") }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return .failure(.unauthorized) }
            guard (200..<300).contains(code) else { return .failure(.http(code)) }
            return .success(data)
        } catch { return .failure(.transport(error.localizedDescription)) }
    }

    /// POST form grant_type=refresh_token. Returns the new auth (refresh token may rotate).
    public func refresh(auth: CodexAuth, now: Date) async -> CodexAuth? {
        guard let rt = auth.refreshToken else { return nil }
        var req = URLRequest(url: Self.refreshURL); req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&client_id=\(Self.clientID)&refresh_token=\(rt)".data(using: .utf8)
        guard let (data, resp) = try? await session.data(for: req),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else { return nil }
        return CodexAuth(accessToken: access, refreshToken: (obj["refresh_token"] as? String) ?? rt,
                         accountID: auth.accountID, lastRefresh: now)
    }
}
```

`CodexUsageNormalizer.swift`:

```swift
import Foundation

public enum CodexUsageNormalizer {
    /// Reads `rate_limit.primary_window` → `.codexSession`, `rate_limit.secondary_window` → `.codexWeek`.
    public static func lanes(fromJSON data: Data, now: Date) -> [LaneUsage]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = obj["rate_limit"] as? [String: Any] else { return nil }
        var out: [LaneUsage] = []
        for (key, kind) in [("primary_window", LaneKind.codexSession), ("secondary_window", .codexWeek)] {
            guard let w = rl[key] as? [String: Any], let lane = lane(kind: kind, window: w, now: now) else { continue }
            out.append(lane)
        }
        return out.isEmpty ? nil : out
    }

    static func lane(kind: LaneKind, window: [String: Any], now: Date) -> LaneUsage? {
        guard let usedAny = window["used_percent"] else { return nil }
        let used: Int
        if let d = usedAny as? Double { used = Int(d.rounded()) } else if let i = usedAny as? Int { used = i } else { return nil }
        let length = (window["limit_window_seconds"] as? Double).map { TimeInterval($0) }
        let reset: Date
        if let at = window["reset_at"] as? Double { reset = Date(timeIntervalSince1970: at) }
        else if let after = window["reset_after_seconds"] as? Double { reset = now.addingTimeInterval(after) }
        else { return nil }
        let sev: LaneSeverity = used >= 100 ? .exceeded : (used >= 90 ? .warning : .normal)
        return LaneUsage(kind: kind, percentUsed: min(max(used, 0), 100), resetDate: reset, windowLength: length, severity: sev)
    }
}
```

`CodexProvider.swift`:

```swift
import Foundation

public final class CodexProvider: Provider, @unchecked Sendable {
    public let id: ProviderID = .codex
    private let authStore: CodexAuthStore
    private let client: CodexUsageClient
    private let sessions: CodexSessionUsageSource
    private var lastGood: [LaneUsage] = []

    public init(authStore: CodexAuthStore = CodexAuthStore(), client: CodexUsageClient = CodexUsageClient(),
                sessions: CodexSessionUsageSource = CodexSessionUsageSource()) {
        self.authStore = authStore; self.client = client; self.sessions = sessions
    }

    public func fetch(now: Date) async -> ProviderSnapshot {
        guard var auth = authStore.load() else {
            return fallback(now: now, error: .needsLogin("run `codex login`"))
        }
        if CodexAuthStore.needsRefresh(auth, now: now), let fresh = await client.refresh(auth: auth, now: now) {
            auth = fresh; try? authStore.save(fresh)
        }
        switch await client.fetchUsage(auth: auth) {
        case .success(let data):
            guard let lanes = CodexUsageNormalizer.lanes(fromJSON: data, now: now) else {
                return fallback(now: now, error: .parseError("wham/usage shape changed"))
            }
            lastGood = lanes
            return ProviderSnapshot(provider: .codex, fetchedAt: now, source: .api, lanes: lanes)
        case .failure(.unauthorized):
            return fallback(now: now, error: .needsLogin("run `codex login`"))
        case .failure(let f):
            return fallback(now: now, error: .transient("\(f)"))
        }
    }

    private func fallback(now: Date, error: ProviderError) -> ProviderSnapshot {
        if let lanes = sessions.latestLanes(now: now) {
            return ProviderSnapshot(provider: .codex, fetchedAt: now, source: .localFallback, lanes: lanes, error: error)
        }
        return ProviderSnapshot(provider: .codex, fetchedAt: now, source: .cache, lanes: lastGood, error: error)
    }
}
```

- [ ] **Step 5: Run** `make test` → PASS. **Step 6: Commit** `git add -A && git commit -m "feat(codex): network usage source with auth refresh and session-file fallback"`

---

### Task 6: Smithy provider

**Files:**
- Create: `Sources/PaceCore/SmithyProvider.swift`
- Create: `Tests/PaceCoreTests/Fixtures/smithy-models-serving.json`, `smithy-lease-free.json`, `smithy-lease-held.json`
- Test: `Tests/PaceCoreTests/SmithyProviderTests.swift`

**Interfaces:**
- Produces: `SmithyProvider(schedulerModelsURL:leaseURL:session:)`, `SmithyProvider.map(models:lease:) -> LaneState`.

- [ ] **Step 1: Fixtures**

`smithy-models-serving.json` (trimmed from the live response):
```json
{"object":"list","data":[{"id":"local-fast","object":"model","smithy":{"lane":"local-fast","serving_now":true,"candidates":[]}},
 {"id":"local-heavy","object":"model","smithy":{"lane":"local-heavy","serving_now":true,"candidates":[{"node":"anvil","serves":"local-heavy","endpoint":"http://100.122.29.52:8000","status":"ready"}]}}]}
```
`smithy-lease-free.json`: `{"state":"free"}` · `smithy-lease-held.json`: `{"state":"held","pid":"4242","runner":"flux-train","started":"2026-09-04T10:00:00Z"}`

- [ ] **Step 2: Failing tests**

```swift
import XCTest
@testable import PaceCore

final class SmithyProviderTests: XCTestCase {
    func data(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
    }
    func testServingWhenLaneReadyAndLeaseFree() throws {
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: try data("smithy-lease-free")), .serving)
    }
    func testLeasedAwayWhenLeaseHeldOrWedged() throws {
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: try data("smithy-lease-held")), .leasedAway)
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: Data(#"{"state":"wedged"}"#.utf8)), .leasedAway)
    }
    func testUnreachableWhenLaneNotServingOrMalformed() throws {
        let notServing = Data(#"{"data":[{"id":"local-heavy","smithy":{"serving_now":false,"candidates":[]}}]}"#.utf8)
        XCTAssertEqual(SmithyProvider.map(models: notServing, lease: try data("smithy-lease-free")), .unreachable)
        XCTAssertEqual(SmithyProvider.map(models: Data("garbage".utf8), lease: try data("smithy-lease-free")), .unreachable)
        XCTAssertEqual(SmithyProvider.map(models: try data("smithy-models-serving"), lease: nil), .unreachable)
    }
    func testFetchAgainstDeadPortIsUnreachableNotServing() async {
        let p = SmithyProvider(schedulerModelsURL: URL(string: "http://127.0.0.1:1/v1/models")!,
                               leaseURL: URL(string: "http://127.0.0.1:1/lease")!)
        let s = await p.fetch(now: Date())
        XCTAssertEqual(s.laneState, .unreachable)
        XCTAssertNotNil(s.error)
    }
}
```

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct SmithyProvider: Provider {
    public let id: ProviderID = .smithy
    public static let defaultModelsURL = URL(string: "http://100.85.83.97:8085/v1/models")!
    public static let defaultLeaseURL = URL(string: "http://100.122.29.52:8001/lease")!
    let modelsURL: URL, leaseURL: URL, session: URLSession

    public init(schedulerModelsURL: URL = SmithyProvider.defaultModelsURL, leaseURL: URL = SmithyProvider.defaultLeaseURL,
                session: URLSession = { let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 5; return URLSession(configuration: c) }()) {
        modelsURL = schedulerModelsURL; self.leaseURL = leaseURL; self.session = session
    }

    public func fetch(now: Date) async -> ProviderSnapshot {
        async let m = get(modelsURL)
        async let l = get(leaseURL)
        let (models, lease) = await (m, l)
        let state = Self.map(models: models, lease: lease)
        var err: ProviderError? = nil
        if models == nil { err = .unreachable("scheduler hearth:8085 not answering") }
        else if lease == nil { err = .unreachable("anvil lease server :8001 not answering") }
        return ProviderSnapshot(provider: .smithy, fetchedAt: now, source: .api, lanes: [], laneState: state, error: err)
    }

    /// serving  = local-heavy serving_now AND a candidate with status "ready" AND lease state "free"
    /// leasedAway = lane answers but lease is "held" or "wedged"
    /// unreachable = anything else (either GET failed, malformed, or lane not serving)
    public static func map(models: Data?, lease: Data?) -> LaneState {
        guard let models, let lease,
              let root = try? JSONSerialization.jsonObject(with: models) as? [String: Any],
              let data = root["data"] as? [[String: Any]],
              let heavy = data.first(where: { ($0["id"] as? String) == "local-heavy" }),
              let smithy = heavy["smithy"] as? [String: Any],
              (smithy["serving_now"] as? Bool) == true,
              let cands = smithy["candidates"] as? [[String: Any]],
              cands.contains(where: { ($0["status"] as? String) == "ready" }),
              let leaseObj = try? JSONSerialization.jsonObject(with: lease) as? [String: Any],
              let state = leaseObj["state"] as? String else { return .unreachable }
        switch state {
        case "free": return .serving
        case "held", "wedged": return .leasedAway
        default: return .unreachable
        }
    }

    private func get(_ url: URL) async -> Data? {
        guard let (data, resp) = try? await session.data(from: url),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        return data
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `git add -A && git commit -m "feat(smithy): tri-state lane availability from scheduler + anvil lease server"`

---

### Task 7: Vendor openusage scanner and pricing code

**Files:**
- Create: `Sources/PaceCore/Vendor/OpenUsage/` (files below)
- Create: `Sources/PaceCore/Vendor/VENDORED.md`
- Create: `Sources/PaceCore/Vendor/OpenUsage/LICENSE` (openusage's MIT text)

**Interfaces:**
- Produces (as they exist upstream): `JSONLScanning`, `JSONLScanCachePersistence`, `DailyUsageAccumulator`, `ClaudeLogUsageScanner.scan(daysBack:now:pricing:) async -> LogUsageScan?`, `CodexLogUsageScanner.scan(...)`, `ModelPricing`, `ModelPricingStore`, `LogUsageScan`, `ModelUsageEntry`.

- [ ] **Step 1: Copy**

```bash
OU=/private/tmp/claude-501/-Users-ryanstern/98fb2511-b0b8-48a2-8dce-8544d287dbc8/scratchpad/openusage
# If the scratchpad is gone: git clone --depth 1 https://github.com/robinebers/openusage.git && git -C openusage checkout 8321283f61335b9e1d942c61f38de042a431a0a6
V=~/pace/Sources/PaceCore/Vendor/OpenUsage
mkdir -p $V/{Providers/Claude,Providers/Codex,Pricing,Models,Services,Support}
cp $OU/LICENSE $V/LICENSE
cp $OU/Sources/OpenUsage/Providers/{IncrementalJSONLScanner,JSONLScanCacheStore,JSONLScanCacheStore+Coordination,DailyUsageAccumulator}.swift $V/Providers/
cp $OU/Sources/OpenUsage/Providers/Claude/ClaudeLogUsageScanner.swift $V/Providers/Claude/
cp $OU/Sources/OpenUsage/Providers/Codex/{CodexLogFileParser,CodexLogUsageScanner,CodexLogUsageScanner+Pricing,CodexUsagePricing}.swift $V/Providers/Codex/
cp $OU/Sources/OpenUsage/Pricing/*.swift $V/Pricing/
cp $OU/Sources/OpenUsage/Models/DailyUsageSeries.swift $V/Models/
cp $OU/Sources/OpenUsage/Services/HTTPClient.swift $V/Services/
cp $OU/Sources/OpenUsage/Support/ProviderParse.swift $V/Support/
```

Then `swift build` and for every "cannot find type X" error, copy the single upstream file that defines X (the signature agent named `EnvironmentReading`, `TextFileAccessing`, `KeychainAccessing`, `LocalTextFileAccessor`, `SecurityKeychainAccessor`, `ProcessEnvironmentReader` under `Services/`, and `ProviderSnapshot`/`MetricLine` under `Models/`). If a dependency drags in UI or telemetry, stub the reference instead of copying: replace the call with a local no-op and record it in `VENDORED.md`. Do NOT copy `Telemetry*.swift`, `ICloud*`, `Views/`.

Name collision: upstream has `ProviderSnapshot` (Models). Ours (Task 1) has the same name. Rename the vendored one to `OUProviderSnapshot` with `sed -i '' 's/\bProviderSnapshot\b/OUProviderSnapshot/g'` across `Vendor/` only, and record it.

- [ ] **Step 2: Header every vendored file**

```bash
for f in $(find $V -name '*.swift'); do
  rel=${f#$V/}
  printf '// Vendored from robinebers/openusage@8321283f Sources/OpenUsage/%s (MIT).\n// Local edits listed in Sources/PaceCore/Vendor/VENDORED.md\n' "$rel" | cat - "$f" > "$f.new" && mv "$f.new" "$f"
done
```

- [ ] **Step 3: VENDORED.md**

```markdown
# Vendored code

Upstream: https://github.com/robinebers/openusage @ 8321283f61335b9e1d942c61f38de042a431a0a6 (MIT, see LICENSE).
Re-vendor by diffing each file against that commit, never by re-copying blind.

| Local path | Upstream path | Local edits |
|---|---|---|
| Providers/IncrementalJSONLScanner.swift | Sources/OpenUsage/Providers/IncrementalJSONLScanner.swift | header only |
| ... one row per file ... | | |
| Models/OUProviderSnapshot.swift | Sources/OpenUsage/Models/ProviderSnapshot.swift | renamed type ProviderSnapshot → OUProviderSnapshot (collides with PaceCore.ProviderSnapshot) |
```

Fill every row; every edit beyond the header gets a one-line reason.

- [ ] **Step 4: Compile smoke test** `Tests/PaceCoreTests/VendorSmokeTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class VendorSmokeTests: XCTestCase {
    func testClaudeLogScannerParsesFixtureDirectory() async throws {
        // Fixture: one Claude Code JSONL with two assistant messages carrying `usage` blocks, plus one garbage line.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/projects/p1")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let lines = [
          #"{"type":"assistant","timestamp":"\#(iso)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#,
          "this is not json",
          #"{"type":"assistant","timestamp":"\#(iso)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":3000,"output_tokens":100,"cache_read_input_tokens":500,"cache_creation_input_tokens":0}}}"#
        ].joined(separator: "\n")
        try lines.write(to: dir.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        let scan = await ClaudeLogUsageScanner(projectsRoot: dir.deletingLastPathComponent()).scan(daysBack: 2, now: now, pricing: ModelPricing.builtInFallback())
        XCTAssertNotNil(scan)
    }
}
```

Adjust the initializer to whatever `ClaudeLogUsageScanner.init` actually takes (the executor reads the vendored file); if it insists on a home-directory root, pass the temp dir as home. If `ModelPricing.builtInFallback()` does not exist, use the supplement-only constructor from `PricingSupplement.swift`. The point of this test is only "the vendored code compiles, runs, and returns non-nil on a real-shaped file with one garbage line".

- [ ] **Step 5: Run** `make test` → PASS. **Step 6: Commit** `git add -A && git commit -m "chore(vendor): openusage JSONL scanners, cache and pricing @8321283f (MIT)"`

---

### Task 8: Spend provider

**Files:**
- Create: `Sources/PaceCore/SpendProvider.swift`
- Test: `Tests/PaceCoreTests/SpendProviderTests.swift` (reuses the fixture technique from Task 7)

**Interfaces:**
- Consumes: vendored `ClaudeLogUsageScanner`, `CodexLogUsageScanner`, `LogUsageScan`, `ModelUsageEntry`, `ModelPricingStore`.
- Produces: `SpendProvider(claudeRoot:codexRoot:cacheDirectory:)`, `BurnSeries` in `ProviderSnapshot.burn`.

- [ ] **Step 1: Failing test**

```swift
final class SpendProviderTests: XCTestCase {
    func testHourlyBucketsAndUnparsedCount() async throws {
        // same fixture writer as VendorSmokeTests (factor into Tests/PaceCoreTests/FixtureWriter.swift)
        let (claudeRoot, now) = try FixtureWriter.claudeProjects(messagesAgoSeconds: [600, 700], garbageLines: 1)
        let p = SpendProvider(claudeRoot: claudeRoot,
                              codexRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                              cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let s = await p.fetch(now: now)
        XCTAssertEqual(s.provider, .spend)
        let burn = try XCTUnwrap(s.burn)
        XCTAssertEqual(burn.unparsedLines, 1)
        XCTAssertEqual(burn.tokens(for: .claude, from: now.addingTimeInterval(-3600), to: now), 4800)
        XCTAssertEqual(burn.hourly.filter { $0.provider == .codex }.count, 0)
    }
}
```

`FixtureWriter.claudeProjects(messagesAgoSeconds:garbageLines:)` writes the same two-message JSONL as Task 7 (1000+200+0+0 and 3000+100+500+0 = 4800 tokens) and returns `(root, now)`.

- [ ] **Step 2: Implement**

```swift
import Foundation

public final class SpendProvider: Provider, @unchecked Sendable {
    public let id: ProviderID = .spend
    let claudeRoot: URL, codexRoot: URL, cacheDirectory: URL
    private let pricing: ModelPricingStore

    public init(claudeRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
                codexRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
                cacheDirectory: URL = SnapshotCache.defaultDirectory().appendingPathComponent("log-scan-cache")) {
        self.claudeRoot = claudeRoot; self.codexRoot = codexRoot; self.cacheDirectory = cacheDirectory
        self.pricing = ModelPricingStore(cacheDirectory: cacheDirectory)   // vendored; daily refresh, supplement fallback
    }

    public func fetch(now: Date) async -> ProviderSnapshot {
        let model = await pricing.current()
        async let c = ClaudeLogUsageScanner(root: claudeRoot, cacheDirectory: cacheDirectory).scan(daysBack: 30, now: now, pricing: model)
        async let x = CodexLogUsageScanner(root: codexRoot, cacheDirectory: cacheDirectory).scan(daysBack: 30, now: now, pricing: model)
        let (claude, codex) = await (c, x)
        var hourly: [HourBucket] = [], daily: [DayBucket] = [], unparsed = 0
        for (scan, pid) in [(claude, ProviderID.claude), (codex, .codex)] {
            guard let scan else { continue }
            unparsed += scan.unparsedLineCount
            hourly += Self.hourly(from: scan, provider: pid, now: now)
            daily += Self.daily(from: scan, provider: pid)
        }
        let burn = BurnSeries(hourly: hourly, daily: daily, unparsedLines: unparsed)
        let err: ProviderError? = (claude == nil && codex == nil) ? .parseError("no session logs readable") : nil
        return ProviderSnapshot(provider: .spend, fetchedAt: now, source: .localFallback, lanes: [], burn: burn, error: err)
    }

    /// `scan.entries` is `[ModelUsageEntry]` with `timestamp: Date`, `totalTokens: Int`, `costUSD: Double`
    /// (names per the vendored DailyUsageSeries.swift; if upstream uses different property names, adapt here, not there).
    static func hourly(from scan: LogUsageScan, provider: ProviderID, now: Date) -> [HourBucket] {
        let floor = now.addingTimeInterval(-6 * 3600)
        let grouped = Dictionary(grouping: scan.entries.filter { $0.timestamp >= floor }) { e -> Date in
            Date(timeIntervalSince1970: (e.timestamp.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        }
        return grouped.map { start, es in
            HourBucket(start: start, provider: provider,
                       tokens: es.reduce(0) { $0 + $1.totalTokens }, costUSD: es.reduce(0) { $0 + $1.costUSD })
        }.sorted { $0.start < $1.start }
    }

    static func daily(from scan: LogUsageScan, provider: ProviderID) -> [DayBucket] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        let grouped = Dictionary(grouping: scan.entries) { f.string(from: $0.timestamp) }
        return grouped.map { day, es in
            DayBucket(day: day, provider: provider,
                      tokens: es.reduce(0) { $0 + $1.totalTokens }, costUSD: es.reduce(0) { $0 + $1.costUSD })
        }.sorted { $0.day < $1.day }
    }
}
```

If the vendored `LogUsageScan` aggregates per DAY only (no per-message `entries`), add a per-message `entries` array to the vendored `DailyUsageAccumulator` (append `ModelUsageEntry(timestamp:model:totalTokens:costUSD:)` on every accepted line) and record the edit in `VENDORED.md`. Same for `unparsedLineCount` if absent: count `catch` hits in the scanner's per-line decode and expose them as `LogUsageScan.unparsedLineCount`.

- [ ] **Step 3: Run** → PASS. **Step 4: Commit** `git add -A && git commit -m "feat(spend): burn series from Claude and Codex session logs"`

---

### Task 9: Claude provider, Keychain move, scraper deletion

**Files:**
- Move: `Sources/Pace/KeychainCredentialStore.swift` → `Sources/PaceCore/KeychainCredentialStore.swift` (make `public`)
- Move: `Sources/Pace/ApiUsageSource.swift` → `Sources/PaceCore/ApiUsageSource.swift` (make `public`)
- Create: `Sources/PaceCore/ClaudeProvider.swift`
- Delete: `Sources/Pace/ScrapeUsageSource.swift`, `Sources/Pace/UsageFetcher.swift`, `Sources/Pace/UsageSource.swift`, `Sources/PaceCore/UsagePanelTextExtractor.swift`, `Sources/PaceCore/UsageParser.swift`, `Tests/PaceCoreTests/UsagePanelTextExtractorTests.swift`, `Tests/PaceCoreTests/UsageParserTests.swift`
- Test: `Tests/PaceCoreTests/ClaudeProviderTests.swift`

**Interfaces:**
- Consumes: `ApiUsageSource.fetch() async -> Result<UsageSnapshot, FetchStatus>?`, `KeychainCredentialStore.read(now:)`.
- Produces: `ClaudeProvider(source:)` where `source` is a `ClaudeUsageFetching` protocol so the test can inject.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import PaceCore

private struct FakeSource: ClaudeUsageFetching {
    let result: Result<UsageSnapshot, FetchStatus>?
    func fetch() async -> Result<UsageSnapshot, FetchStatus>? { result }
}

final class ClaudeProviderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testSuccessMapsLanesAndOverage() async {
        let lanes = [LaneUsage(kind: .session, percentUsed: 10, resetDate: now.addingTimeInterval(3600), windowLength: 18000)]
        let snap = UsageSnapshot(lanes: lanes, extraUsage: ExtraUsage(dollarsUsed: 12.5, isEnabled: true), fetchedAt: now)
        let s = await ClaudeProvider(source: FakeSource(result: .success(snap))).fetch(now: now)
        XCTAssertEqual(s.source, .api); XCTAssertNil(s.error)
        XCTAssertEqual(s.lanes.map(\.kind), [.session, .overage])
        XCTAssertEqual(s.lanes[1].percentUsed, 12)     // ⚠ divisor unverified (spec §8) — label in UI
    }
    func testTokenExpiredIsNeedsLoginWithCache() async {
        let p = ClaudeProvider(source: FakeSource(result: .failure(.tokenExpired)))
        let s = await p.fetch(now: now)
        XCTAssertEqual(s.error, .needsLogin("open Claude Code to refresh sign-in"))
        XCTAssertEqual(s.source, .cache)
    }
}
```

- [ ] **Step 2: Implement**

```swift
public protocol ClaudeUsageFetching: Sendable { func fetch() async -> Result<UsageSnapshot, FetchStatus>? }
extension ApiUsageSource: ClaudeUsageFetching {}

public final class ClaudeProvider: Provider, @unchecked Sendable {
    public let id: ProviderID = .claude
    private let source: ClaudeUsageFetching
    private var lastGood: [LaneUsage] = []
    public init(source: ClaudeUsageFetching = ApiUsageSource()) { self.source = source }

    public func fetch(now: Date) async -> ProviderSnapshot {
        switch await source.fetch() {
        case .success(let snap)?:
            var lanes = snap.lanes
            if let x = snap.extraUsage, x.isEnabled {
                lanes.append(LaneUsage(kind: .overage, percentUsed: Int(x.dollarsUsed.rounded()), resetDate: .distantFuture, windowLength: nil))
            }
            lastGood = lanes
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .api, lanes: lanes)
        case .failure(.tokenExpired)?, .failure(.needsLogin)?:
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: lastGood, error: .needsLogin("open Claude Code to refresh sign-in"))
        case .failure(let f)?:
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: lastGood, error: .transient("\(f)"))
        case nil:
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: lastGood, error: .transient("no fetch"))
        }
    }
}
```

Overage: `ExtraUsage.dollarsUsed` is what v2 already parses; the "÷100" divisor question is about the raw `used_credits` field inside `ApiUsageNormalizer` and stays flagged. `.overage` lanes have `windowLength: nil` so `PaceCalculator.status` returns `.onPace` and the engine never projects them.

- [ ] **Step 3: Delete the scraper**, remove `DataSourceMode.browser` and every reference in `Sources/Pace` (the app will not compile until Task 13 rewrites `AppState`; that is expected — make `Sources/Pace` compile by temporarily reducing `AppState` to the v2 API path only, or comment the browser branches out; Task 13 replaces the file).

- [ ] **Step 4: Run** `make test` → PASS, `swift build` → PASS. **Step 5: Commit** `git add -A && git commit -m "refactor(claude): provider over the OAuth usage client; delete WKWebView scraper"`

---

### Task 10: Refresh coordinator

**Files:**
- Create: `Sources/PaceCore/RefreshCoordinator.swift`
- Test: `Tests/PaceCoreTests/RefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: `Provider`, `PacingEngine.report(snapshots:now:)`, `ReportStore`.
- Produces: `RefreshCoordinator(providers:store:clock:)`, `func refresh() async -> PaceReport`, `var latest: PaceReport?`, `func start(interval:smithyInterval:)`, `func stop()`, `onReport: (@Sendable (PaceReport) -> Void)?`.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import PaceCore

private struct StubProvider: Provider {
    let id: ProviderID; let snapshot: ProviderSnapshot
    func fetch(now: Date) async -> ProviderSnapshot { snapshot }
}

final class RefreshCoordinatorTests: XCTestCase {
    func testRefreshRunsAllProvidersAndPersists() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: now.addingTimeInterval(9000), windowLength: 18000)
        let providers: [any Provider] = [
            StubProvider(id: .claude, snapshot: ProviderSnapshot(provider: .claude, fetchedAt: now, source: .api, lanes: [lane])),
            StubProvider(id: .smithy, snapshot: ProviderSnapshot(provider: .smithy, fetchedAt: now, source: .api, lanes: [], laneState: .serving))
        ]
        let c = RefreshCoordinator(providers: providers, store: ReportStore(directory: dir), clock: { now })
        let r = await c.refresh()
        XCTAssertEqual(r.headline?.kind, .session)
        XCTAssertEqual(r.advice, "move bulk/mechanical work to smithy (hearth:8085 local-heavy)")
        XCTAssertEqual(ReportStore(directory: dir).load(), r)
        XCTAssertEqual(c.latest, r)
    }

    func testOneFailingProviderDoesNotBlankOthers() async {
        let now = Date()
        let lane = LaneUsage(kind: .codexSession, percentUsed: 5, resetDate: now.addingTimeInterval(9000), windowLength: 18000)
        let providers: [any Provider] = [
            StubProvider(id: .claude, snapshot: ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: [], error: .transient("500"))),
            StubProvider(id: .codex, snapshot: ProviderSnapshot(provider: .codex, fetchedAt: now, source: .api, lanes: [lane]))
        ]
        let c = RefreshCoordinator(providers: providers, store: ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), clock: { now })
        let r = await c.refresh()
        XCTAssertEqual(r.windows.map(\.kind), [.codexSession])
        XCTAssertTrue(r.stale)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public final class RefreshCoordinator: @unchecked Sendable {
    private let providers: [any Provider]
    private let store: ReportStore
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var _latest: PaceReport?
    private var mainTask: Task<Void, Never>?
    private var smithyTask: Task<Void, Never>?
    private var lastSnapshots: [ProviderID: ProviderSnapshot] = [:]
    public var onReport: (@Sendable (PaceReport) -> Void)?

    public var latest: PaceReport? { lock.withLock { _latest } }

    public init(providers: [any Provider], store: ReportStore = ReportStore(directory: ReportStore.defaultDirectory()),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.providers = providers; self.store = store; self.clock = clock
        _latest = store.load()
    }

    public static func live() -> RefreshCoordinator {
        RefreshCoordinator(providers: [ClaudeProvider(), CodexProvider(), SmithyProvider(), SpendProvider()])
    }

    @discardableResult
    public func refresh(only: Set<ProviderID>? = nil) async -> PaceReport {
        let now = clock()
        let targets = providers.filter { only?.contains($0.id) ?? true }
        let fresh = await withTaskGroup(of: ProviderSnapshot.self) { group -> [ProviderSnapshot] in
            for p in targets { group.addTask { await p.fetch(now: now) } }
            var out: [ProviderSnapshot] = []; for await s in group { out.append(s) }; return out
        }
        let merged: [ProviderSnapshot] = lock.withLock {
            for s in fresh { lastSnapshots[s.provider] = s }
            return Array(lastSnapshots.values).sorted { $0.provider.rawValue < $1.provider.rawValue }
        }
        let report = PacingEngine.report(snapshots: merged, now: now)
        try? store.save(report)
        lock.withLock { _latest = report }
        onReport?(report)
        return report
    }

    public func start(interval: TimeInterval = 120, smithyInterval: TimeInterval = 60) {
        stop()
        mainTask = Task { [weak self] in
            while !Task.isCancelled { await self?.refresh(); try? await Task.sleep(nanoseconds: UInt64(interval * 1e9)) }
        }
        smithyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(smithyInterval * 1e9))
            while !Task.isCancelled { await self?.refresh(only: [.smithy]); try? await Task.sleep(nanoseconds: UInt64(smithyInterval * 1e9)) }
        }
    }

    public func stop() { mainTask?.cancel(); smithyTask?.cancel(); mainTask = nil; smithyTask = nil }
}
```

- [ ] **Step 3: Run** → PASS. **Step 4: Commit** `git add -A && git commit -m "feat(core): refresh coordinator joining providers into the report"`

---

### Task 11: Loopback server

**Files:**
- Create: `Sources/PaceCore/LoopbackServer.swift`
- Test: `Tests/PaceCoreTests/LoopbackServerTests.swift`

**Interfaces:**
- Consumes: `ReportStore`, `RefreshCoordinator` (via a `@Sendable () -> PaceReport?` closure and a refresh closure).
- Produces: `LoopbackServer(port:report:refresh:)`, `start() throws`, `stop()`. Routes: `GET /v1/report` → 200 JSON; `POST /v1/refresh` → runs refresh, 200 JSON; anything else 404; non-loopback binds impossible by construction.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import PaceCore

final class LoopbackServerTests: XCTestCase {
    func testServesReportAnd404sElsewhere() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = PaceReport(generatedAt: now, headline: nil, advice: nil, windows: [], laneState: .serving, burn: nil, providers: [], stale: false)
        let server = LoopbackServer(port: 0, report: { report }, refresh: { report })   // port 0 = ephemeral, exposes .boundPort
        try server.start()
        defer { server.stop() }
        let port = try await server.boundPort()
        let (data, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/report")!)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(PaceReport.self, from: data), report)
        let (_, r404) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/nope")!)
        XCTAssertEqual((r404 as? HTTPURLResponse)?.statusCode, 404)
    }
}
```

- [ ] **Step 2: Implement** with `Network.framework`:

```swift
import Foundation
import Network

public final class LoopbackServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 6737
    private let port: UInt16
    private let report: @Sendable () -> PaceReport?
    private let refresh: @Sendable () async -> PaceReport?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pace.loopback")
    private var active = 0
    private let maxConnections = 8

    public init(port: UInt16 = LoopbackServer.defaultPort, report: @escaping @Sendable () -> PaceReport?,
                refresh: @escaping @Sendable () async -> PaceReport?) {
        self.port = port; self.report = report; self.refresh = refresh
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        l.start(queue: queue)
        listener = l
    }

    public func stop() { listener?.cancel(); listener = nil }

    public func boundPort() async throws -> UInt16 {
        for _ in 0..<50 {
            if let p = listener?.port?.rawValue, p != 0 { return p }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw URLError(.cannotConnectToHost)
    }

    private func handle(_ conn: NWConnection) {
        guard active < maxConnections else { conn.cancel(); return }
        active += 1
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let head = String(decoding: data ?? Data(), as: UTF8.self)
            let line = head.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            let method = parts.count > 0 ? String(parts[0]) : ""
            let path = parts.count > 1 ? String(parts[1]) : ""
            Task {
                let response: (Int, Data)
                switch (method, path) {
                case ("GET", "/v1/report"):  response = self.encode(self.report())
                case ("POST", "/v1/refresh"): response = self.encode(await self.refresh())
                default: response = (404, Data("{\"error\":\"not found\"}".utf8))
                }
                self.send(conn, status: response.0, body: response.1)
            }
        }
    }

    private func encode(_ r: PaceReport?) -> (Int, Data) {
        guard let r else { return (503, Data("{\"error\":\"no report yet\"}".utf8)) }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        return (200, (try? enc.encode(r)) ?? Data("{}".utf8))
    }

    private func send(_ conn: NWConnection, status: Int, body: Data) {
        let reason = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Service Unavailable")
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        head.reserveCapacity(head.count + body.count)
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] _ in
            conn.cancel(); self?.queue.async { self?.active -= 1 }
        })
    }
}
```

- [ ] **Step 3: Run** → PASS. **Step 4: Commit** `git add -A && git commit -m "feat(core): loopback report server on 127.0.0.1:6737"`

---

### Task 12: CLI

**Files:**
- Replace: `Sources/PaceCLI/main.swift`
- Modify: `Makefile` (add `cli` and `install-cli` targets)
- Test: manual (executables are not unit-tested; the formatting function lives in PaceCore and IS tested)
- Create: `Sources/PaceCore/ReportTextFormatter.swift`, `Tests/PaceCoreTests/ReportTextFormatterTests.swift`

**Interfaces:**
- Produces: `ReportTextFormatter.render(_:now:) -> String`; binary `pace [--json] [--refresh]`.

- [ ] **Step 1: Failing test**

```swift
final class ReportTextFormatterTests: XCTestCase {
    func testRendersHeadlineAdviceAndWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let v = WindowVerdict(kind: .fableWeek, provider: .claude, percentUsed: 71, percentElapsed: 54, resetsAt: now.addingTimeInterval(86400),
                              status: .ahead, projectedCapAt: now.addingTimeInterval(3600), resetsFirst: false, projectionBasis: .burnRate,
                              source: .api, fetchedAt: now, verdict: "Fable · week: 71% used, 54% elapsed, caps 14:10 at this rate (resets Fri 09:00)")
        let r = PaceReport(generatedAt: now, headline: v, advice: "move bulk/mechanical work to smithy (hearth:8085 local-heavy)",
                           windows: [v], laneState: .serving, burn: nil,
                           providers: [ProviderStatus(provider: .claude, source: .api, fetchedAt: now, error: nil)], stale: false)
        let text = ReportTextFormatter.render(r, now: now)
        XCTAssertTrue(text.contains("HEADLINE  Fable · week: 71% used"))
        XCTAssertTrue(text.contains("ADVICE    move bulk/mechanical work to smithy"))
        XCTAssertTrue(text.contains("smithy    serving"))
        XCTAssertTrue(text.contains("claude    api"))
    }
}
```

- [ ] **Step 2: Implement formatter**

```swift
public enum ReportTextFormatter {
    public static func render(_ r: PaceReport, now: Date) -> String {
        var lines: [String] = []
        lines.append("pace  \(PaceFormatter.ageLabel(since: r.generatedAt, now: now))\(r.stale ? "  [STALE]" : "")")
        if let h = r.headline { lines.append("HEADLINE  \(h.verdict)") }
        if let a = r.advice { lines.append("ADVICE    \(a)") }
        lines.append("")
        for w in r.windows { lines.append("  \(w.status == .ahead || w.status == .capped ? "↑" : " ") \(w.verdict)  [\(w.source.rawValue)]") }
        lines.append("")
        lines.append("smithy    \(r.laneState?.rawValue ?? "unknown")")
        for p in r.providers where p.provider != .smithy {
            lines.append("\(p.provider.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(p.source.rawValue)\(p.error.map { "  ⚠ \($0)" } ?? "")")
        }
        if let b = r.burn, b.unparsedLines > 0 { lines.append("spend     \(b.unparsedLines) unparsed log lines") }
        return lines.joined(separator: "\n") + "\n"
    }
}
```

- [ ] **Step 3: main.swift**

```swift
import Foundation
import PaceCore

let args = CommandLine.arguments.dropFirst()
let wantJSON = args.contains("--json")
let wantRefresh = args.contains("--refresh")
if args.contains("--help") || args.contains("-h") {
    print("usage: pace [--json] [--refresh]\n  --json     print report.json verbatim\n  --refresh  force a fetch via the running app (127.0.0.1:6737), else fetch in-process")
    exit(0)
}

func fetchViaApp(path: String, method: String) async -> Data? {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(LoopbackServer.defaultPort)\(path)")!)
    req.httpMethod = method; req.timeoutInterval = 30
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return data
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    let now = Date()
    var report: PaceReport? = nil
    if wantRefresh {
        if let data = await fetchViaApp(path: "/v1/refresh", method: "POST") {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            report = try? dec.decode(PaceReport.self, from: data)
        } else {
            report = await RefreshCoordinator.live().refresh()
        }
    } else {
        report = ReportStore(directory: ReportStore.defaultDirectory()).load()
        if report == nil { report = await RefreshCoordinator.live().refresh() }
    }
    guard let report else { FileHandle.standardError.write(Data("pace: no report available\n".utf8)); exit(2) }
    if wantJSON {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        print(String(decoding: try! enc.encode(report), as: UTF8.self))
    } else {
        print(ReportTextFormatter.render(report, now: now), terminator: "")
    }
    semaphore.signal()
}
semaphore.wait()
```

- [ ] **Step 4: Makefile additions**

```makefile
cli:
	swift build -c release --product pace-cli

install-cli: cli
	mkdir -p "$$HOME/.local/bin"
	cp .build/release/pace-cli "$$HOME/.local/bin/pace"
	@echo "Installed ~/.local/bin/pace"
```

- [ ] **Step 5: Run** `make test && make cli && .build/release/pace-cli --help` → PASS, usage printed. **Step 6: Commit** `git add -A && git commit -m "feat(cli): pace one-shot report (text/json, --refresh via loopback)"`

---

### Task 13: Menubar app

**Files:**
- Rewrite: `Sources/Pace/AppState.swift`, `Sources/Pace/MenuView.swift`, `Sources/Pace/IconRenderer.swift` (only the input type changes), `Sources/Pace/PreferencesView.swift`, `Sources/Pace/PaceApp.swift`
- Keep: `Sources/Pace/PaceNotifier.swift` (unused in v1, leave), `Info.plist`

**Interfaces:**
- Consumes: `RefreshCoordinator.live()`, `LoopbackServer`, `PaceReport`, `WindowVerdict`, `IconGeometry`.

- [ ] **Step 1: AppState**

```swift
import SwiftUI
import PaceCore

@Observable @MainActor
final class AppState {
    private(set) var report: PaceReport?
    private(set) var lastRefreshAt: Date?
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval"); coordinator.start(interval: refreshInterval) }
    }
    var pinnedKind: LaneKind? {   // nil = headline (auto)
        didSet { UserDefaults.standard.set(pinnedKind?.rawValue, forKey: "pinnedKind") }
    }
    let coordinator: RefreshCoordinator
    private let server: LoopbackServer

    init(coordinator: RefreshCoordinator? = nil) {
        let c = coordinator ?? RefreshCoordinator.live()
        self.coordinator = c
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        refreshInterval = stored > 0 ? stored : 120
        pinnedKind = UserDefaults.standard.string(forKey: "pinnedKind").flatMap(LaneKind.init(rawValue:))
        report = c.latest
        server = LoopbackServer(report: { [weak c] in c?.latest }, refresh: { [weak c] in await c?.refresh() })
        c.onReport = { [weak self] r in Task { @MainActor in self?.report = r; self?.lastRefreshAt = r.generatedAt } }
        try? server.start()
        c.start(interval: refreshInterval)
    }

    func refreshNow() { Task { await coordinator.refresh() } }

    /// What the menubar pin shows.
    var pinned: WindowVerdict? {
        guard let r = report else { return nil }
        if let k = pinnedKind, let w = r.windows.first(where: { $0.kind == k }) { return w }
        return r.headline
    }
    var isStale: Bool {
        guard let r = report else { return true }
        return r.stale || Date().timeIntervalSince(r.generatedAt) > ReportStore.staleAfter
    }
}
```

- [ ] **Step 2: PaceApp**

```swift
@main
struct PaceApp: App {
    @State private var state = AppState()
    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            Image(nsImage: IconRenderer.image(for: state.pinned, stale: state.isStale))
        }
        .menuBarExtraStyle(.window)
        Settings { PreferencesView(state: state) }
    }
}
```

`IconRenderer.image(for:stale:)`: keep v2's drawing (mini-bar + percent text), red fill when `status == .ahead || .capped`, grey when `stale`, dash when `nil`. Only the input type changes from `[PaceReading]` to `WindowVerdict?`.

- [ ] **Step 3: MenuView**

```swift
struct MenuView: View {
    @Bindable var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = state.report {
                if let h = r.headline { Text(h.verdict).font(.headline).foregroundStyle(h.status == .ahead || h.status == .capped ? .red : .primary) }
                if let a = r.advice { Text(a).font(.subheadline) }
                Divider()
                ForEach([ProviderID.claude, .codex], id: \.self) { p in
                    let ws = r.windows.filter { $0.provider == p }
                    if !ws.isEmpty {
                        Text(p == .claude ? "Claude" : "Codex").font(.caption).foregroundStyle(.secondary)
                        ForEach(ws, id: \.kind) { w in WindowRow(w: w) }
                    }
                }
                Divider()
                HStack { Text("smithy"); Spacer(); Text(laneLabel(r.laneState)).foregroundStyle(r.laneState == .serving ? .green : .orange) }
                if let b = r.burn, b.unparsedLines > 0 { Text("\(b.unparsedLines) unparsed log lines").font(.caption).foregroundStyle(.orange) }
                ForEach(r.providers.filter { $0.error != nil }, id: \.provider) { p in
                    Text("\(p.provider.rawValue): \(p.error!)").font(.caption).foregroundStyle(.orange)
                }
            } else { Text("No data yet").foregroundStyle(.secondary) }
            Divider()
            HStack {
                Text(state.report.map { PaceFormatter.ageLabel(since: $0.generatedAt, now: Date()) } ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { state.refreshNow() }.keyboardShortcut("r")
                SettingsLink { Text("Preferences") }
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }.padding(12).frame(width: 380)
    }
    func laneLabel(_ s: LaneState?) -> String {
        switch s { case .serving?: return "serving"; case .leasedAway?: return "GPU leased"; default: return "unreachable" }
    }
}

struct WindowRow: View {
    let w: WindowVerdict
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(w.kind.displayName)
                Spacer()
                Text("\(w.percentUsed)%").monospacedDigit()
                Text(w.source.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.quaternary)
                    Rectangle().fill(w.status == .ahead || w.status == .capped ? .red : .accentColor).frame(width: g.size.width * CGFloat(w.percentUsed) / 100)
                    if let e = w.percentElapsed { Rectangle().fill(.primary).frame(width: 1).offset(x: g.size.width * CGFloat(e) / 100) }
                }
            }.frame(height: 6)
            Text(w.verdict).font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 4: PreferencesView** (keep v2's launch-at-login `SMAppService` toggle code as-is; replace the rest):

```swift
struct PreferencesView: View {
    @Bindable var state: AppState
    var body: some View {
        Form {
            LaunchAtLoginToggle()   // v2's existing SMAppService-backed view
            Picker("Refresh every", selection: $state.refreshInterval) {
                Text("1 min").tag(TimeInterval(60)); Text("2 min").tag(TimeInterval(120)); Text("5 min").tag(TimeInterval(300))
            }
            Picker("Menubar pin", selection: $state.pinnedKind) {
                Text("Headline (auto)").tag(LaneKind?.none)
                ForEach(LaneKind.allCases, id: \.self) { k in Text(k.displayName).tag(LaneKind?.some(k)) }
            }
            Text("Overage percent is an unverified ÷100 of raw credits (see TODOS.md).").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 360)
    }
}
```

12/24h follows the system locale via `PaceFormatter.shortClock` (no preference in v1).

- [ ] **Step 5: Build, install, run** `make install && open ~/Applications/Pace.app`. Confirm the popover shows all four providers. `curl -s 127.0.0.1:6737/v1/report | head -c 300`.

- [ ] **Step 6: Commit** `git add -A && git commit -m "feat(app): v3 menubar over the unified report"`

---

### Task 14: Statusline segment

**Files:**
- Create: `Scripts/pace-statusline-segment.sh`
- Modify: `~/.claude/hooks/gsd-statusline.js` around line 450 (`process.stdout.write(composeStatusline(...))`)
- Modify: `Makefile` (`install-statusline` target copies the script to `~/.claude/hooks/`)

- [ ] **Step 1: Script**

```bash
#!/bin/bash
# pace-statusline-segment.sh — one short segment for the Claude Code statusline.
# Reads ~/Library/Application Support/Pace/report.json. No network. Prints nothing if absent.
set -u
F="$HOME/Library/Application Support/Pace/report.json"
[ -r "$F" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
now=$(date +%s)
gen=$(jq -r '.generatedAt' "$F" 2>/dev/null) || exit 0
gen_s=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$gen" +%s 2>/dev/null || echo 0)
if [ $((now - gen_s)) -gt 600 ]; then printf 'pace stale'; exit 0; fi
jq -r '
  def short: if .kind=="fableWeek" then "Fable wk" elif .kind=="allModelsWeek" then "All wk" elif .kind=="session" then "5h"
             elif .kind=="codexSession" then "Codex 5h" elif .kind=="codexWeek" then "Codex wk" else .kind end;
  def arrow: if .status=="ahead" or .status=="capped" then "↑" else "" end;
  def cap: if .projectedCapAt then " caps " + (.projectedCapAt | sub("\\.[0-9]+";"") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | localtime | strftime("%H:%M")) else "" end;
  ([.headline | select(.!=null) | (short + " " + (.percentUsed|tostring) + "%" + arrow + cap)]
   + [.windows[] | select(.kind=="session") | select(.kind != (.headline.kind // "")) | ("5h " + (.percentUsed|tostring) + "%")]
  ) | join(" · ")' "$F" 2>/dev/null | tr -d '\n'
```

- [ ] **Step 2: Hook line** in `gsd-statusline.js`, immediately before the `process.stdout.write(composeStatusline(...))` call at line 450:

```js
    // pace v3 segment (reads report.json; never network; silent if absent)
    let paceSeg = '';
    try {
      const { execFileSync } = require('child_process');
      const seg = execFileSync(path.join(process.env.HOME, '.claude/hooks/pace-statusline-segment.sh'), { timeout: 800, encoding: 'utf8' }).trim();
      if (seg) paceSeg = ` │ \x1b[2m${seg}\x1b[0m`;
    } catch (e) { /* never break the statusline */ }
    lastCmdSuffix = paceSeg + lastCmdSuffix;
```

- [ ] **Step 3: Makefile**

```makefile
install-statusline:
	cp Scripts/pace-statusline-segment.sh "$$HOME/.claude/hooks/pace-statusline-segment.sh"
	chmod +x "$$HOME/.claude/hooks/pace-statusline-segment.sh"
```

- [ ] **Step 4: Verify** `make install-statusline && ~/.claude/hooks/pace-statusline-segment.sh; echo` prints a segment; `echo '{"model":{"display_name":"x"},"workspace":{"current_dir":"/tmp"}}' | node ~/.claude/hooks/gsd-statusline.js` shows it. Open a fresh `claude` session and confirm the segment is visible. Quit Pace.app, wait 10 min, confirm `pace stale`.

- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(statusline): pace segment for Claude Code"` (the hooks file lives in `~/.claude`, which is its own repo: commit there separately with `git -C ~/.claude add hooks/gsd-statusline.js hooks/pace-statusline-segment.sh && git -C ~/.claude commit -m "statusline: pace v3 segment"`).

---

### Task 15: Retire codex-pace

- [ ] **Step 1:** Confirm every test from `~/codex-pace/Tests` has an equivalent in `~/pace/Tests` (Task 4 copied `CodexRateLimitParserTests`; list any others with `ls ~/codex-pace/Tests/PaceCoreTests` and port them).
- [ ] **Step 2:** Quit CodexPace, remove the login item: `osascript -e 'tell application "System Events" to delete login item "CodexPace"' 2>/dev/null; rm -rf ~/Applications/CodexPace.app; rm -rf "$HOME/Library/Application Support/CodexPace"`.
- [ ] **Step 3:** Archive the repo: `git -C ~/codex-pace status --short` must be empty; then `gh repo archive sternryan/codex-pace --yes` (if the remote exists — check `git -C ~/codex-pace remote -v`; if there is no remote, skip). Add one line to `~/codex-pace/README.md`: "Retired 2026-09-xx: merged into sternryan/pace v3." and commit it BEFORE archiving.
- [ ] **Step 4:** `mv ~/codex-pace ~/archive/codex-pace` (create `~/archive` if absent). Do not `rm`.
- [ ] **Step 5:** Verify `launchctl list | grep -i codex-pace` prints nothing.

---

### Task 16: Docs, live verification, grader, push

- [ ] **Step 1: README.md** rewrite: what v3 shows, the four sources, install (`make install`, `make install-cli`, `make install-statusline`), the loopback API, the CLI, the "undocumented endpoints" caveat, the smithy tri-state, the overage-divisor caveat. **TODOS.md**: delete the three v1 scraper items; add "overage divisor unverified" and "scheduler lease field names confirmed 2026-09-04 (`/lease` state free|held|wedged)".
- [ ] **Step 2: Two-directory test run** (spec §6.1): `cd ~/pace && make test` and `cd ~ && swift test --package-path ~/pace`. Both green.
- [ ] **Step 3: Live definition-of-done checks** (spec §6.2–6.4), each pasted into the final report:
  - `pace --json | jq '.providers'` → claude `api`, codex `api` (or `localFallback` with `needsLogin` if `codex login` is stale — say which), smithy `laneState` present, spend `burn.hourly` non-empty.
  - `pace --json | jq -r .laneState` vs `ssh anvil flux-lock-status` run within the same minute → consistent (`free`↔`serving`, `held`↔`leasedAway`).
  - `diff <(pace --json) <(curl -s 127.0.0.1:6737/v1/report | jq -S .)` → identical (or differ only by `generatedAt` if a refresh raced; rerun).
  - Fresh `claude` session shows the segment.
- [ ] **Step 4: Grader** (house rule 2): `~/.claude/bin/grade-diff.sh` against `a5b4dea..HEAD` before any push. Fix, re-run tests, re-grade until PASS.
- [ ] **Step 5: Push** `git push origin main` as a standalone command (the deploy gate refuses chained push segments).
- [ ] **Step 6: Lane log** one row per wave in `~/.claude/state/lane-log.tsv`; close outcomes.

---

## Execution routing (house rule 9)

| Tasks | Lane | Model | Why |
|---|---|---|---|
| 1, 3, 4, 7 (copy + header + VENDORED.md), 12, 14, 15 | subagent | sonnet | mechanical, fully specified |
| 7 (compile-fix of vendored deps), 8 | subagent | sonnet, escalate to opus only if the vendored dependency graph will not close after 2 attempts | needs reading unfamiliar code |
| 2 (engine), 5, 6, 9, 10, 11 | subagent | sonnet writes; **opus reviews** the engine (Task 2) and coordinator (Task 10) only | judgment lives in the pacing math |
| 13 (UI) | subagent | sonnet | SwiftUI over a finished model |
| 16 grader | grader | fresh context per house rule 2 | |
| smithy `local-heavy` | not used for Swift code generation in this plan: no Swift-capable eval exists for it and the tasks are short; use it only if a bulk fixture-generation step appears | | |

NO Codex anywhere in this project (Ryan, 2026-09-04).
