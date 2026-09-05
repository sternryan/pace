# Pace v3 revert to v2 — 2026-09-05

## Why

Ryan's call (2026-09-05 08:30 PDT): v3 was less useful day-to-day than the two things it replaced —
the two glanceable v2 menubar icons, and the openusage repo it was modeled on — and it cost roughly
248M Claude tokens to build. The reverted tree is `main` at `a5b4dea` (pace v2, Claude-only). v3
(commits `a5b4dea..b20d547`) is preserved on branch `v3-unified-pacing` and stays on `origin`; history
was not rewritten, the revert is a new commit on top of `a5b4dea`.

## What v3 got right (keep for a future pass)

- **Unified provider model** — one `Provider` protocol (`fetch() -> ProviderSnapshot`, never throws,
  errors live in the snapshot) covering Claude, Codex, smithy lane state, and local spend. Worth
  keeping the shape even if the UI goes back to two icons; a shared snapshot type made the pacing
  engine provider-agnostic.
- **Loopback JSON report** — `report.json` served on `127.0.0.1:6737/v1/report`, written atomically,
  carries per-provider `source`/`fetchedAt`/`error` so a consumer can tell live from stale from cache.
  The statusline segment (`~/.claude/bin/statusline.sh` pace segment) reads this file and is silent
  when it's absent — that behavior is harmless and is being left in place even with v3 reverted.
- **Smithy lane state as a first-class three-state signal** (`serving` / `leasedAway` / `unreachable`,
  never collapsed to two) — matches the house doctrine on lanes lying silently
  ([[infra_silent_false_negative_lanes]] equivalent in this repo's design doc). A held anvil lease
  pausing vLLM must read `leasedAway`, not `unreachable` — read the lease first.
- **ATS gotcha, worth remembering for any future bundled .app that talks Tailscale HTTP**: a bundled
  `.app` blocks cleartext HTTP to Tailscale IPs by default (App Transport Security) even when the
  same code works unbundled from a CLI. Needs per-host `NSExceptionAllowsInsecureHTTPLoads` for the
  specific tailnet IPs it calls.
- **`Pace`/`pace` product name collision**: SwiftPM products `Pace` (app) and `pace` (CLI) collide on
  case-insensitive APFS — the GUI build silently overwrote the CLI binary. Any future CLI+app split
  needs distinctly-named products (v3 used `pace-cli`).

## What v3 got wrong

- **A single verdict line replaced two glanceable icons.** The two v2 menubar icons (Claude window,
  Codex window) were faster to read at a glance than one collapsed headline-window verdict with a
  lane-advice line underneath. Consolidation traded scanability for cleverness.
- **The openusage-style scanners (vendored JSONL scanners, pricing pipeline, burn-rate series) never
  surfaced anything Ryan actually used.** The projection math (`projectedCapAt`, tokens-per-percent)
  and the 8-day burn history were built and tested but didn't change what Ryan looked at day to day —
  effort spent on infrastructure the product didn't need.

## Rule for next time

Before any rebuild in this space: a design pass with Ryan looking at actual mockups of the UI
**before** any code is written, not a written spec reviewed in the abstract. Once a design is picked,
use `/conduct` to drive the implementation through the smithy local lane rather than a full
subagent-driven Claude build — this class of well-specified, shape-constrained work is exactly what
`/conduct` is for, and it avoids re-running an expensive multi-round Claude build for a UI that turns
out not to earn its complexity.
