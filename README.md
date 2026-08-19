# Pace

A tiny macOS menu bar app that shows how your Claude usage is tracking against
its reset window — at a glance, without opening a browser tab.

Claude's Settings → Usage page tells you *what percent* of your session/weekly
limits you've used. It doesn't tell you whether that's *fast* or *fine* — 80%
used with 4 hours left in a 5-hour session is very different from 80% used
with 4 hours left in a 7-day window. Pace computes that and shows it as three
small bars in your menu bar, going red only when a lane is burning faster than
its window allows.

In v2, Pace automatically chooses between two modes: it reads the usage API
directly if Claude Code is installed, or falls back to a browser-session scrape
otherwise.

## What it looks like

Three stacked bars in the menu bar, one per lane (current session, all-models
week, Fable week). Each bar fills to the percent used, with a tick mark at the
percent of the window that has elapsed. Monochrome (matches Battery/WiFi/
Control Center) except a lane that's ahead of pace, which turns red — the only
color the icon ever shows. Click the icon for a dropdown with exact numbers,
reset times, and (for an ahead-of-pace lane) a projected time-to-cap. If
overage spend is enabled and nonzero, the dropdown also shows an "Extra usage"
dollar row. Preferences shows which data source is active.

## Behavior

- **Refresh rates:** Pace refreshes every 2 minutes in API mode and every 6
  minutes in browser mode.
- **Notifications:** Pace sends a native macOS notification when a lane crosses
  into ahead-of-pace. This is re-armed when the window resets or the lane drops
  back below the pace threshold. Requires macOS notification permission.
- **Cached data:** To ensure transparency, any data shown from the local cache
  (shown on relaunch or after failed refreshes) is labeled with its age
  (e.g., "cached · 5m ago").

## How it gets the data

**API mode (primary).** Pace reads the undocumented `api.anthropic.com/api/oauth/usage`
endpoint. The required Bearer token is read natively from the macOS Keychain
from the Claude Code credentials. This mode is used automatically whenever
Claude Code credentials are present.

**Browser mode (fallback).** Without Claude Code credentials, Pace falls back to
v1's method: reading the rendered claude.ai Settings → Usage page in a hidden
WKWebView. On first launch in this mode, a sign-in window will open.

In both modes, Pace is designed to fail gracefully. If the API endpoint shape
changes (API mode) or the page DOM changes (browser mode), Pace will show a
dimmed icon and display the last-known values (labeled as cached). It will
never show a wrong number and will never crash. See `docs/superpowers/specs/`
and `docs/superpowers/research/` for the design rationale and research.

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

## Install

Requires macOS 14+ and Swift 5.9+ (Xcode 15+, or the standalone Swift
toolchain).

```bash
git clone https://github.com/sternryan/pace.git
cd pace
make install
```

This builds a release binary, wraps it into `~/Applications/Pace.app`, and
signs it with a stable local self-signed certificate (created automatically by
`make app`/`make install`) so the macOS Keychain grant survives rebuilds.
Ad-hoc signing is used as a fallback. This is not distributed via the App Store
and is not notarized. Launch it once from `~/Applications`, then turn on
**Launch at Login** from Pace's Preferences if you want it to persist across
reboots.

## Development

```bash
make test    # swift test — PaceCore's pure-logic unit tests
make build   # swift build -c release
make run     # swift run Pace, for local iteration
make app     # build + wrap into .build/Pace.app, without installing
```

The codebase is split into two targets:

- **`PaceCore`** — pure Swift: usage-text parsing, pace math, icon geometry.
  Fully unit-tested, no AppKit/WebKit dependency.
- **`Pace`** — the SwiftUI `MenuBarExtra` app: the WKWebView scraper, icon
  rendering, dropdown UI, and preferences.

## Limitations

- Browser mode is subject to DOM churn; if Anthropic changes the Settings →
  Usage markup, the scraper may fail until updated.
- No App Store distribution or notarization — you're trusting a locally built
  binary signed with a local certificate. Build it yourself from source rather
  than running an unsigned prebuilt binary from someone else.

## License

MIT — see [LICENSE](LICENSE).
