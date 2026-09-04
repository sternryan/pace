# Pace

A macOS menu bar app that shows how your Claude and Codex usage is tracking
against its reset windows — at a glance, without opening a browser tab.

The provider usage pages tell you *what percent* of your limits you've used.
They don't tell you whether that's *fast* or *fine* — 80% used with 4 hours
left in a 5-hour session is very different from 80% used with 4 hours left in
a 7-day window. Pace computes that and shows it as stacked bars in your menu
bar, going red only when a lane is burning faster than its window allows.

v3 unifies four sources into one report: Claude, Codex, a local "smithy"
compute lane, and local spend estimated from on-disk usage logs.

## What it looks like

The menu bar icon itself shows one lane at a time: a single mini progress
bar plus its percent, for whichever lane is pinned (or, with nothing pinned,
whichever lane the pacing engine picks as the headline — the tightest or
most-ahead one). The bar fills to percent used, with a tick mark at the
percent of the window elapsed. It's monochrome (matches Battery/WiFi/Control
Center) and turns red only when that lane is ahead of pace or capped — the
only color the icon ever shows — and dims to indicate a stale report.

Click the icon for a dropdown with every lane's own bar (Claude session,
Claude week, Fable week, Codex session, Codex week), exact numbers, reset
countdowns, a projected time-to-cap for any ahead-of-pace lane, the smithy
lane's state, and (if overage spend is enabled and nonzero) an "Extra usage"
dollar row — shown as text only, with no bar, since it isn't a pace lane.

## The four sources

- **Claude.** Reads the undocumented `api.anthropic.com` OAuth usage
  endpoint. The bearer token is read from the macOS Keychain, from the same
  item Claude Code's CLI already created and maintains — Pace never signs in
  on its own and never touches the token's renewal.
- **Codex.** Reads `chatgpt.com`'s `wham/usage` endpoint the same way the
  Codex CLI's own usage view does. If that's unavailable or the login looks
  stale, Pace falls back to scanning `~/.codex/sessions` for a local rate-limit
  estimate and marks the source `localFallback` with a `needsLogin` reason.
  Pace never writes `~/.codex/auth.json`; the Codex CLI owns renewal. If
  Pace's own poll finds the access token near expiry, it refreshes one in
  memory for its own subsequent polls, but never persists it back to disk.
- **Smithy.** A local compute lane, not a usage meter — its "usage" is
  whether the lane is actually available to you right now. Pace checks the
  fabric scheduler (`hearth:8085/v1/models`) for whether the lane is serving,
  and the GPU box's lease server (`anvil:8001/lease`) for whether that
  candidate is free, held, or wedged, and maps the pair to one of three
  states: `serving`, `leasedAway`, or `unreachable`. It is intentionally a
  three-state read, never a binary up/down — a scheduler or lease server that
  doesn't answer is `unreachable`, not silently treated as available.
- **Spend.** Estimated cost from local usage logs (`~/.claude/projects` and
  `~/.codex/sessions`), parsed by vendored scanners from the open-source
  `openusage` project (see `Sources/PaceCore/Vendor/VENDORED.md` for exactly
  what was vendored, from where, and what was changed). This drives the
  hourly burn-rate series used for time-to-cap projections; it is not billing
  data and is not sent anywhere.

## Pacing math

- A lane's status (`tooEarly`, `onPace`, `ahead`, `capped`) compares percent
  used against percent of the window elapsed, with a 5-percentage-point slack
  band so noise near the boundary doesn't flip status back and forth, and a
  15-minute minimum-elapsed guard so a window that just opened doesn't read
  as "ahead" off a single burst.
- Where a lane has enough burn-rate history (from an 8-day hourly series
  built from the spend logs), an ahead-of-pace lane gets a projected
  time-to-cap; otherwise the projection falls back to a plain percent-rate
  extrapolation, or is omitted if there isn't enough data yet.
- **Caveat — overage dollar figure is unverified.** The extra-usage endpoint
  returns a raw integer credits/cents figure with no documented scale; Pace
  divides by 100 to get dollars and truncates. That divisor has not been
  confirmed against a real overage bill. Treat the "Extra usage" row as
  directional, not authoritative.
- **Caveat — both usage endpoints are undocumented.** `api.anthropic.com`'s
  OAuth usage endpoint and `chatgpt.com`'s `wham/usage` endpoint are internal
  endpoints their own official clients use, not public APIs, and both can
  change shape without notice. Pace is designed to fail toward a dimmed,
  clearly-labelled cached value rather than show a wrong number.

## Install

Requires macOS 14+ and Swift 5.9+ (Xcode 15+, or the standalone Swift
toolchain). Not notarized and not distributed via the App Store — build from
source.

```bash
git clone https://github.com/sternryan/pace.git
cd pace
make install            # menu bar app, into ~/Applications/Pace.app
make install-cli        # `pace` CLI, into ~/.local/bin/pace
make install-statusline # Claude Code statusline segment
```

`make install` builds a release binary, wraps it into `~/Applications/Pace.app`,
and signs it with a stable local self-signed certificate (created automatically
by `make app`/`make install`) so the macOS Keychain grant survives rebuilds.
Ad-hoc signing is used as a fallback. Launch it once from `~/Applications`,
then turn on **Launch at Login** from Pace's Preferences if you want it to
persist across reboots. Preferences also has a refresh-interval choice (1, 2,
or 5 minutes) and whether the icon is pinned in the menu bar.

## CLI

`make install-cli` installs `pace` to `~/.local/bin/pace`. By default it reads
`report.json` straight off disk (`~/Library/Application Support/Pace/report.json`)
with no network call at all, and only fetches in-process (which may hit the
Keychain directly) if that file doesn't exist yet. `--refresh` is the one path
that talks to the app: it `POST`s `/v1/refresh` on the running app's loopback
server and prints the fresh report; if the app isn't running, it falls back
to the same in-process fetch.

```
pace                # human-readable report
pace --json         # report.json verbatim, sorted keys, pretty-printed
pace --refresh      # force a fresh fetch before printing (via the app if it's running)
pace --help
```

## Loopback API

While the app is running, it serves a small local-only HTTP API on
`127.0.0.1:6737` (loopback interface only — never bound to any other
interface):

- `GET /v1/report` — the current cached `PaceReport` as JSON.
- `POST /v1/refresh` — force a fresh fetch across all four sources, then
  return the new report.

Both the CLI and the loopback endpoint serialize the same `PaceReport` type,
with whole-second ISO-8601 timestamps and unescaped slashes, so `pace --json`
and `curl 127.0.0.1:6737/v1/report` should always agree (barring a refresh
racing between the two calls).

The report is also written to disk at
`~/Library/Application Support/Pace/report.json` on every refresh, which is
what the CLI's non-`--refresh` path and the statusline segment read.

## Claude Code statusline segment

`make install-statusline` copies `Scripts/pace-statusline-segment.sh` to
`~/.claude/hooks/pace-statusline-segment.sh`. It's called from
`~/.claude/bin/statusline.sh`, reads `report.json` directly (no network, no
dependency on the app being installed beyond having written that file at
least once), and prints nothing if the file is missing or more than 10
minutes stale.

## Security and data

Pace reads Claude Code's OAuth access token from the macOS Keychain (service
`Claude Code-credentials`, including suffixed variants some installs create).
The token stays in memory and is sent only to `api.anthropic.com` over HTTPS.
Pace never writes it to disk, never logs it, and never refreshes it — Claude
Code owns token renewal.

Discovery of the Keychain items is a native Security.framework call
(attributes only). The decrypt itself runs `/usr/bin/security
find-generic-password`, with a native read as fallback. This is deliberate:
Claude Code creates its item with `security add-generic-password -U`, so
`/usr/bin/security` is already on that item's ACL whether or not Pace uses it
— shelling out grants no access that did not already exist. A Pace-scoped
grant would be worse in practice, because every `claude` launch rewrites the
item and wipes the grant, so the "Always Allow" you clicked is gone by the
next poll. Do not "harden" this back to a Keychain-API-only read; that has
been tried and reintroduces the prompt-on-every-poll bug.

On disk, `~/Library/Application Support/Pace/report.json` holds the full
computed report (percentages, reset times, lane states, spend estimates). It
never contains credentials, and the Codex/Claude usage-log scan never leaves
the machine.

Pace isn't affiliated with Anthropic or OpenAI. Both usage endpoints are
undocumented and can change shape without notice; see the pacing-math
caveats above.

## Development

```bash
make test              # swift test — PaceCore's pure-logic unit tests
make build              # swift build -c release
make run                # swift run Pace, for local iteration
make app                # build + wrap into .build/Pace.app, without installing
make cli                # build the pace-cli product only
```

The codebase is split into three targets — see this repo's `CLAUDE.md` for
where things live. `PaceCore` stays free of AppKit and WebKit so its parsing
and pacing logic is fully unit-testable; `Pace` is the SwiftUI menu bar app;
`PaceCLI` is the standalone `pace` binary.

## Limitations

- v2's native macOS notifications aren't wired up in v3 — `NotificationGovernor`
  (`Sources/PaceCore/NotificationGovernor.swift`) and `PaceNotifier`
  (`Sources/Pace/PaceNotifier.swift`) are kept but unused; the popover is the
  only surface for an ahead-of-pace alarm right now.
- No App Store distribution or notarization — build it yourself from source
  rather than running an unsigned prebuilt binary from someone else.
- No telemetry, no iCloud sync, no auto-update.
- The smithy lane's tri-state read depends on two internal hosts
  (`hearth:8085`, `anvil:8001`) being reachable on your network; if either
  isn't, the lane reads `unreachable`, never a guessed `serving`.

## License

MIT — see [LICENSE](LICENSE).
