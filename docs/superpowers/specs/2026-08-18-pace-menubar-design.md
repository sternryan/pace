# Pace — macOS menu bar Claude usage indicator

Date: 2026-08-18
Status: Approved (design), pending implementation plan

## Problem

Checking Claude usage limits (current-session %, weekly all-models %, weekly
Fable %) requires opening claude.ai → Settings → Usage in a browser. There's
no CLI or public API surface for this data. The goal is to see it at a glance
in the macOS menu bar, without keeping a Chrome tab open, and specifically to
be able to tell whether usage is running *ahead of* or *behind* the pace of
each window's reset — not just the raw percentage.

## Feasibility finding (informs the whole design)

Investigated whether this data is reachable without a browser:

- `claude auth status` and local `~/.claude/stats-cache.json` only carry local
  session/message counts — never the plan-level quota percentages.
- A live network trace of claude.ai's Settings → Usage panel found no
  discoverable REST/XHR/GraphQL call carrying the usage numbers — only
  analytics beacons. The data is very likely embedded in an internal
  RSC/bootstrap payload, not a clean documented endpoint.

**Consequence:** there is no clean API integration available. The only
reliable way to get this data is to read the *rendered* Settings → Usage page
via an authenticated browser session. This is why the design below scrapes
DOM text rather than calling an API, and why scrape failure is treated as an
expected, designed-for state rather than an edge case — Anthropic changing
the page markup is a real, foreseeable failure mode, not a hypothetical.

## Non-goals

- No native macOS notifications (passive-only alerting; icon color is the
  signal). Revisit later if the passive signal turns out to be too easy to
  miss.
- No App Store distribution — ad-hoc signed, local build/install only.
- No attempt to reverse-engineer or call an internal claude.ai API. Scraping
  the rendered page is the deliberate, chosen approach, not a fallback.

## Architecture

SwiftUI macOS menu bar app (`MenuBarExtra`/`NSStatusItem`), target macOS 14+.

### Components

- **UsageFetcher** — owns a hidden WKWebView (attached to a real, off-screen
  window — WKWebView needs a window to execute JS reliably even when never
  shown). On a timer (default 6 minutes, user-configurable), navigates to
  claude.ai's Settings → Usage panel using the session cookies persisted in
  `WKWebsiteDataStore.default()`, waits for the panel to render, and reads
  the three lanes' text via `evaluateJavaScript`. On first run, or whenever
  the session is no longer authenticated, the same WKWebView is surfaced in
  a visible window so the user can sign in once; cookies persist after that.
- **UsageParser** — converts the raw scraped strings (e.g. "21% used",
  "Resets in 3 hr 53 min", "Resets Sat 2:00 PM") into structured `LaneUsage`
  values: percent used, reset target `Date`, window length. Weekly windows
  follow the fixed Sat 2:00 PM cadence read off the page (window length =
  7 days). The session window's total length is **not yet confirmed** — the
  page only ever shows time-remaining, not window length or start time.
  Needs empirical confirmation during implementation (e.g. observe the
  countdown across a full session or a reset boundary) before "% of window
  elapsed" can be computed for that lane; until confirmed, the session lane
  can still show %used and time-remaining without the pace tick/projection.
- **PaceCalculator** — pure function(s): percent used vs. percent of window
  elapsed → ahead / on-pace / behind-pace, plus a linear-extrapolation
  "projected to hit cap in ~Xh" figure, computed only when ahead of pace.
- **IconRenderer** — draws the menu bar icon into a template `NSImage`
  whenever `AppState` updates. Three stacked micro bars (one per lane), each
  with a tick mark at the % of window elapsed. Bars render in the system
  template tint (monochrome, blends with Battery/WiFi/Control Center) except
  a lane that is ahead of pace, whose fill breaks to red — the only color
  the icon ever shows, and only while that condition holds.
- **MenuView** (SwiftUI popover, opens on click) — three lane rows (name,
  %, bar + tick, "resets in Xh Ym" / "resets Sat 2:00 PM", "% of window
  elapsed"); a lane ahead of pace additionally shows a red "Projected to hit
  cap in ~Xh" line. No other verdict/status text on the row. Footer: Refresh
  now (with "updated Xm ago"), Open claude.ai usage, Preferences…, Quit.
- **PreferencesView** — refresh interval (default 6 min), launch-at-login
  toggle (default on), sign-out/re-login control.
- **AppState** — `@Observable` holder of the three `LaneUsage` values, fetch
  status (`ok` / `needsLogin` / `parseError`), and `lastSuccessAt`. Shared
  by `IconRenderer` and `MenuView`.

### Data flow

Timer fires (default every 6 min) → `UsageFetcher` scrapes the hidden
WKWebView → `UsageParser` structures the text → `PaceCalculator` annotates
pace/projection → `AppState` updates → `IconRenderer` redraws the status
item image → `MenuView` reflects the new state the next time it's opened.

### Error handling

All failure states are non-fatal and never blank the icon:

- **Not signed in** (WKWebView redirects to login) → `AppState.status =
  .needsLogin`. Icon shows the last-known values dimmed with a small ‼
  badge. Dropdown surfaces a "Sign in to claude.ai" action that reveals the
  WKWebView.
- **Parse failure** (expected DOM text not found — most likely cause:
  Anthropic changed the Usage page markup) → `AppState.status =
  .parseError`. Same dimmed-icon + ‼ treatment. Dropdown states plainly that
  the read failed and when it last succeeded, plus an "Open claude.ai
  usage" action to check by hand.
- **Network/offline** → same dimmed + ‼ treatment; retried on the next
  timer tick. No special backoff needed at a 6-minute cadence.

### Testing

- `UsageParser` and `PaceCalculator` are pure functions → real XCTest unit
  tests against a set of captured sample strings (normal, near-100%,
  just-reset, "hr"/"hrs" pluralization variance).
- `IconRenderer` output is checked by eye (Xcode preview / rendered
  `NSImage`) — not worth automating pixel-level menu bar rendering for a
  single-user tool.
- The live scrape against the real claude.ai Usage page **cannot** be unit
  tested (no fixtures for a real authenticated session). It is verified
  manually against the real account before any "this works" claim — this is
  a manual verification step, not something the test suite proves.

## Open risk (accepted, not a blocker)

This entire approach is contingent on claude.ai's rendered Usage page
keeping a readable structure. If Anthropic changes it, scraping breaks.
That's why parse failure is a first-class, designed-for state rather than
an afterthought — but it remains true that a markup change could silently
degrade the tool until it's fixed, since there is no alternative API to
fall back to.
