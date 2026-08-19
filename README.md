# Pace

A tiny macOS menu bar app that shows how your Claude usage is tracking against
its reset window — at a glance, without opening a browser tab.

Claude's Settings → Usage page tells you *what percent* of your session/weekly
limits you've used. It doesn't tell you whether that's *fast* or *fine* — 80%
used with 4 hours left in a 5-hour session is very different from 80% used
with 4 hours left in a 7-day window. Pace computes that and shows it as three
small bars in your menu bar, going red only when a lane is burning faster than
its window allows.

## What it looks like

Three stacked bars in the menu bar, one per lane (current session, all-models
week, Fable week). Each bar fills to the percent used, with a tick mark at the
percent of the window that has elapsed. Monochrome (matches Battery/WiFi/
Control Center) except a lane that's ahead of pace, which turns red — the only
color the icon ever shows. Click the icon for a dropdown with exact numbers,
reset times, and (for an ahead-of-pace lane) a projected time-to-cap.

## Why it works the way it does

There's no public API or documented endpoint for these usage numbers — a live
network trace of the Settings → Usage panel turned up no discoverable REST/
GraphQL call carrying them, only analytics beacons. The only reliable way to
get this data is to read the *rendered* page. So Pace keeps a hidden WKWebView
signed into claude.ai (using the same cookie jar you'd get from Safari/Chrome
signing in), navigates it to the Usage panel on a timer, and reads the text
via `document.body.innerText`. See `docs/superpowers/specs/` and
`docs/superpowers/research/` for the full design rationale and the DOM
research that pinned down stable selectors.

This means Pace is inherently coupled to claude.ai's current page structure.
If Anthropic changes the Settings → Usage markup, Pace will show a dimmed icon
with a "couldn't refresh" note (never a wrong number, never a crash) until the
selectors are updated.

## Privacy

Everything runs locally. Pace's only network traffic is the same claude.ai
requests your normal browser session would make in the hidden WKWebView — it
does not send your usage data, session cookies, or anything else to any
third-party service. Signing out from Preferences clears the WKWebView's
session data.

## Install

Requires macOS 14+ and Swift 5.9+ (Xcode 15+, or the standalone Swift
toolchain).

```bash
git clone https://github.com/sternryan/pace.git
cd pace
make install
```

This builds a release binary, wraps it into `~/Applications/Pace.app`, and
ad-hoc code-signs it (no Apple Developer account needed, no notarization —
this isn't distributed via the App Store). Launch it once from
`~/Applications`, then turn on **Launch at Login** from Pace's Preferences if
you want it to persist across reboots.

On first launch — or whenever your claude.ai session expires — Pace opens a
sign-in window. Sign in once; cookies persist after that.

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

- Scrapes a page Anthropic doesn't guarantee the stability of. Selector
  breakage is a designed-for failure mode (dimmed icon, last-known values),
  not a hypothetical, but it can still happen.
- No App Store distribution or notarization — you're trusting a locally built,
  ad-hoc-signed binary. Build it yourself from source rather than running an
  unsigned prebuilt binary from someone else.
- Native notifications for ahead-of-pace alerts are a deliberate non-goal for
  now (see `TODOS.md`) — the signal is passive, icon-color only.

## License

MIT — see [LICENSE](LICENSE).
