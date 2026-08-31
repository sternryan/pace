# Codex Pace

Codex Pace is a small macOS menu-bar app that shows whether your Codex usage
is tracking ahead of its actual reset windows.

It displays one bar for every active Codex allowance window. In the common
case that is a 5-hour window and a weekly window, but the app does not assume
those values: it uses the `window_minutes` and `resets_at` values reported by
the installed Codex client. This lets it handle accounts that expose only a
weekly window, plan changes, and future window configurations.

Each bar fills to the percentage used and includes a tick for the percentage
of the window elapsed. A lane turns red only when usage is ahead of pace. The
menu shows exact percentages, reset times, and a projected cap time where the
available history supports it.

## Data and privacy

Codex writes rate-limit updates to local session event files in
`~/.codex/sessions/`. Codex Pace reads those files only. It does not read your
Codex credentials, make network requests, or scrape a web page.

If no rate-limit event is available, it keeps the last good values and labels
them as cached. Start or use Codex once to create a fresh event.

## Install

Requires macOS 14+ and Swift 5.9+ (Xcode 15+, or the standalone Swift
toolchain).

```bash
cd codex-pace
make install
```

This builds `CodexPace.app` and installs it at
`~/Applications/CodexPace.app`. Launch it once from Applications, then enable
Launch at Login in Preferences if desired.

## Development

```bash
make test
make build
make run
make app
```

`PaceCore` contains parsing, pace calculation, icon geometry, cache handling,
and notifications. `CodexPace` contains the menu-bar app and the read-only
local session source.

## Limitations

The local session event format is owned by Codex rather than a public stable
API. If it changes, Codex Pace will keep cached values and show a refresh
error instead of guessing. The parser is intentionally built around the
rate-limit fields present in current Codex session events.

Codex Pace is not affiliated with or endorsed by OpenAI.

## License

MIT. See [LICENSE](LICENSE).
