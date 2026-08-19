# Pace v2 — OAuth Usage API Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the WKWebView scraper as Pace's primary data source with the Claude Code OAuth usage API, keeping the scraper as a fallback for Keychain-absent users, and add the persisted cache, overage lane, pace guard, and edge-armed notifications.

**Architecture:** A `UsageSource` protocol seam with two implementations — `ApiUsageSource` (native Keychain read → one URLSession GET → pure normalizer) and `ScrapeUsageSource` (the existing `UsageFetcher`, lazily constructed). Mode chosen at launch by Keychain presence. All new parsing/selection/pace logic is pure Swift in `PaceCore` with fixture tests; the app target gets only thin I/O wrappers.

**Tech Stack:** Swift 5.9 SPM, SwiftUI `MenuBarExtra`, Security.framework (`SecItemCopyMatching`), URLSession, UserNotifications. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-19-pace-v2-api-migration-design.md` — read it before starting any task.

## Global Constraints

- macOS 14+, Swift 5.9, SPM only — no new package dependencies.
- The OAuth token is READ-ONLY: never refresh it, never write it anywhere, never log it, never put it in an error message. Claude Code owns renewal.
- Never call the `security` CLI — Keychain access is native `SecItemCopyMatching` only.
- Usage endpoint: `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`, 10-second timeout.
- The normalizer must IGNORE unknown JSON keys (the response carries churning feature-flag keys) and must return nil (never crash, never guess) when required fields are missing.
- Expired/revoked token is NEVER a mode switch — API mode shows "Open Claude Code and run /login" with last-good data.
- Icon color rule stands: red only for an alarmed lane; stale = dimmed + ‼ glyph.
- Public comments carry self-contained domain rationale — no internal review codenames (no "review finding I5"-style references in NEW code; Task 12 sanitizes existing ones).
- Run `swift test` after every task; all tests green before every commit. Commit after every task.
- Work directly on `main` (repo convention). Do NOT push — the orchestrator pushes after final verification.

---

### Task 1: PaceCore — LaneSeverity, LaneUsage extensions, FetchStatus.tokenExpired

**Files:**
- Create: `Sources/PaceCore/LaneSeverity.swift`
- Modify: `Sources/PaceCore/LaneUsage.swift`
- Modify: `Sources/PaceCore/FetchStatus.swift`
- Test: `Tests/PaceCoreTests/CoreTypesTests.swift` (append)

**Interfaces:**
- Consumes: existing `LaneUsage`, `FetchStatus`.
- Produces: `LaneSeverity` (`normal|warning|critical|exceeded`, `init(rawServerValue:)` mapping unknown→`.normal`, `var isAlarming: Bool` true for critical/exceeded); `LaneUsage` gains `severity: LaneSeverity` and `displayNameOverride: String?`, both defaulted in `init` so every existing call site compiles unchanged; `FetchStatus.tokenExpired` case.

- [ ] **Step 1: Write the failing tests** — append to `Tests/PaceCoreTests/CoreTypesTests.swift`:

```swift
func testLaneSeverityMapsServerStringsAndUnknowns() {
    XCTAssertEqual(LaneSeverity(rawServerValue: "critical"), .critical)
    XCTAssertEqual(LaneSeverity(rawServerValue: "exceeded"), .exceeded)
    XCTAssertEqual(LaneSeverity(rawServerValue: "warning"), .warning)
    XCTAssertEqual(LaneSeverity(rawServerValue: "normal"), .normal)
    // Unknown strings must degrade to normal, never crash — the endpoint is
    // undocumented and severity vocabulary can grow.
    XCTAssertEqual(LaneSeverity(rawServerValue: "melting"), .normal)
    XCTAssertEqual(LaneSeverity(rawServerValue: nil), .normal)
}

func testLaneSeverityAlarming() {
    XCTAssertTrue(LaneSeverity.critical.isAlarming)
    XCTAssertTrue(LaneSeverity.exceeded.isAlarming)
    XCTAssertFalse(LaneSeverity.warning.isAlarming)
    XCTAssertFalse(LaneSeverity.normal.isAlarming)
}

func testLaneUsageDefaultsPreserveV1CallSites() {
    let lane = LaneUsage(kind: .session, percentUsed: 10, resetDate: Date(), windowLength: 5 * 3600)
    XCTAssertEqual(lane.severity, .normal)
    XCTAssertNil(lane.displayNameOverride)
}

func testLaneUsageDisplayNameOverride() {
    let lane = LaneUsage(kind: .fableWeek, percentUsed: 10, resetDate: Date(), windowLength: nil,
                         severity: .warning, displayNameOverride: "Fable")
    XCTAssertEqual(lane.effectiveDisplayName, "Fable · week")
    let plain = LaneUsage(kind: .fableWeek, percentUsed: 10, resetDate: Date(), windowLength: nil)
    XCTAssertEqual(plain.effectiveDisplayName, "Fable · week")
}
```

Note on `effectiveDisplayName`: when `displayNameOverride` is non-nil AND `kind == .fableWeek`, the name is `"\(displayNameOverride!) · week"`; otherwise it is `kind.displayName`. (The server's `scope.model.display_name` is a label, not an identity — a renamed model relabels the lane instead of breaking it.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CoreTypesTests`
Expected: FAIL — `LaneSeverity` not defined.

- [ ] **Step 3: Implement** — create `Sources/PaceCore/LaneSeverity.swift`:

```swift
/// Server-reported severity for a usage lane. The endpoint is undocumented,
/// so unknown values degrade to `.normal` rather than failing the whole parse.
public enum LaneSeverity: String, Equatable, Sendable, Codable, CaseIterable {
    case normal, warning, critical, exceeded

    public init(rawServerValue: String?) {
        self = rawServerValue.flatMap(LaneSeverity.init(rawValue:)) ?? .normal
    }

    /// Whether the server considers this lane in an alarm state. Server
    /// severity can force the alarm even when local pace math wouldn't —
    /// the server knows about caps the pace model can't see.
    public var isAlarming: Bool { self == .critical || self == .exceeded }
}
```

Modify `Sources/PaceCore/LaneUsage.swift` — add the two stored properties with defaults and the computed name:

```swift
public struct LaneUsage: Equatable, Sendable, Codable {
    public let kind: LaneKind
    public let percentUsed: Int
    public let resetDate: Date
    /// Total length of this lane's reset window. `nil` when not yet known —
    /// callers MUST treat `nil` as "can't compute pace for this lane" and
    /// never substitute a guessed duration. See Global Constraints.
    public let windowLength: TimeInterval?
    /// Server-reported severity; `.normal` for sources that don't carry one
    /// (the browser scrape path).
    public let severity: LaneSeverity
    /// Server-provided model label for a scoped lane (e.g. "Fable"). A label
    /// only — lane identity comes from `kind`, so a model rename relabels
    /// the row instead of breaking it.
    public let displayNameOverride: String?

    public init(kind: LaneKind, percentUsed: Int, resetDate: Date, windowLength: TimeInterval?,
                severity: LaneSeverity = .normal, displayNameOverride: String? = nil) {
        self.kind = kind
        self.percentUsed = percentUsed
        self.resetDate = resetDate
        self.windowLength = windowLength
        self.severity = severity
        self.displayNameOverride = displayNameOverride
    }

    public var effectiveDisplayName: String {
        if let displayNameOverride, kind == .fableWeek { return "\(displayNameOverride) · week" }
        return kind.displayName
    }
}
```

Also make `LaneKind` Codable (`Sources/PaceCore/LaneKind.swift`): change its declaration to `public enum LaneKind: String, CaseIterable, Hashable, Sendable, Codable`.

Modify `Sources/PaceCore/FetchStatus.swift` — add the case with its rationale:

```swift
public enum FetchStatus: Equatable, Sendable {
    case ok
    case needsLogin
    /// API mode: Claude Code credentials exist but the token is expired or
    /// rejected. Distinct from `.needsLogin` (browser mode's claude.ai
    /// sign-in) because the remediation is different — the fix is to open
    /// Claude Code and run /login, and showing a claude.ai sign-in window
    /// here would be the wrong instruction.
    case tokenExpired
    /// The scrape click-through broke for a reason OTHER than being signed
    /// out (e.g. claude.ai renamed a button). Kept separate so the dropdown
    /// never tells you to sign in when you already are.
    case navigationFailed(String)
    case parseError(String)
}
```

- [ ] **Step 4: Run the full suite** — `swift test`. Expected: PASS (existing tests compile via defaulted params). The app target will still compile because `IconRenderer.render`'s `switch status` gains a case — check: it switches with `case .needsLogin, .navigationFailed, .parseError:`; ADD `.tokenExpired` to that stale list in `Sources/Pace/IconRenderer.swift` (stale treatment is correct for it). `MenuView.statusRow` also switches exhaustively — add a temporary case now (Task 9 replaces it):

```swift
case .tokenExpired:
    Text("Claude Code login expired. Open Claude Code and run /login. Showing last known values.")
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
```

Run `swift build` to confirm the app target compiles too.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore Tests Sources/Pace/IconRenderer.swift Sources/Pace/MenuView.swift
git commit -m "feat(core): LaneSeverity, lane display override, FetchStatus.tokenExpired"
```

---

### Task 2: PaceCore — ExtraUsage + UsageSnapshot (Codable cache format)

**Files:**
- Create: `Sources/PaceCore/UsageSnapshot.swift`
- Test: `Tests/PaceCoreTests/UsageSnapshotTests.swift`

**Interfaces:**
- Consumes: `LaneUsage` (Task 1).
- Produces: `ExtraUsage` (`dollarsUsed: Double`, `isEnabled: Bool`) and `UsageSnapshot` (`lanes: [LaneUsage]`, `extraUsage: ExtraUsage?`, `fetchedAt: Date`), both `Codable`, plus `UsageSnapshot.isStale(now:threshold:)`.

- [ ] **Step 1: Write the failing tests** — create `Tests/PaceCoreTests/UsageSnapshotTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class UsageSnapshotTests: XCTestCase {
    private func sampleSnapshot(fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            lanes: [
                LaneUsage(kind: .session, percentUsed: 67, resetDate: fetchedAt.addingTimeInterval(3600),
                          windowLength: 5 * 3600, severity: .warning),
                LaneUsage(kind: .fableWeek, percentUsed: 60, resetDate: fetchedAt.addingTimeInterval(86400),
                          windowLength: 7 * 24 * 3600, displayNameOverride: "Fable")
            ],
            extraUsage: ExtraUsage(dollarsUsed: 12.34, isEnabled: true),
            fetchedAt: fetchedAt
        )
    }

    func testRoundTripsThroughJSON() throws {
        let snapshot = sampleSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testDecodeToleratesUnknownFields() throws {
        // Forward-compat: a snapshot written by a NEWER Pace with extra keys
        // must still load — the cache must never brick a downgrade/upgrade.
        let snapshot = sampleSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        object["futureField"] = ["nested": true]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNoThrow(try JSONDecoder().decode(UsageSnapshot.self, from: data))
    }

    func testStaleness() {
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = sampleSnapshot(fetchedAt: fetched)
        XCTAssertFalse(snapshot.isStale(now: fetched.addingTimeInterval(9 * 60)))
        XCTAssertTrue(snapshot.isStale(now: fetched.addingTimeInterval(11 * 60)))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter UsageSnapshotTests`. Expected: FAIL — types not defined.

- [ ] **Step 3: Implement** — create `Sources/PaceCore/UsageSnapshot.swift`:

```swift
import Foundation

/// Extra-usage (overage) spend, converted from the API's minor units.
public struct ExtraUsage: Equatable, Sendable, Codable {
    public let dollarsUsed: Double
    public let isEnabled: Bool

    public init(dollarsUsed: Double, isEnabled: Bool) {
        self.dollarsUsed = dollarsUsed
        self.isEnabled = isEnabled
    }
}

/// One successful fetch result. Also the persisted last-good cache format —
/// contains percentages and timestamps only, never credentials.
public struct UsageSnapshot: Equatable, Sendable, Codable {
    public let lanes: [LaneUsage]
    public let extraUsage: ExtraUsage?
    public let fetchedAt: Date

    public init(lanes: [LaneUsage], extraUsage: ExtraUsage?, fetchedAt: Date) {
        self.lanes = lanes
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }

    /// Data older than the threshold gets a visible "cached" label rather than
    /// being hidden — last-good numbers with an age tag beat a blank icon.
    public func isStale(now: Date, threshold: TimeInterval = 10 * 60) -> Bool {
        now.timeIntervalSince(fetchedAt) > threshold
    }
}
```

- [ ] **Step 4: Run the full suite** — `swift test`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/UsageSnapshot.swift Tests/PaceCoreTests/UsageSnapshotTests.swift
git commit -m "feat(core): ExtraUsage + UsageSnapshot codable cache format"
```

---

### Task 3: PaceCore — PaceCalculator guard, severity override, resets-first flag

**Files:**
- Modify: `Sources/PaceCore/PaceCalculator.swift`
- Modify: `Sources/PaceCore/PaceReading.swift`
- Test: `Tests/PaceCoreTests/PaceCalculatorTests.swift` (append)

**Interfaces:**
- Consumes: `LaneUsage` (Task 1).
- Produces: `PaceReading` gains `isAlarmed: Bool` (ahead-of-pace OR server severity alarming) and `capBeforeReset: Bool?` (nil when no projection). `PaceCalculator.reading(for:now:)` signature unchanged. New constant `PaceCalculator.minimumElapsedForVerdict: TimeInterval = 10 * 60`.

- [ ] **Step 1: Write the failing tests** — append to `Tests/PaceCoreTests/PaceCalculatorTests.swift`:

```swift
func testNoAheadOfPaceVerdictInFirstTenMinutes() {
    // v1 live bug: at minute one, 1% used > 0% elapsed turned the icon red
    // on trivial usage. Suppress the verdict until the window has history.
    let now = Date()
    let lane = LaneUsage(kind: .session, percentUsed: 5,
                         resetDate: now.addingTimeInterval(5 * 3600 - 60), // 1 min elapsed
                         windowLength: 5 * 3600)
    let reading = PaceCalculator.reading(for: lane, now: now)
    XCTAssertFalse(reading.isAheadOfPace)
    XCTAssertFalse(reading.isAlarmed)
    XCTAssertNil(reading.projectedCapDate)
}

func testAheadOfPaceStillFiresAfterGuardWindow() {
    let now = Date()
    let lane = LaneUsage(kind: .session, percentUsed: 50,
                         resetDate: now.addingTimeInterval(5 * 3600 - 30 * 60), // 30 min elapsed
                         windowLength: 5 * 3600)
    let reading = PaceCalculator.reading(for: lane, now: now)
    XCTAssertTrue(reading.isAheadOfPace)
    XCTAssertTrue(reading.isAlarmed)
    XCTAssertNotNil(reading.projectedCapDate)
    XCTAssertEqual(reading.capBeforeReset, true) // 50% in 30min caps long before 5h
}

func testServerSeverityForcesAlarmEvenWhenBehindPace() {
    let now = Date()
    let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 10,
                         resetDate: now.addingTimeInterval(3 * 24 * 3600), // ~57% elapsed, 10% used
                         windowLength: 7 * 24 * 3600, severity: .critical)
    let reading = PaceCalculator.reading(for: lane, now: now)
    XCTAssertFalse(reading.isAheadOfPace) // local math says fine
    XCTAssertTrue(reading.isAlarmed)      // server says critical — server wins
}

func testResetsFirstWhenPaceIsBarelyAhead() {
    // 30% used at 25% elapsed of a 7-day window: ahead, but the projected
    // cap lands after the reset — the user doesn't need to care.
    let now = Date()
    let windowLength: TimeInterval = 7 * 24 * 3600
    let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 30,
                         resetDate: now.addingTimeInterval(windowLength * 0.75),
                         windowLength: windowLength)
    let reading = PaceCalculator.reading(for: lane, now: now)
    XCTAssertTrue(reading.isAheadOfPace)
    XCTAssertEqual(reading.capBeforeReset, false)
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter PaceCalculatorTests`. Expected: FAIL (new asserts / missing members).

- [ ] **Step 3: Implement** — `Sources/PaceCore/PaceReading.swift` gains two fields (defaulted init params keep old test call sites compiling):

```swift
import Foundation

public struct PaceReading: Equatable, Sendable {
    public let lane: LaneUsage
    public let percentElapsed: Int?
    public let isAheadOfPace: Bool
    public let projectedCapDate: Date?
    /// True when the lane deserves the red treatment: locally ahead of pace,
    /// or the server reports critical/exceeded (the server can see caps the
    /// local pace model can't).
    public let isAlarmed: Bool
    /// For a projected cap: whether the window resets before the cap would
    /// hit — i.e. whether the user actually needs to care. nil when there is
    /// no projection.
    public let capBeforeReset: Bool?

    public init(lane: LaneUsage, percentElapsed: Int?, isAheadOfPace: Bool, projectedCapDate: Date?,
                isAlarmed: Bool = false, capBeforeReset: Bool? = nil) {
        self.lane = lane
        self.percentElapsed = percentElapsed
        self.isAheadOfPace = isAheadOfPace
        self.projectedCapDate = projectedCapDate
        self.isAlarmed = isAlarmed
        self.capBeforeReset = capBeforeReset
    }
}
```

`Sources/PaceCore/PaceCalculator.swift` becomes:

```swift
import Foundation

public enum PaceCalculator {
    /// No ahead-of-pace verdict (and no projection) until the window holds
    /// this much history — a burst in the first minutes of a fresh window
    /// says nothing about sustained pace and flashed the icon red in v1.
    public static let minimumElapsedForVerdict: TimeInterval = 10 * 60

    public static func reading(for lane: LaneUsage, now: Date) -> PaceReading {
        guard let windowLength = lane.windowLength, windowLength > 0 else {
            return PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false,
                               projectedCapDate: nil, isAlarmed: lane.severity.isAlarming,
                               capBeforeReset: nil)
        }

        let windowStart = lane.resetDate.addingTimeInterval(-windowLength)
        let elapsed = max(0, min(now.timeIntervalSince(windowStart), windowLength))
        let percentElapsed = Int((elapsed / windowLength) * 100)
        let ahead = elapsed >= minimumElapsedForVerdict && lane.percentUsed > percentElapsed

        var projectedCapDate: Date? = nil
        var capBeforeReset: Bool? = nil
        if ahead, elapsed > 0, lane.percentUsed > 0 {
            let ratePerSecond = Double(lane.percentUsed) / elapsed
            let secondsTo100 = 100.0 / ratePerSecond
            let cap = windowStart.addingTimeInterval(secondsTo100)
            projectedCapDate = cap
            capBeforeReset = cap < lane.resetDate
        }

        return PaceReading(lane: lane, percentElapsed: percentElapsed, isAheadOfPace: ahead,
                           projectedCapDate: projectedCapDate,
                           isAlarmed: ahead || lane.severity.isAlarming,
                           capBeforeReset: capBeforeReset)
    }
}
```

- [ ] **Step 4: Switch consumers from `isAheadOfPace` to `isAlarmed`** — in `Sources/PaceCore/IconGeometry.swift` change `isHot: reading.isAheadOfPace` to `isHot: reading.isAlarmed`. In `Sources/Pace/MenuView.swift`'s `LaneRow`, replace all three `reading.isAheadOfPace` reads with `reading.isAlarmed` (percent color, bar fill color, and the projection-line condition `if reading.isAheadOfPace, let capDate` → `if reading.isAheadOfPace, let capDate` stays — the projection only exists when locally ahead; only the two COLOR reads change). Run `swift test && swift build`.

- [ ] **Step 5: Run full suite and verify PASS, then commit**

```bash
git add Sources Tests
git commit -m "feat(core): MIN_ELAPSED pace guard, server-severity alarm override, resets-first flag"
```

---

### Task 4: PaceCore — ApiUsageNormalizer with dual-generation fixtures

**Files:**
- Create: `Sources/PaceCore/ApiUsageNormalizer.swift`
- Test: `Tests/PaceCoreTests/ApiUsageNormalizerTests.swift`

**Interfaces:**
- Consumes: `LaneUsage`, `LaneSeverity`, `ExtraUsage`, `UsageSnapshot` (Tasks 1–2).
- Produces: `ApiUsageNormalizer.snapshot(fromJSON: Data, now: Date) -> UsageSnapshot?`. Returns nil when neither generation's required fields parse. Lane order in output: session, allModelsWeek, fableWeek (matching v1's display order); absent lanes simply omitted.

- [ ] **Step 1: Write the failing tests** — create `Tests/PaceCoreTests/ApiUsageNormalizerTests.swift`. The first fixture is the SANITIZED live capture from the 2026-08-19 probe (structure verbatim, feature-flag keys reduced to two stand-ins):

```swift
import XCTest
@testable import PaceCore

final class ApiUsageNormalizerTests: XCTestCase {
    // Structure captured live from /api/oauth/usage on 2026-08-19 (Max plan).
    // Opaque feature-flag keys reduced to two stand-ins; numbers/dates kept.
    private let currentGeneration = """
    {
      "some_flag_key": true, "another_flag": {"nested": 1},
      "limits": [
        {"kind": "session", "group": "session", "percent": 67, "severity": "normal",
         "resets_at": "2026-08-19T22:50:00.109754+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_all", "group": "weekly", "percent": 43, "severity": "warning",
         "resets_at": "2026-08-22T21:00:00.109771+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 60, "severity": "normal",
         "resets_at": "2026-08-22T21:00:00.109937+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ],
      "extra_usage": {"is_enabled": false, "monthly_limit": 5000, "used_credits": 0.0,
                      "utilization": 0.0, "currency": "USD", "disabled_reason": "out_of_credits"},
      "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "percent": 0,
                "severity": "normal", "enabled": false},
      "five_hour": {"utilization": 67.0, "resets_at": "2026-08-19T22:50:00.109754+00:00"},
      "seven_day": {"utilization": 43.0, "resets_at": "2026-08-22T21:00:00.109771+00:00"}
    }
    """.data(using: .utf8)!

    private let legacyGeneration = """
    {
      "five_hour": {"utilization": 61.0, "resets_at": "2026-08-19T22:50:00+00:00"},
      "seven_day": {"utilization": 36.0, "resets_at": "2026-08-22T21:00:00+00:00"},
      "extra_usage": {"is_enabled": true, "used_credits": 1234}
    }
    """.data(using: .utf8)!

    private let now = Date(timeIntervalSince1970: 1_787_200_000)

    func testCurrentGenerationProducesThreeLanesInDisplayOrder() throws {
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: currentGeneration, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.session, .allModelsWeek, .fableWeek])
        XCTAssertEqual(snapshot.lanes[0].percentUsed, 67)
        XCTAssertEqual(snapshot.lanes[0].windowLength, 5 * 3600)
        XCTAssertEqual(snapshot.lanes[1].severity, .warning)
        XCTAssertEqual(snapshot.lanes[1].windowLength, 7 * 24 * 3600)
        XCTAssertEqual(snapshot.lanes[2].displayNameOverride, "Fable")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testScopedLaneIdentityIsKindPlusScopeNotName() throws {
        // A renamed model must relabel the lane, not break it.
        let renamed = String(data: currentGeneration, encoding: .utf8)!
            .replacingOccurrences(of: "\"Fable\"", with: "\"Meridian\"")
            .data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: renamed, now: now))
        XCTAssertEqual(snapshot.lanes[2].kind, .fableWeek)
        XCTAssertEqual(snapshot.lanes[2].displayNameOverride, "Meridian")
    }

    func testLegacyGenerationProducesTwoLanesAndOverage() throws {
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: legacyGeneration, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.session, .allModelsWeek])
        XCTAssertEqual(snapshot.lanes[0].percentUsed, 61)
        XCTAssertEqual(snapshot.extraUsage, ExtraUsage(dollarsUsed: 12.34, isEnabled: true))
    }

    func testExtraUsagePrefersExtraUsageObjectOverSpend() throws {
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: currentGeneration, now: now))
        XCTAssertEqual(snapshot.extraUsage, ExtraUsage(dollarsUsed: 0, isEnabled: false))
    }

    func testMissingScopedLaneStillParses() throws {
        // A plan without a per-model weekly lane renders two lanes, not zero.
        let fixture = """
        {"limits": [
           {"kind": "session", "percent": 10, "severity": "normal",
            "resets_at": "2026-08-19T22:50:00+00:00"},
           {"kind": "weekly_all", "percent": 20, "severity": "normal",
            "resets_at": "2026-08-22T21:00:00+00:00"}]}
        """.data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: fixture, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.session, .allModelsWeek])
        XCTAssertNil(snapshot.extraUsage)
    }

    func testGarbageAndShapeDriftReturnNilNotCrash() {
        XCTAssertNil(ApiUsageNormalizer.snapshot(fromJSON: Data("not json".utf8), now: now))
        XCTAssertNil(ApiUsageNormalizer.snapshot(fromJSON: Data("{}".utf8), now: now))
        // limits present but entries missing required fields, and no legacy
        // fallback objects → nil (shape changed; caller reports parseError).
        let drifted = Data(#"{"limits": [{"kind": "session", "pct": 5}]}"#.utf8)
        XCTAssertNil(ApiUsageNormalizer.snapshot(fromJSON: drifted, now: now))
    }

    func testUnparseableResetDateDropsLaneRatherThanGuessing() throws {
        let fixture = """
        {"limits": [
           {"kind": "session", "percent": 10, "severity": "normal", "resets_at": "soonish"},
           {"kind": "weekly_all", "percent": 20, "severity": "normal",
            "resets_at": "2026-08-22T21:00:00+00:00"}]}
        """.data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: fixture, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.allModelsWeek])
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ApiUsageNormalizerTests`. Expected: FAIL — normalizer not defined.

- [ ] **Step 3: Implement** — create `Sources/PaceCore/ApiUsageNormalizer.swift`:

```swift
import Foundation

/// Maps /api/oauth/usage JSON to a UsageSnapshot. The endpoint is
/// undocumented and has already changed shape once, so this handles both
/// observed generations and treats anything else as "shape changed" (nil) —
/// the caller reports it; nothing here guesses or crashes. Unknown keys are
/// ignored everywhere: the live response carries transient feature-flag keys.
public enum ApiUsageNormalizer {
    public static func snapshot(fromJSON data: Data, now: Date) -> UsageSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        let lanes = lanesFromLimits(root["limits"] as? [[String: Any]])
            ?? lanesFromLegacy(root)
        guard let lanes, !lanes.isEmpty else { return nil }

        return UsageSnapshot(lanes: lanes, extraUsage: extraUsage(from: root), fetchedAt: now)
    }

    // MARK: current generation — limits[]

    private static func lanesFromLimits(_ limits: [[String: Any]]?) -> [LaneUsage]? {
        guard let limits, !limits.isEmpty else { return nil }
        var byKind: [LaneKind: LaneUsage] = [:]

        for entry in limits {
            guard let kindString = entry["kind"] as? String else { continue }
            // Identity is kind (+ scope presence for the per-model lane);
            // scope.model.display_name is only a label.
            let kind: LaneKind
            var displayName: String? = nil
            switch kindString {
            case "session":
                kind = .session
            case "weekly_all":
                kind = .allModelsWeek
            case "weekly_scoped":
                guard let scope = entry["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any] else { continue }
                kind = .fableWeek
                displayName = model["display_name"] as? String
            default:
                continue // unknown lane kinds are future features, not errors
            }
            guard byKind[kind] == nil else { continue } // first of each kind wins

            guard let percent = intPercent(entry["percent"]),
                  let resetDate = isoDate(entry["resets_at"]) else { continue }

            byKind[kind] = LaneUsage(
                kind: kind, percentUsed: percent, resetDate: resetDate,
                windowLength: kind == .session ? 5 * 3600 : 7 * 24 * 3600,
                severity: LaneSeverity(rawServerValue: entry["severity"] as? String),
                displayNameOverride: displayName
            )
        }

        // Display order matches the dropdown and icon: session, week, scoped.
        let ordered: [LaneKind] = [.session, .allModelsWeek, .fableWeek]
        let lanes = ordered.compactMap { byKind[$0] }
        return lanes.isEmpty ? nil : lanes
    }

    // MARK: legacy generation — top-level five_hour / seven_day

    private static func lanesFromLegacy(_ root: [String: Any]) -> [LaneUsage]? {
        func lane(_ key: String, _ kind: LaneKind, _ window: TimeInterval) -> LaneUsage? {
            guard let object = root[key] as? [String: Any],
                  let percent = intPercent(object["utilization"]),
                  let resetDate = isoDate(object["resets_at"]) else { return nil }
            return LaneUsage(kind: kind, percentUsed: percent, resetDate: resetDate, windowLength: window)
        }
        let lanes = [lane("five_hour", .session, 5 * 3600),
                     lane("seven_day", .allModelsWeek, 7 * 24 * 3600)].compactMap { $0 }
        return lanes.isEmpty ? nil : lanes
    }

    // MARK: overage

    private static func extraUsage(from root: [String: Any]) -> ExtraUsage? {
        if let eu = root["extra_usage"] as? [String: Any] {
            let credits = (eu["used_credits"] as? NSNumber)?.doubleValue ?? 0
            return ExtraUsage(dollarsUsed: credits / 100, isEnabled: eu["is_enabled"] as? Bool ?? false)
        }
        if let spend = root["spend"] as? [String: Any],
           let used = spend["used"] as? [String: Any],
           let minor = (used["amount_minor"] as? NSNumber)?.doubleValue {
            return ExtraUsage(dollarsUsed: minor / 100, isEnabled: minor > 0)
        }
        return nil
    }

    // MARK: field coercion

    private static func intPercent(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return Int(number.doubleValue.rounded())
    }

    private static func isoDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
```

- [ ] **Step 4: Run full suite** — `swift test`. Expected: PASS. Fix only within this task's files if not.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/ApiUsageNormalizer.swift Tests/PaceCoreTests/ApiUsageNormalizerTests.swift
git commit -m "feat(core): dual-generation /api/oauth/usage normalizer with live-capture fixtures"
```

---

### Task 5: PaceCore — credential selection logic (pure) 

**Files:**
- Create: `Sources/PaceCore/ClaudeCodeCredential.swift`
- Test: `Tests/PaceCoreTests/ClaudeCodeCredentialTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ClaudeCodeCredential` (`accessToken: String`, `expiresAt: Date?`), `ClaudeCodeCredential.parse(itemData: Data) -> ClaudeCodeCredential?`, and `ClaudeCodeCredential.selectFreshest(from: [ClaudeCodeCredential], now: Date) -> ClaudeCodeCredential?` (latest non-expired; nil when all expired). Task 6's Keychain wrapper feeds raw item Data into these.

- [ ] **Step 1: Write the failing tests** — create `Tests/PaceCoreTests/ClaudeCodeCredentialTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class ClaudeCodeCredentialTests: XCTestCase {
    func testParsesNestedClaudeAiOauthShape() throws {
        // The shape Claude Code writes: {"claudeAiOauth": {...}} with
        // expiresAt in epoch MILLISECONDS.
        let json = Data(#"{"claudeAiOauth":{"accessToken":"tok-a","expiresAt":1787204000000,"refreshToken":"r"}}"#.utf8)
        let credential = try XCTUnwrap(ClaudeCodeCredential.parse(itemData: json))
        XCTAssertEqual(credential.accessToken, "tok-a")
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 1_787_204_000))
    }

    func testParsesFlatShapeAndMissingExpiry() throws {
        let flat = try XCTUnwrap(ClaudeCodeCredential.parse(itemData: Data(#"{"accessToken":"tok-b"}"#.utf8)))
        XCTAssertEqual(flat.accessToken, "tok-b")
        XCTAssertNil(flat.expiresAt)
    }

    func testGarbageParsesToNil() {
        XCTAssertNil(ClaudeCodeCredential.parse(itemData: Data("nope".utf8)))
        XCTAssertNil(ClaudeCodeCredential.parse(itemData: Data(#"{"claudeAiOauth":{}}"#.utf8)))
    }

    func testSelectFreshestPicksLatestNonExpired() {
        // The trap found live on 2026-08-19: multiple Keychain items share
        // the service name; a single-match read returned the STALE one and
        // reported "revoked" forever, right after a successful login.
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        let stale = ClaudeCodeCredential(accessToken: "old", expiresAt: now.addingTimeInterval(-86400))
        let fresh = ClaudeCodeCredential(accessToken: "new", expiresAt: now.addingTimeInterval(8 * 3600))
        let fresher = ClaudeCodeCredential(accessToken: "newest", expiresAt: now.addingTimeInterval(9 * 3600))
        XCTAssertEqual(ClaudeCodeCredential.selectFreshest(from: [stale, fresher, fresh], now: now)?.accessToken, "newest")
    }

    func testSelectFreshestAllExpiredReturnsNil() {
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        let a = ClaudeCodeCredential(accessToken: "a", expiresAt: now.addingTimeInterval(-1))
        XCTAssertNil(ClaudeCodeCredential.selectFreshest(from: [a], now: now))
        XCTAssertNil(ClaudeCodeCredential.selectFreshest(from: [], now: now))
    }

    func testMissingExpiryTreatedAsUsableButLeastPreferred() {
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        let unknown = ClaudeCodeCredential(accessToken: "unknown", expiresAt: nil)
        let dated = ClaudeCodeCredential(accessToken: "dated", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(ClaudeCodeCredential.selectFreshest(from: [unknown, dated], now: now)?.accessToken, "dated")
        XCTAssertEqual(ClaudeCodeCredential.selectFreshest(from: [unknown], now: now)?.accessToken, "unknown")
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ClaudeCodeCredentialTests`. Expected: FAIL.

- [ ] **Step 3: Implement** — create `Sources/PaceCore/ClaudeCodeCredential.swift`:

```swift
import Foundation

/// A parsed Claude Code OAuth credential. Pace only ever READS these —
/// renewal belongs to Claude Code; refreshing from a second process would
/// rotate a token the owner can't see.
public struct ClaudeCodeCredential: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// Parses one Keychain item's payload. Claude Code writes
    /// {"claudeAiOauth": {accessToken, expiresAt(ms), ...}}; a flat object
    /// is accepted for resilience. Returns nil rather than guessing.
    public static func parse(itemData: Data) -> ClaudeCodeCredential? {
        guard let root = (try? JSONSerialization.jsonObject(with: itemData)) as? [String: Any] else { return nil }
        let payload = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = payload["accessToken"] as? String, !token.isEmpty else { return nil }
        let expiresAt = (payload["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000) // epoch milliseconds
        }
        return ClaudeCodeCredential(accessToken: token, expiresAt: expiresAt)
    }

    /// Multiple Keychain items can share the Claude Code service name
    /// (different accounts, suffixed variants from other installs). A
    /// single-match read can return a stale item and report the login as
    /// revoked forever — observed live. Pick the latest non-expired
    /// credential; a credential without an expiry is usable but least
    /// preferred (no evidence of freshness).
    public static func selectFreshest(from candidates: [ClaudeCodeCredential], now: Date) -> ClaudeCodeCredential? {
        let usable = candidates.filter { $0.expiresAt.map { $0 > now } ?? true }
        return usable.max { lhs, rhs in
            (lhs.expiresAt ?? .distantPast) < (rhs.expiresAt ?? .distantPast)
        }
    }
}
```

- [ ] **Step 4: Run full suite** — `swift test`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/ClaudeCodeCredential.swift Tests/PaceCoreTests/ClaudeCodeCredentialTests.swift
git commit -m "feat(core): credential parse + freshest-selection (multi-item Keychain trap)"
```

---

### Task 6: App — KeychainCredentialStore + ApiUsageSource

**Files:**
- Create: `Sources/Pace/KeychainCredentialStore.swift`
- Create: `Sources/Pace/UsageSource.swift`
- Create: `Sources/Pace/ApiUsageSource.swift`

**Interfaces:**
- Consumes: `ClaudeCodeCredential` (Task 5), `ApiUsageNormalizer`, `UsageSnapshot`, `FetchStatus` (Tasks 1–4).
- Produces:
  - `protocol UsageSource { func fetch() async -> Result<UsageSnapshot, FetchStatus>? }` (nil = skipped, leave state as-is)
  - `enum KeychainReadResult { case found(ClaudeCodeCredential); case allExpired; case none }`
  - `struct KeychainCredentialStore { func read(now: Date) -> KeychainReadResult; func hasAnyItem() -> Bool }`
  - `final class ApiUsageSource: UsageSource`
- Task 7 consumes `UsageSource` and `KeychainCredentialStore.hasAnyItem()`.

No unit tests in this task — the pure logic was tested in Tasks 4–5; these are thin I/O wrappers covered by Task 13's manual checklist.

- [ ] **Step 1: Create `Sources/Pace/UsageSource.swift`**

```swift
import PaceCore

/// The seam between AppState and its data source. Exactly one implementation
/// is active per launch: the API source when Claude Code credentials exist
/// in the Keychain, the browser scraper otherwise. Failure carries the same
/// FetchStatus the UI already renders.
protocol UsageSource: AnyObject {
    /// nil = the fetch was skipped (e.g. the sign-in window is up, or a
    /// scrape is already in flight); the caller leaves state untouched.
    /// The API source never returns nil.
    func fetch() async -> Result<UsageSnapshot, FetchStatus>?
}
```

- [ ] **Step 2: Create `Sources/Pace/KeychainCredentialStore.swift`**

```swift
import Foundation
import Security
import PaceCore

enum KeychainReadResult {
    case found(ClaudeCodeCredential)
    /// Items exist but every credential is expired — the user has Claude Code
    /// and needs to re-login there. NOT the same as `.none`: showing a
    /// claude.ai sign-in window here would be the wrong remediation.
    case allExpired
    case none
}

/// Reads Claude Code's OAuth credentials natively (SecItemCopyMatching), so
/// the user's Keychain grant is scoped to Pace.app itself — shelling out to
/// /usr/bin/security would extend the grant to every CLI process on the
/// machine. Multiple items can share the service name (and suffixed
/// variants exist), so this enumerates ALL matching items and lets
/// ClaudeCodeCredential.selectFreshest pick — a single-match read was
/// observed returning a stale token right after a successful login.
struct KeychainCredentialStore {
    private static let servicePrefix = "Claude Code-credentials"

    func read(now: Date = Date()) -> KeychainReadResult {
        let payloads = copyAllMatchingItemPayloads()
        guard !payloads.isEmpty else { return .none }
        let credentials = payloads.compactMap(ClaudeCodeCredential.parse(itemData:))
        guard !credentials.isEmpty else { return .none }
        if let freshest = ClaudeCodeCredential.selectFreshest(from: credentials, now: now) {
            return .found(freshest)
        }
        return .allExpired
    }

    func hasAnyItem() -> Bool {
        !copyAllMatchingItemPayloads().isEmpty
    }

    private func copyAllMatchingItemPayloads() -> [Data] {
        // kSecAttrService has no prefix query, so fetch all generic passwords'
        // attributes+data and filter on the service prefix ourselves. The
        // attribute list never leaves this function; only matching payloads do.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(Self.servicePrefix),
                  let data = item[kSecValueData as String] as? Data else { return nil }
            return data
        }
    }
}
```

- [ ] **Step 3: Create `Sources/Pace/ApiUsageSource.swift`**

```swift
import Foundation
import PaceCore

/// Primary data source: the same endpoint Claude Code's /usage command reads.
/// One GET per refresh; the token is used in-memory only — never stored,
/// never logged, never refreshed (Claude Code owns renewal).
final class ApiUsageSource: UsageSource {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let store: KeychainCredentialStore
    private let session: URLSession

    init(store: KeychainCredentialStore = KeychainCredentialStore()) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10 // a hung socket must not wedge the refresh cycle
        self.session = URLSession(configuration: config)
    }

    func fetch() async -> Result<UsageSnapshot, FetchStatus>? {
        let credential: ClaudeCodeCredential
        switch store.read() {
        case .found(let found): credential = found
        case .allExpired, .none:
            // .none shouldn't occur in API mode (mode selection saw an item)
            // but a user can delete the item mid-session; either way the
            // remediation is Claude Code's login, not claude.ai's.
            return .failure(.tokenExpired)
        }

        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.parseError("network unreachable"))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.parseError("unexpected response"))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            // Expiry math said the token was fresh but the server disagrees
            // (revoked, or clock skew) — the server is the authority.
            return .failure(.tokenExpired)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.parseError("usage request failed (HTTP \(http.statusCode))"))
        }

        guard let snapshot = ApiUsageNormalizer.snapshot(fromJSON: data, now: Date()) else {
            return .failure(.parseError("usage endpoint shape changed"))
        }
        return .success(snapshot)
    }
}
```

- [ ] **Step 4: Build and test** — `swift build && swift test`. Expected: both green (nothing consumes these yet).

- [ ] **Step 5: Commit**

```bash
git add Sources/Pace/UsageSource.swift Sources/Pace/KeychainCredentialStore.swift Sources/Pace/ApiUsageSource.swift
git commit -m "feat: native Keychain credential store + ApiUsageSource"
```

---

### Task 7: App — ScrapeUsageSource wrapper, mode selection, AppState rewiring

**Files:**
- Create: `Sources/Pace/ScrapeUsageSource.swift`
- Modify: `Sources/Pace/AppState.swift`
- Modify: `Sources/Pace/UsageFetcher.swift` (delegate removal)

**Interfaces:**
- Consumes: `UsageSource`, `ApiUsageSource`, `KeychainCredentialStore` (Task 6); existing `UsageFetcher`.
- Produces: `enum DataSourceMode { case api, browser }`; `AppState.mode: DataSourceMode`; `AppState.applySnapshot(_ snapshot: UsageSnapshot, stale: Bool)` (Task 8 consumes); `AppState.latestSnapshot: UsageSnapshot?`. `UsageFetcher` gains `func fetchSnapshot() async -> Result<UsageSnapshot, FetchStatus>` and loses the delegate protocol.

- [ ] **Step 1: Convert `UsageFetcher` from delegate to result-returning.** In `Sources/Pace/UsageFetcher.swift`: delete the `UsageFetcherDelegate` protocol and the `weak var delegate` property. Change the private `scrape()` so that instead of calling `delegate?...` it returns the outcome, and add a public async API. Replace `refresh()`/`scrapeCurrentPage()`/`scrape()` with:

```swift
    enum ScrapeOutcome {
        case success([LaneUsage])
        case failure(FetchStatus)
        /// Refresh skipped (login window up, or a scrape already in flight) —
        /// not a failure; the caller leaves current state untouched.
        case skipped
    }

    func fetchSnapshot() async -> ScrapeOutcome {
        guard !isPresentingLogin else { return .skipped } // never reload the page the user is signing into
        guard !isRefreshing else { return .skipped }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let url = URL(string: "https://claude.ai/new") else { return .skipped }
        webView.load(URLRequest(url: url))
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        return await scrape()
    }

    /// Reads whatever the WKWebView is already showing, without navigating —
    /// the post-login poll's detection mechanism, so watching for sign-in
    /// completion can't destroy the sign-in itself. Returns non-nil once the
    /// page is past claude.ai's sign-in gate (whether or not it parsed), so
    /// the caller knows sign-in finished.
    func scrapeCurrentPageOutcome() async -> ScrapeOutcome? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        defer { isRefreshing = false }
        let outcome = await scrape()
        if case .failure(.needsLogin) = outcome { return nil }
        return outcome
    }

    private func scrape() async -> ScrapeOutcome {
        switch await clickThroughToUsagePanel() {
        case .reachedUsagePanel:
            break
        case .notSignedIn:
            return .failure(.needsLogin)
        case .navigationBroke(let step):
            return .failure(.navigationFailed("Couldn't find the \(step) button — claude.ai's UI may have changed"))
        }

        guard let panelText = await readUsagePanelText(), !panelText.isEmpty else {
            return .failure(.parseError("Usage panel text not found"))
        }
        guard let lanes = UsagePanelTextExtractor.extractLanes(
            from: panelText, now: Date(), sessionWindowLength: SessionWindow.confirmedLength
        ) else {
            return .failure(.parseError("Could not parse usage panel text"))
        }
        return .success(lanes)
    }
```

Also update the class doc comment (the `@MainActor` rationale referencing "review finding I5") to plain language: "MainActor-isolated so state mutations land before async callers resume — a nonisolated seam here forced an unstructured Task hop that let callers read stale status."

- [ ] **Step 2: Create `Sources/Pace/ScrapeUsageSource.swift`**

```swift
import Foundation
import PaceCore

/// Fallback source for claude.ai users without Claude Code: wraps the v1
/// WKWebView scraper. Only ever constructed in browser mode, so API-mode
/// users never pay the WebView's memory or lifecycle cost.
@MainActor
final class ScrapeUsageSource: UsageSource {
    let fetcher: UsageFetcher

    init(fetcher: UsageFetcher = UsageFetcher()) {
        self.fetcher = fetcher
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
```

(The protocol's optional return exists exactly for `.skipped` — Task 6 defined it that way; `ApiUsageSource.fetch()` has the same optional signature but never returns nil.)

- [ ] **Step 3: Rewire `AppState`** — replace `Sources/Pace/AppState.swift` contents with:

```swift
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
    let mode: DataSourceMode

    // Mode-dependent default; a user-customized value still wins (see
    // migration note in init). API mode polls faster because a refresh is
    // one small JSON GET, not a WebView page load.
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    private let source: UsageSource
    private let scrapeSource: ScrapeUsageSource? // non-nil only in browser mode
    private var timer: Timer?
    private var postLoginPollTask: Task<Void, Never>?

    init(source: UsageSource? = nil, mode: DataSourceMode? = nil) {
        let store = KeychainCredentialStore()
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
        // be told apart from "user chose 360" — treat 360 as uncustomized
        // and migrate it to the mode default once.
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        let modeDefault: TimeInterval = resolvedMode == .api ? 120 : 360
        self.refreshInterval = (stored > 0 && stored != 360) ? stored : modeDefault

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
        Task { await performFetch() }
    }

    private func performFetch() async {
        guard let result = await source.fetch() else { return } // skipped — leave state as-is
        switch result {
        case .success(let snapshot):
            applySnapshot(snapshot, stale: false)
        case .failure(let failure):
            status = failure
            // Last-known readings stay rendered; mark them as cached so the
            // dropdown can label their age honestly.
            if latestSnapshot != nil { isShowingCachedData = true }
        }
    }

    func applySnapshot(_ snapshot: UsageSnapshot, stale: Bool) {
        latestSnapshot = snapshot
        paceReadings = snapshot.lanes.map { PaceCalculator.reading(for: $0, now: Date()) }
        status = .ok
        isShowingCachedData = stale
        if !stale { lastSuccessAt = snapshot.fetchedAt }
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
                        applySnapshot(UsageSnapshot(lanes: lanes, extraUsage: nil, fetchedAt: Date()), stale: false)
                    }
                    return
                }
            }
        }
    }

    func openClaudeUsagePage() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    func openClaudeCode() {
        // Best remediation we can offer for an expired token: surface the
        // instruction; there is no reliable way to deep-link a terminal app.
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
```

Note: initial `status` changed from `.needsLogin` to `.ok` — in API mode "needs claude.ai login" was always wrong, and in browser mode the first fetch immediately sets `.needsLogin` if true. Delete `openClaudeCode()` if unused by Task 9's MenuView (Task 9 decides; keep for now).

- [ ] **Step 4: Fix compile fallout.** `MenuView.statusRow`'s `.needsLogin` case calls `appState.presentLogin()` — still valid. `PreferencesView`'s "Sign out of claude.ai" button should only show in browser mode: wrap it in `if appState.mode == .browser { ... }`. Run `swift build && swift test` until green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pace
git commit -m "feat: UsageSource seam, mode selection, AppState on snapshots (scraper = browser-mode fallback)"
```

---

### Task 8: PaceCore + App — persisted last-good cache

**Files:**
- Create: `Sources/PaceCore/SnapshotCache.swift`
- Modify: `Sources/Pace/AppState.swift`
- Test: `Tests/PaceCoreTests/SnapshotCacheTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot` (Task 2), `AppState.applySnapshot(_:stale:)` (Task 7).
- Produces: `SnapshotCache(directory: URL)` with `func load() -> UsageSnapshot?`, `func save(_ snapshot: UsageSnapshot)`. Default directory: `~/Library/Application Support/Pace/`, file `last-usage.json`.

- [ ] **Step 1: Write the failing tests** — create `Tests/PaceCoreTests/SnapshotCacheTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class SnapshotCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pace-cache-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveThenLoadRoundTrips() {
        let cache = SnapshotCache(directory: directory)
        let snapshot = UsageSnapshot(
            lanes: [LaneUsage(kind: .session, percentUsed: 40,
                              resetDate: Date(timeIntervalSince1970: 1_787_204_000),
                              windowLength: 5 * 3600)],
            extraUsage: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_787_200_000))
        cache.save(snapshot)
        XCTAssertEqual(cache.load(), snapshot)
    }

    func testLoadWithNoFileReturnsNil() {
        XCTAssertNil(SnapshotCache(directory: directory).load())
    }

    func testCorruptFileReturnsNilRatherThanCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("last-usage.json"))
        XCTAssertNil(SnapshotCache(directory: directory).load())
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter SnapshotCacheTests`. Expected: FAIL.

- [ ] **Step 3: Implement** — create `Sources/PaceCore/SnapshotCache.swift`:

```swift
import Foundation

/// Persists the last successful UsageSnapshot so a relaunch (or a fetch
/// failure) renders real last-known numbers with an age label instead of a
/// blank icon. Contains percentages and timestamps only — never credentials.
public struct SnapshotCache {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("last-usage.json")
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pace", isDirectory: true)
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Wire into AppState** — in `init`, after mode resolution and before `refreshNow()`:

```swift
        // Render last-good numbers immediately on launch; the first live
        // fetch replaces them. Stale labeling is age-based, so day-old cache
        // shows as cached, not as fresh truth.
        if let cached = cache.load() {
            applySnapshot(cached, stale: cached.isStale(now: Date()))
        }
```

with `private let cache = SnapshotCache(directory: SnapshotCache.defaultDirectory())` as a stored property. In `applySnapshot`, when `stale == false`, add `cache.save(snapshot)`. In `performFetch`'s failure branch, recompute the label honestly: `isShowingCachedData = latestSnapshot != nil`. Run `swift build && swift test`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: persisted last-good snapshot cache with age-labeled staleness"
```

---

### Task 9: App — MenuView status rows, overage row, resets-first copy, Preferences mode line

**Files:**
- Modify: `Sources/Pace/MenuView.swift`
- Modify: `Sources/Pace/PreferencesView.swift`
- Modify: `Sources/PaceCore/PaceFormatter.swift`
- Test: `Tests/PaceCoreTests/PaceFormatterTests.swift` (create if absent)

**Interfaces:**
- Consumes: `AppState.mode`, `.latestSnapshot`, `.isShowingCachedData` (Tasks 7–8), `PaceReading.capBeforeReset` (Task 3).
- Produces: `PaceFormatter.projectionLabel(capDate:resetDate:capBeforeReset:)` replacing the two-argument version.

- [ ] **Step 1: PaceFormatter — failing test first** (`Tests/PaceCoreTests/PaceFormatterTests.swift`):

```swift
import XCTest
@testable import PaceCore

final class PaceFormatterTests: XCTestCase {
    func testProjectionLabelCapBeforeReset() {
        let reset = Date(timeIntervalSince1970: 1_787_300_000)
        let cap = reset.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(PaceFormatter.projectionLabel(capDate: cap, resetDate: reset, capBeforeReset: true),
                       "~2h before reset")
    }

    func testProjectionLabelResetsFirstSaysSo() {
        // The projection's answer to "do I need to care?" — when the reset
        // arrives before the projected cap, say that instead of an alarm.
        let reset = Date(timeIntervalSince1970: 1_787_300_000)
        let cap = reset.addingTimeInterval(3 * 3600)
        XCTAssertEqual(PaceFormatter.projectionLabel(capDate: cap, resetDate: reset, capBeforeReset: false),
                       "after reset — resets first")
    }
}
```

Run `swift test --filter PaceFormatterTests` → FAIL. Then change `PaceFormatter.projectionLabel` to:

```swift
    public static func projectionLabel(capDate: Date, resetDate: Date, capBeforeReset: Bool) -> String {
        guard capBeforeReset else { return "after reset — resets first" }
        let hours = max(0, Int(resetDate.timeIntervalSince(capDate)) / 3600)
        return hours <= 0 ? "before reset" : "~\(hours)h before reset"
    }
```

Run the filter again → PASS.

- [ ] **Step 2: MenuView updates.** In `LaneRow`:
  - lane title: `Text(reading.lane.kind.displayName)` → `Text(reading.lane.effectiveDisplayName)`.
  - projection line becomes (note color: informational when resets-first):

```swift
            if reading.isAheadOfPace, let capDate = reading.projectedCapDate, let capBeforeReset = reading.capBeforeReset {
                Text("Projected to hit cap \(PaceFormatter.projectionLabel(capDate: capDate, resetDate: reading.lane.resetDate, capBeforeReset: capBeforeReset))")
                    .font(.system(size: 11))
                    .foregroundStyle(capBeforeReset ? Color.red : Color.secondary)
            }
```

  In `MenuView.body`, after the `ForEach` lanes block, add the overage row:

```swift
            if let extra = appState.latestSnapshot?.extraUsage, extra.isEnabled, extra.dollarsUsed > 0 {
                HStack {
                    Text("Extra usage").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", extra.dollarsUsed)).font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
            }
```

  In `statusRow`, replace the temporary `.tokenExpired` case with the final copy, and add a cached-data line. Full replacement `statusRow`:

```swift
    @ViewBuilder
    private var statusRow: some View {
        if appState.isShowingCachedData, appState.status == .ok {
            Text("Showing cached data\(appState.latestSnapshot.map { " · fetched \(PaceFormatter.ageLabel(since: $0.fetchedAt, now: Date()))" } ?? "")")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        }
        switch appState.status {
        case .needsLogin:
            Button("Sign in to claude.ai") { appState.presentLogin() }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .tokenExpired:
            Text("Claude Code login expired — open Claude Code and run /login. Showing last known values.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .navigationFailed(let detail):
            Text("\(detail). Showing last known values — open claude.ai directly to check.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .parseError(let detail):
            Text("Couldn't refresh usage (\(detail)). Showing last known values.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .ok:
            EmptyView()
        }
    }
```

  Add `PaceFormatter.ageLabel` (with a test in the same file as Step 1's tests):

```swift
    public static func ageLabel(since date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date)) / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return hours < 48 ? "\(hours)h ago" : "\(hours / 24)d ago"
    }
```

Test:

```swift
    func testAgeLabel() {
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        XCTAssertEqual(PaceFormatter.ageLabel(since: now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(PaceFormatter.ageLabel(since: now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(PaceFormatter.ageLabel(since: now.addingTimeInterval(-3 * 86400), now: now), "3d ago")
    }
```

- [ ] **Step 3: PreferencesView.** Add a read-only mode line at the top of the Form, and make the sign-out button browser-mode-only (if not already from Task 7):

```swift
            LabeledContent("Data source",
                           value: appState.mode == .api ? "Claude Code API" : "claude.ai browser session")
```

- [ ] **Step 4: Also update the `#Preview` in MenuView** if it references removed APIs (it uses `IconRenderer.render` and `PaceCalculator.reading` — both still exist; verify it compiles). Run `swift build && swift test` → green.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat(ui): tokenExpired + cached-data rows, overage row, resets-first projection copy, mode line"
```

---

### Task 10: PaceCore + App — edge-armed ahead-of-pace notifications

**Files:**
- Create: `Sources/PaceCore/NotificationGovernor.swift`
- Create: `Sources/Pace/PaceNotifier.swift`
- Modify: `Sources/Pace/AppState.swift`
- Test: `Tests/PaceCoreTests/NotificationGovernorTests.swift`

**Interfaces:**
- Consumes: `PaceReading` (Task 3).
- Produces: `NotificationGovernor` (pure, value type): `mutating func alertsFor(readings: [PaceReading]) -> [LaneAlert]` where `LaneAlert` is `{kind: LaneKind, message: String}`. `PaceNotifier.post(_ alert: LaneAlert)` (thin UNUserNotificationCenter wrapper).

- [ ] **Step 1: Write the failing tests** — create `Tests/PaceCoreTests/NotificationGovernorTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class NotificationGovernorTests: XCTestCase {
    private func reading(_ kind: LaneKind, alarmed: Bool, resetDate: Date) -> PaceReading {
        let lane = LaneUsage(kind: kind, percentUsed: 50, resetDate: resetDate, windowLength: 5 * 3600)
        return PaceReading(lane: lane, percentElapsed: 20, isAheadOfPace: alarmed,
                           projectedCapDate: nil, isAlarmed: alarmed, capBeforeReset: nil)
    }

    func testFiresOnceOnUpwardCrossingOnly() {
        var governor = NotificationGovernor()
        let reset = Date(timeIntervalSince1970: 1_787_204_000)
        XCTAssertTrue(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)]).count == 1)
        // Same alarmed state on the next tick: already notified — stay silent.
        XCTAssertTrue(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)]).isEmpty)
    }

    func testReArmsWhenLaneDropsBackBelow() {
        var governor = NotificationGovernor()
        let reset = Date(timeIntervalSince1970: 1_787_204_000)
        _ = governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)])
        _ = governor.alertsFor(readings: [reading(.session, alarmed: false, resetDate: reset)])
        XCTAssertEqual(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)]).count, 1)
    }

    func testReArmsOnWindowReset() {
        var governor = NotificationGovernor()
        let reset1 = Date(timeIntervalSince1970: 1_787_204_000)
        _ = governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset1)])
        // New window (later resetDate), still alarmed → a fresh event.
        let reset2 = reset1.addingTimeInterval(5 * 3600)
        XCTAssertEqual(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset2)]).count, 1)
    }

    func testIndependentPerLane() {
        var governor = NotificationGovernor()
        let reset = Date(timeIntervalSince1970: 1_787_204_000)
        _ = governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)])
        let alerts = governor.alertsFor(readings: [
            reading(.session, alarmed: true, resetDate: reset),
            reading(.allModelsWeek, alarmed: true, resetDate: reset)
        ])
        XCTAssertEqual(alerts.map(\.kind), [.allModelsWeek])
    }
}
```

- [ ] **Step 2: Run to verify failure**, then implement `Sources/PaceCore/NotificationGovernor.swift`:

```swift
import Foundation

public struct LaneAlert: Equatable, Sendable {
    public let kind: LaneKind
    public let message: String
}

/// Edge-armed alerting: one notification per lane when it CROSSES into the
/// alarm state; re-armed when it drops back below or its window resets.
/// Level-triggered alerting would re-fire every refresh tick — notification
/// fatigue is how a signal gets ignored.
public struct NotificationGovernor {
    private struct Armed: Equatable { let resetDate: Date }
    private var notified: [LaneKind: Armed] = [:]

    public init() {}

    public mutating func alertsFor(readings: [PaceReading]) -> [LaneAlert] {
        var alerts: [LaneAlert] = []
        for reading in readings {
            let kind = reading.lane.kind
            if reading.isAlarmed {
                let alreadyNotifiedThisWindow = notified[kind]?.resetDate == reading.lane.resetDate
                if !alreadyNotifiedThisWindow {
                    notified[kind] = Armed(resetDate: reading.lane.resetDate)
                    alerts.append(LaneAlert(
                        kind: kind,
                        message: "\(reading.lane.effectiveDisplayName) is at \(reading.lane.percentUsed)% and running ahead of its window."
                    ))
                }
            } else {
                notified[kind] = nil // dropped below: re-arm
            }
        }
        return alerts
    }
}
```

Run `swift test --filter NotificationGovernorTests` → PASS.

- [ ] **Step 3: Create `Sources/Pace/PaceNotifier.swift`**

```swift
import Foundation
import UserNotifications
import PaceCore

/// Thin UNUserNotificationCenter wrapper. Permission is requested lazily on
/// the first alert; denial is tolerated silently — the icon remains the
/// primary signal and a menu bar utility must not nag for permissions.
@MainActor
final class PaceNotifier {
    private var requestedPermission = false

    func post(_ alert: LaneAlert) {
        let center = UNUserNotificationCenter.current()
        if !requestedPermission {
            requestedPermission = true
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Pace — ahead of pace"
        content.body = alert.message
        center.add(UNNotificationRequest(identifier: "pace-\(alert.kind.rawValue)-\(UUID().uuidString)",
                                         content: content, trigger: nil))
    }
}
```

- [ ] **Step 4: Wire into AppState.** Add stored properties `private var notificationGovernor = NotificationGovernor()` and `private let notifier = PaceNotifier()`. In `applySnapshot`, ONLY when `stale == false`, after computing `paceReadings`:

```swift
        // Cached data must never notify — a relaunch would re-announce an
        // alarm the user already saw.
        if !stale {
            for alert in notificationGovernor.alertsFor(readings: paceReadings) {
                notifier.post(alert)
            }
        }
```

Caveat for the implementer: `UNUserNotificationCenter.current()` requires a real app bundle; under `swift run` (bare binary) it can crash. Guard the notifier call: wrap `PaceNotifier.post`'s body in `guard Bundle.main.bundleIdentifier != nil else { return }`. Run `swift build && swift test` → green.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: edge-armed ahead-of-pace notifications (pure governor + UN wrapper)"
```

---

### Task 11: Makefile/Scripts — stable local signing certificate

**Files:**
- Modify: `Scripts/build-app.sh`
- Create: `Scripts/ensure-signing-cert.sh`

**Interfaces:** none (build tooling).

- [ ] **Step 1: Create `Scripts/ensure-signing-cert.sh`** (mode 755):

```bash
#!/bin/bash
# Ensure a stable local code-signing identity exists. Ad-hoc signatures have
# no persistent identity, so macOS re-prompts the Keychain grant for the
# Claude Code credentials item after every rebuild. A local self-signed cert
# gives Pace.app a stable identity: grant once, survives rebuilds.
# Nothing here enters the repo; the cert lives only in the login keychain.
set -euo pipefail

CERT_NAME="Pace Local Signing"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "$CERT_NAME"
  exit 0
fi

echo "Creating local signing certificate '$CERT_NAME' (one-time)..." >&2
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/cert.conf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = codesign_ext
prompt = no
[ dn ]
CN = Pace Local Signing
[ codesign_ext ]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
  -config "$TMP_DIR/cert.conf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
  -out "$TMP_DIR/cert.p12" -passout pass:pace >/dev/null 2>&1
security import "$TMP_DIR/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P pace -T /usr/bin/codesign >/dev/null

echo "$CERT_NAME"
```

- [ ] **Step 2: Use it in `Scripts/build-app.sh`** — replace the final `codesign --force --deep --sign - "$APP_BUNDLE"` line with:

```bash
# Prefer the stable local identity; fall back to ad-hoc (with a warning —
# ad-hoc means a Keychain re-prompt after every rebuild).
IDENTITY="$(./Scripts/ensure-signing-cert.sh || true)"
if [ -n "$IDENTITY" ] && security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE" \
    || { echo "warning: signing with '$IDENTITY' failed; falling back to ad-hoc" >&2; codesign --force --deep --sign - "$APP_BUNDLE"; }
else
  echo "warning: no stable signing identity; using ad-hoc (Keychain will re-prompt after rebuilds)" >&2
  codesign --force --deep --sign - "$APP_BUNDLE"
fi
```

- [ ] **Step 3: Verify** — `chmod +x Scripts/ensure-signing-cert.sh && make app` and confirm: build succeeds, and `codesign -dv .build/Pace.app 2>&1 | grep -E 'Authority|Signature'` shows either "Pace Local Signing" or (fallback path, with the warning printed) an ad-hoc signature. Note: `security import` may prompt the user; if the environment can't complete it non-interactively, the ad-hoc fallback firing WITH its warning is the acceptable outcome — record which path happened in the task report.

- [ ] **Step 4: Commit**

```bash
git add Scripts
git commit -m "build: stable self-signed identity so the Keychain grant survives rebuilds"
```

---

### Task 12: README rewrite + public comment sanitation

**Files:**
- Modify: `README.md`
- Modify: `Sources/Pace/UsageFetcher.swift`, `Sources/Pace/MenuView.swift`, `Sources/Pace/IconRenderer.swift`, `Sources/Pace/AppState.swift`, `Sources/Pace/PreferencesView.swift`, `Sources/PaceCore/UsagePanelTextExtractor.swift` (comment sanitation only)

- [ ] **Step 1: README.** Rewrite these sections (leave Install/Development/License structure intact, update content):
  - Intro: Pace now reads usage from the same API endpoint Claude Code's `/usage` command uses when Claude Code credentials are present, and falls back to the claude.ai browser-session scrape when they aren't. Two modes, chosen automatically.
  - Replace "Why it works the way it does" with **"How it gets the data"**: API mode (primary) — undocumented `api.anthropic.com/api/oauth/usage` endpoint, Bearer token read from the Keychain; browser mode (fallback) — v1's rendered-page read, kept for claude.ai users without Claude Code. Keep the honest what-breaks-when framing for both (endpoint shape churn / DOM churn).
  - New **"Security and data"** section (replaces "Privacy"), audit-anticipating:

```markdown
## Security and data

**API mode.** Pace reads Claude Code's OAuth access token from the macOS
Keychain (service `Claude Code-credentials`, including suffixed variants some
installs create). The token stays in memory and is sent only to
`api.anthropic.com` over HTTPS. Pace never writes it to disk, never logs it,
and never refreshes it — Claude Code owns token renewal. The Keychain read is
a native Security.framework call, so the access grant macOS asks you for is
scoped to Pace.app specifically — not to a shared CLI binary that any local
process could then use.

**Browser mode.** Without Claude Code credentials, Pace falls back to reading
the rendered claude.ai Settings → Usage page in a hidden WKWebView, exactly as
v1 did. Its only network traffic is the same claude.ai requests your normal
browser session would make. Signing out from Preferences clears the WKWebView
session data.

**On disk.** The cache at `~/Library/Application Support/Pace/last-usage.json`
holds the last usage percentages and timestamps. It never contains credentials.

Pace isn't affiliated with Anthropic. The usage endpoint is undocumented and
has already changed shape once; Pace handles both known generations and shows
last-known values (labeled as cached) if it changes again.
```

  - Behavior section: notifications now exist ("one notification when a lane crosses into ahead-of-pace; re-armed when the window resets; requires macOS notification permission"), refresh defaults (2 min API / 6 min browser), stale labeling (10 min).
  - Limitations: update accordingly; drop the "notifications are a non-goal" line.

- [ ] **Step 2: Comment sanitation.** Grep for internal codenames: `grep -rn "review finding\|C1\|I1\|I2\|I3\|I4\|I5\|Task [0-9]\|cross-model" Sources/`. For each hit, rewrite the comment to carry the reason itself (the pattern: delete the citation, keep/expand the rationale). Examples:
  - `UsageFetcher` isPresentingLogin comment: "…throws away whatever the user has typed (review finding C1) — every navigating path checks this first." → "…throws away whatever the user has typed — every navigating path checks this first."
  - `MenuView` bar color comment: drop "(review finding I2)", keep the white-on-white rationale, drop "Same fix IconRenderer already carries".
  - `IconRenderer`: drop "— review finding, cross-model" tails (three occurrences) and "(spec: …)"-style internal cites may stay only when they refer to the public spec file.
  - `PreferencesView`: drop "(review finding, cross-model: \"the toggle can lie\")" but keep the revert-to-real-status rationale.
  - `UsagePanelTextExtractor`: "— see review finding." → end the sentence at the rationale.
  - Any "Task N" references in `Sources/` comments (e.g. UsageFetcher's "Task 6's research", "Task 8's review finding"): rewrite to point at `docs/superpowers/research/live-usage-page-notes.md` or drop.
  Tests are exempt (not shipped surface, and some cite the fixtures' provenance meaningfully) — sanitize only `Sources/`.

- [ ] **Step 3: Verify** — `swift build && swift test` green; `grep -rn "review finding" Sources/` returns nothing.

- [ ] **Step 4: Commit**

```bash
git add README.md Sources
git commit -m "docs: v2 README (API-first security story); sanitize internal codenames from public comments"
```

---

### Task 13: Final verification — full suite, live API-mode run, checklist

**Files:** none created; this task produces a verification report.

- [ ] **Step 1: Full clean test + build** — `swift test 2>&1 | tail -5` (all pass), `swift build -c release` (succeeds), `make app` (bundle built + signed).

- [ ] **Step 2: Live API-mode smoke test.** Run the app briefly from the bundle: `open .build/Pace.app`, wait ~15s, then verify from the outside (no GUI interrogation available — use the observable artifacts):
  - `cat ~/Library/Application\ Support/Pace/last-usage.json | python3 -m json.tool` — must exist and contain 3 lanes with plausible percents (this machine has fresh Claude Code credentials; API mode should engage automatically).
  - `pkill -x Pace` afterward.
  - If the Keychain prompt blocks the fetch (first native read may prompt), note it in the report as expected first-run behavior — the cache file simply won't exist; do NOT fail the task on it, but say so explicitly.
- [ ] **Step 3: Confirm mode-selection fallback logic by inspection** (browser mode requires a credential-free machine — out of scope for automation): re-read `AppState.init` and `KeychainCredentialStore.hasAnyItem()` and confirm the `.none → browser` path constructs `ScrapeUsageSource` and no `ApiUsageSource`.
- [ ] **Step 4: Write the verification report** to the task output (not a file): test count, build result, cache file contents (percents only), which signing path Task 11 took, any deviations.

---

## Manual verification checklist (post-merge, human)

Not part of the agent tasks — for Ryan after push:
1. `make install`, launch, grant the Keychain prompt once → icon shows three bars within ~15s.
2. Rebuild (`make install` again), relaunch → NO new Keychain prompt (stable cert working).
3. Dropdown shows: three lanes, reset times, "Data source: Claude Code API" in Preferences.
4. Burn usage hard for 15+ min early in a session window → ahead-of-pace turns red only after the 10-min guard, one notification fires, no repeat on the next tick.
5. Quit + relaunch → cached values render immediately with "cached · Xm ago" until the first fetch lands.
```
