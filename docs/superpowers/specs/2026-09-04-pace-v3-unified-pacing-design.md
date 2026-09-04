# Pace v3: unified budget pacing (Claude + Codex + smithy + spend)

Date: 2026-09-04 · Status: DESIGN, awaiting Ryan's review · Supersedes: pace v2 (Claude-only), codex-pace (retired by this spec)

## 1. Why

pace (Claude only) and codex-pace (Codex only) each show a percent-used bar and an ahead/behind tick. Neither projects when a window will cap, neither knows whether the free smithy lane is available to absorb bulk work, neither feeds the Claude Code statusline, and neither keeps history. robinebers/openusage does most of this for ten providers in a 36.7k-line codebase built around telemetry, iCloud sync, and a customize UI that are not wanted here.

v3 is one app that answers a single question at a glance: **am I burning a Claude or Codex window faster than it resets, and if so where should the work go?**

Primary job (Ryan, 2026-09-04): budget pacing. Enforces house rule 9 (token discipline) by sight rather than memory.

## 2. Decisions taken

| Decision | Choice | Rejected |
|---|---|---|
| Codebase | Greenfield targets inside `~/pace`, reusing pace's auth and codex-pace's parser | Fork openusage and strip (25k lines of someone else's code remain); Python engine + Swift shell (a daemon to babysit) |
| Hard scanning code | Vendor openusage's incremental JSONL scanner, cache store, Claude/Codex log scanners, and pricing pipeline (MIT, with attribution) | Rewrite them (weeks of hidden bugs in exactly the wrong place) |
| Sources v1 | Claude subscription, Codex/ChatGPT Plus, smithy lane availability, local spend from logs | Cursor, Copilot, OpenRouter, others |
| Surfaces v1 | Menubar pin + popover, Claude Code statusline segment, CLI | ntfy push (Ryan declined), iCloud sync, Sparkle auto-update |
| Pacing model | Projection + lane advice | Tick-only (what exists), full budget planner (history charts, allowances) |
| codex-pace | Retired; its parser moves into PaceCore | Keep two apps |

Prior-art scan 2026-09-04: PARTIAL. Registry entry "Subscription usage pacing" written to `~/throughline/architecture/capabilities.md`. Extend pace/codex-pace, read smithy state from the existing scheduler and probes, never re-probe. gstackapp's burn-rate router is the wrong layer (Admin-API failover primitive) and is not touched.

## 3. Architecture

One SwiftPM package, macOS 14+, Swift 6 language mode, three targets:

- **`PaceCore`** (library, no UI, fully tested): providers, scanner, pricing, pacing engine, report model, cache, report writer, loopback server.
- **`PaceApp`** (executable): `MenuBarExtra` UI over `PaceCore`. Replaces today's `Sources/Pace`.
- **`pace`** (executable CLI): one-shot report as text or `--json`.

Existing PaceCore files kept and extended: `KeychainCredentialStore`, `ApiUsageSource` and `ApiUsageNormalizer` (Claude), `CodexRateLimitParser` (from codex-pace), `LaneKind`, `LaneSeverity`, `PaceCalculator`, `SnapshotCache`, `NotificationGovernor` (kept for later, unused in v1 UI).

Vendored from openusage commit `8321283f61335b9e1d942c61f38de042a431a0a6` into `Sources/PaceCore/Vendor/OpenUsage/`, MIT notice preserved, listed with upstream paths in `Sources/PaceCore/Vendor/VENDORED.md`:

- `Providers/IncrementalJSONLScanner.swift`, `JSONLScanCacheStore.swift` (+`Coordination`), `DailyUsageAccumulator.swift`
- `Providers/Claude/ClaudeLogUsageScanner.swift`
- `Providers/Codex/CodexLogFileParser.swift`, `CodexLogUsageScanner.swift` (+`Pricing`), `CodexUsagePricing.swift`
- `Pricing/*` (7 files)

Vendored files are edited only to drop dependencies on openusage types that are not brought along; every such edit is noted in `VENDORED.md`. Upstream drift is handled by re-diffing against that commit, never by re-copying blind.

### 3.1 Provider protocol

```swift
protocol Provider: Sendable {
    var id: ProviderID { get }                 // .claude, .codex, .smithy, .spend
    func fetch() async -> ProviderSnapshot     // never throws; errors are in the snapshot
}

struct ProviderSnapshot: Codable, Sendable {
    let provider: ProviderID
    let fetchedAt: Date
    let source: SnapshotSource                 // .api, .localFallback, .cache
    let windows: [UsageWindow]                 // empty for .smithy and .spend
    let lane: LaneState?                       // .smithy only
    let burn: BurnSeries?                      // .spend only
    let error: ProviderError?                  // present => windows may be from cache
}

struct UsageWindow: Codable, Sendable {
    let kind: LaneKind                         // fiveHour, weekAll, weekFable, codexFiveHour, codexWeekly, overage
    let used: Double                           // 0...1 (overage: credits used / 100, still unverified against a live nonzero value)
    let windowLength: TimeInterval
    let resetsAt: Date
    let serverSeverity: LaneSeverity?          // provider-asserted, shown as-is
}

enum LaneState: String, Codable { case serving, leasedAway, unreachable }   // three states, never two

struct BurnSeries: Codable, Sendable {
    let hourly: [HourBucket]                   // trailing 6h, tokens + cost per provider
    let daily: [DayBucket]                     // trailing 30d
}
```

### 3.2 Providers

- **ClaudeProvider**: Keychain token (per-(service,account) limit-one reads, pick latest non-expired `expiresAt`; the `kSecMatchLimitAll` batch read is errSecParam and must not return), `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`. Windows: 5h, all-models week, Fable week, overage. Expired token means "open Claude Code", never a mode switch. The v1/v2 WKWebView scraper is deleted in v3; Keychain-absent shows an error state.
- **CodexProvider**: token from `~/.codex/auth.json` (`tokens` block; refresh via `auth.openai.com` as openusage does), `GET https://chatgpt.com/backend-api/wham/usage`. Windows: 5h, weekly, per the `window_minutes`/`resets_at` the API reports. Fallback when the token is absent or the call fails: `CodexRateLimitParser` over `~/.codex/sessions/` (source = `.localFallback`).
- **SmithyProvider**: one GET to the fabric scheduler health on `hearth:8085` (tailnet). Maps to `serving` when the scheduler reports `local-heavy` bound and anvil not leased, `leasedAway` when the scheduler reports a lease holding the GPU, `unreachable` on timeout or non-200. It reads what the scheduler already says about the lease; it never SSHes to anvil and never runs `flux-lock-status` itself. Exact health field names are confirmed against the live endpoint during implementation and recorded in the provider's doc comment.
- **SpendProvider**: vendored scanners over `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/**`, priced by the vendored pipeline (supplement → LiteLLM → models.dev, cached on disk, refreshed daily). Emits `BurnSeries`. Cache under `~/Library/Application Support/Pace/log-scan-cache/`.

### 3.3 Pacing engine

Input: the four snapshots. Output: `PaceReport`.

Per `UsageWindow`:

- `elapsed = clamp((now - (resetsAt - windowLength)) / windowLength, 0, 1)`
- `status`: `.tooEarly` if elapsed < 15 min of wall time (pace's MIN_ELAPSED guard); `.ahead` if `used > elapsed + 0.05`; `.capped` if `used >= 1`; else `.onPace`.
- `tokensPerPercent`: tokens attributed to this provider since the window's start (from `BurnSeries`) divided by `used * 100`. Undefined if `used < 0.02` or no burn data; projection is then omitted, not guessed.
- `projectedCapAt`: `now + ((1 - used) * 100 * tokensPerPercent) / trailingHourTokenRate`. Omitted if the rate is zero. Clamped: if later than `resetsAt`, reported as "resets first".
- `verdict`: one line, e.g. "Fable week: 71% used, 54% elapsed, caps Thu 14:10 at this rate (resets Fri 09:00)".

Headline: the window whose `projectedCapAt` is soonest; ties broken by highest `used`. If no window is ahead, headline is the tightest by `used - elapsed`.

Lane advice (one line, only when headline is `.ahead` or `.capped`):

- smithy `serving` → "move bulk/mechanical work to smithy (hearth:8085 local-heavy)"
- smithy `leasedAway` → "smithy GPU is leased; Codex is the next lane" (or the reverse if Codex is the capped one)
- smithy `unreachable` → "smithy unreachable, check before routing there"

The engine is pure, deterministic, and unit-tested with fixed clocks. It never calls a model.

### 3.4 Report and cache

```swift
struct PaceReport: Codable { generatedAt, headline: WindowVerdict?, advice: String?, windows: [WindowVerdict], lane: LaneState?, providers: [ProviderStatus], stale: Bool }
```

Written atomically (temp file + rename) to `~/Library/Application Support/Pace/report.json` after every refresh. Served read-only on `127.0.0.1:6737/v1/report` (loopback only, GET only, no CORS wildcard, 8 concurrent connections max). Port 6737 avoids openusage's 6736 in case both run. The last good report is kept and shown with `stale: true` when any provider fails; per-provider `fetchedAt` and `source` are always present so the UI can name what it is trusting.

Refresh cadence: 2 min for Claude and Codex, 60 s for smithy (cheap, and lease state changes fast), spend scan incremental on every cycle. Refresh on popover open and on `⌘R`.

### 3.5 Surfaces

- **Menubar pin**: headline window as an 18-pt mini-bar plus percent. Tint red only when `.ahead` or `.capped`, grey when stale. Click opens the popover.
- **Popover**: windows grouped by provider (Claude, Codex), each with used/elapsed bars, reset countdown, projection line, and a small source tag (api / local / cache, with age). Below: smithy lane state and the advice line. Footer: last refresh, refresh button, Preferences, Quit.
- **Statusline**: `~/.claude/hooks/pace-statusline-segment.sh` (called from `~/.claude/bin/statusline.sh`, the current statusLine command) reads `report.json` with `jq`, no network, and prints one segment like `Fable wk 71%↑ caps 14:10 · 5h 32%`. If the file is older than 10 min it prints `pace stale`. `gsd-statusline.js` gains one line that shells to this script and appends the segment. If the script or file is absent the statusline is unchanged.
- **CLI**: `pace` prints the report as aligned text, `pace --json` prints `report.json` verbatim, `pace --refresh` forces a fetch through the running app's loopback API and falls back to an in-process fetch if the app is not running.

### 3.6 Preferences

Launch at login, refresh interval (1/2/5 min), which window pins to the menubar (default: headline, auto), 12/24h. Nothing else in v1.

## 4. Error handling

- A provider failure never blanks the others. Each provider returns a snapshot with `error` set and its last cached windows.
- Smithy is tri-state by construction; an unreachable scheduler is never rendered as "available" or as "leased".
- Token expiry: Claude shows "open Claude Code to refresh sign-in"; Codex shows "run `codex login`" and switches to the local-fallback source for windows.
- Log format change: the vendored parsers throw per-line; the scanner skips the line, counts it, and the popover shows "N unparsed lines" so a silent zero-spend day cannot pass as real.
- Pricing catalog unreachable: last cached catalog is used and cost lines carry an "as of <date>" tag; tokens still display.

## 5. Testing

`PaceCore` tests (XCTest, run by `make test` from the repo root and from `Sources/PaceCore`):

- Pacing engine: fixed-clock cases for each status, projection math, "resets first" clamp, tooEarly guard, headline selection, all three lane-advice branches, no-burn-data omission.
- Claude normalizer: recorded responses for legacy `five_hour`/`seven_day` and `limits[]` generations, Fable `weekly_scoped` lane, overage present and absent.
- Codex client + parser: recorded `wham/usage` response; session-file fixtures from codex-pace's existing tests.
- Smithy mapper: recorded scheduler health bodies for serving / leased / malformed, plus timeout.
- Spend: fixture JSONL directories with an unparsable line, verifying the unparsed count surfaces.
- Report writer: atomic write, stale flag, per-provider source tags.
- Loopback server: GET only, loopback bind, 404 elsewhere.

Not unit-tested by design: SwiftUI views, Keychain reads (manual check on this Mac), live endpoints.

## 6. Definition of done

1. `make test` green from the repo root and from a second directory using the documented command.
2. `PaceApp` running on this Mac with all four providers reporting `source: .api` (Claude, Codex), `serving`/`leasedAway` (smithy, matching `ssh anvil flux-lock-status` at the same minute), and a non-empty `BurnSeries`.
3. `pace --json` and `curl 127.0.0.1:6737/v1/report` return the same document.
4. A fresh Claude Code session shows the pace segment in its statusline; killing the app makes it read `pace stale` within 10 min.
5. `~/codex-pace` retired: its parser and tests merged, the repo archived on GitHub, `~/Applications/CodexPace.app` removed, and the login item gone.
6. `VENDORED.md` lists every vendored file, the upstream commit, and every local edit.
7. Fresh-context grader per house rule 2 before the public push.

## 7. Non-goals (v1)

ntfy or any push; iCloud or multi-Mac sync; auto-update; notarization or App Store; Cursor/Copilot/OpenRouter/other providers; history charts; daily allowances; writing to `lane-log.tsv`; any frontier-model call anywhere in the app.

## 8. Open items carried in

- Overage divisor (`used_credits ÷ 100`) still unverified against a nonzero live response (from pace v2). Verify during implementation or label the lane "unverified" in the popover.
- Exact scheduler health field names for lease state: confirm live, record in `SmithyProvider`.

## Execution notes 2026-09-04

- The shipped `PaceReport`/`WindowVerdict` field is `laneState`, not `smithy_state` or any other name implied elsewhere in this doc.
- §3.4 says the loopback server is "GET only" — superseded by §3.5 and the shipped code: `POST /v1/refresh` exists and is the CLI's `--refresh` path, in addition to `GET /v1/report`.
- §3.3's burn attribution is per provider, not per model — `BurnSeries` has no model dimension — so a scoped lane (`fableWeek`) always uses the plain percent-rate projection, never `burnRate`, regardless of how much burn history is available.
- 12/24-hour clock preference is deferred to the system locale (`PaceFormatter.shortClock` uses `Calendar.current`/`DateFormatter` defaults); no explicit user-facing toggle was built.
- `leasedAway` is verified only by fixture (`SmithyProviderTests`), not observed against a real held/wedged lease live — the field names are confirmed live per item 2 in `TODOS.md`, but the `leasedAway` *branch itself* has not been.
