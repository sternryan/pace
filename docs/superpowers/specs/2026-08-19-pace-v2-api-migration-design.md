# Pace v2 — OAuth usage API migration (API-first, browser fallback)

Date: 2026-08-19
Status: Approved (design), pending implementation plan
Supersedes: the data-source portion of `2026-08-18-pace-menubar-design.md`.
Research basis: `docs/superpowers/research/2026-08-19-swiftbar-prior-art-v2-direction.md`
(prior-art audit of agusalvarez6/claude-code-usage-swiftbar + live endpoint probe).

## Problem

v1's foundational feasibility finding — "no clean API integration available; the
only reliable way to get this data is the rendered page" — was falsified on
2026-08-19. `GET https://api.anthropic.com/api/oauth/usage`, authenticated with
the Claude Code OAuth access token from the macOS Keychain and the header
`anthropic-beta: oauth-2025-04-20`, returns the same plan-usage data as Claude
Code's `/usage` command, as clean JSON. v1's trace sampled only the web client;
Claude Code is a second client of the same quota with its own endpoint.

v2 makes the API the primary data source, keeps the v1 scraper as a fallback for
claude.ai users who don't run Claude Code, and folds in the highest-value craft
from the prior-art audit.

## Verified endpoint facts (live probe, 2026-08-19, Max plan)

- `limits[]` entries: `{kind, group, percent, severity, resets_at, scope,
  is_active}`. Observed kinds: `session` (group `session`), `weekly_all` and
  `weekly_scoped` (group `weekly`). The per-model weekly lane is
  `kind == "weekly_scoped"` with `scope.model != nil`; `scope.model.id` was
  `null`, so `scope.model.display_name` ("Fable") is a **label**, not a lane
  identity — identity is kind + scope presence, so a model rename or swap
  doesn't kill the lane.
- Severity values (from prior art + probe): `normal | warning | critical |
  exceeded`.
- Legacy top-level `five_hour` / `seven_day` objects (`utilization`,
  `resets_at`) are still present alongside `limits[]`. The endpoint has already
  changed shape once; the normalizer handles both generations.
- `extra_usage`: `{is_enabled, monthly_limit, used_credits, utilization,
  currency, disabled_reason, user_disabled, spend_limit_reached, ...}`; a
  parallel `spend` object carries its own `severity`. Amounts are minor units
  (cents).
- The response contains transient feature-flag keys (opaque codenames) that
  churn — the normalizer must ignore unknown keys and never fail on extras.
- ⚠⚠ **Keychain multiplicity (observed live):** multiple generic-password items
  can share the service name `Claude Code-credentials` (different `acct`
  values), plus suffixed variants (`Claude Code-credentials-<hex>`). A
  single-match lookup returns a stale item and reports "revoked/expired"
  forever even right after a successful login. The credential read MUST
  enumerate all matches and pick the latest non-expired credential.

## Non-goals

- No token refresh, ever. Claude Code owns renewal; Pace reads only. (This is
  also a security posture statement for the README.)
- No deletion of the scraper (it becomes the fallback), no App Store
  distribution, no notarization.
- No use of the `security` CLI for the Keychain read (widens the ACL grant to
  every CLI process — the exact weakness found in the prior art).

## Architecture

### UsageSource protocol (new seam)

```swift
protocol UsageSource {
    func fetch() async -> Result<UsageSnapshot, FetchStatus>
}
```

Two implementations. `AppState` owns exactly one, chosen at launch (see Mode
selection). The delegate-based `UsageFetcherDelegate` plumbing is replaced by
this result-returning call; `AppState` keeps its timer role.

### ApiUsageSource (primary)

1. **KeychainCredentialStore** — native `SecItemCopyMatching` with
   `kSecMatchLimitAll` over generic-password items whose service is
   `"Claude Code-credentials"` or a `"Claude Code-credentials-"`-prefixed
   variant (enumerate all generic passwords and filter on the service prefix;
   `kSecAttrService` has no native prefix query). Parse each item's JSON
   (`{claudeAiOauth: {accessToken, expiresAt, ...}}` or flat), drop entries
   with `expiresAt <= now`, return the credential with the **latest**
   `expiresAt`. Distinguishes three outcomes: credentials found / no items at
   all (Keychain-absent) / items exist but all expired.
2. **One HTTPS GET** to the usage URL, `Authorization: Bearer <token>`,
   `anthropic-beta: oauth-2025-04-20`, 10-second timeout. HTTP 401 → token
   invalid. Non-2xx → transient failure.
3. **ApiUsageNormalizer** (PaceCore, pure) — maps the JSON to `UsageSnapshot`:
   - Prefer `limits[]`: `session` → `.session` lane (window 5h),
     `weekly_all` → `.allModelsWeek` (window 7d), first `weekly_scoped` with
     `scope.model != nil` → `.fableWeek`, its display name taken from
     `scope.model.display_name` when present.
   - Fall back to legacy `five_hour`/`seven_day` when `limits[]` is missing
     (produces two lanes; the scoped lane is simply absent — the UI renders
     the lanes it gets).
   - Carry `severity` per lane; default `normal` when absent.
   - Extra usage from `extra_usage` (or legacy `spend.used.amount_minor`),
     dollars = minor units / 100.
   - Ignore all unknown keys. Missing/renamed *required* fields → normalizer
     returns nil → `FetchStatus.parseError` ("endpoint shape changed") — shape
     churn is a designed-for failure, exactly as DOM churn was in v1.

### ScrapeUsageSource (fallback)

The existing `UsageFetcher` (WKWebView scraper) wrapped behind `UsageSource`,
**lazily constructed** — API-mode users never instantiate the WKWebView, so
they never pay its 100–300MB idle memory or lifecycle complexity (retires
TODOS #1 and #3 for the primary path without deleting the code). Login-window
presentation and the post-login poll stay exactly as v1 built them, used only
in browser mode.

### Mode selection

Decided at launch (and re-evaluated on manual "Refresh now"):

- Keychain has any Claude Code credential item (even expired) → **API mode**.
- No item at all → **browser mode** (scraper + claude.ai sign-in window).

In API mode, an expired/revoked/401 token is NOT a mode switch: status becomes
`.tokenExpired`, the dropdown says "Open Claude Code and run /login", and
last-good data stays rendered. A Claude Code user never sees a claude.ai
sign-in window for a Claude Code auth problem. Preferences shows the active
mode as a read-only line ("Data source: Claude Code API" / "claude.ai
browser session").

## PaceCore changes (pure, tested)

- **`UsageSnapshot`** (new): `lanes: [LaneUsage]`, `extraUsage:
  ExtraUsage?`, `fetchedAt: Date`. Codable — this is also the persisted-cache
  format.
- **`LaneUsage`** gains `severity: LaneSeverity` (`normal | warning |
  critical | exceeded`, unknown strings → `normal`) and an optional
  `displayName` override for the scoped lane.
- **`PaceCalculator`**:
  - **MIN_ELAPSED guard** — no ahead-of-pace verdict and no projection until
    the window has ≥10 minutes of elapsed history (fixes the live v1 bug
    where 1% used > 0% elapsed at minute one turns the icon red).
  - **Server severity wins** — `critical`/`exceeded` forces the alarm state
    even when local pace math wouldn't; local ahead-of-pace still alarms on
    its own.
  - **"(resets first)"** — the projection carries whether the reset arrives
    before the projected cap, and the dropdown says so.
- **`FetchStatus`** gains `.tokenExpired` (remediation: open Claude Code)
  distinct from `.needsLogin` (browser mode's claude.ai sign-in).
- v1's parsers (`UsageParser`, `UsagePanelTextExtractor`) are untouched — they
  serve the fallback path.

## App-layer additions

- **Persisted last-good cache** — `UsageSnapshot` JSON in
  `~/Library/Application Support/Pace/last-usage.json`. Loaded at launch and
  rendered immediately; rendered on any fetch failure; labeled stale
  ("cached · Xm ago") once older than 10 minutes. Contains percentages and
  timestamps only — never credentials (README says so).
- **Overage row** — dropdown row "Extra usage $X.XX" when the snapshot reports
  extra usage enabled and nonzero (API mode only; the scrape path doesn't
  carry it).
- **Edge-armed notifications** — `UNUserNotificationCenter`, one notification
  per lane when it crosses INTO ahead-of-pace (or its severity crosses into
  `critical`/`exceeded`); re-armed when the lane drops back below / the window
  resets. Permission requested lazily on first cross, denial tolerated
  silently (icon remains the signal).
- **Refresh cadence** — default 120s in API mode (one small JSON GET), 360s in
  browser mode (unchanged). A user-customized `refreshInterval` still wins;
  the mode-dependent value applies only when no explicit preference has been
  set (v1 wrote the key unconditionally, so v2 treats a stored value equal to
  the old 360s default as "not customized" on first launch and migrates it).
- Icon and dropdown rendering otherwise unchanged — the pace concept (fill vs
  elapsed tick, red only when it matters) is the product and survives intact.

## Signing & distribution

`make install` gains a one-time step: generate a local self-signed signing
certificate ("Pace Local Signing") into the login keychain if absent, and sign
the app with it thereafter (fallback to ad-hoc if generation fails, with a
printed warning). Stable code identity means the user's Keychain ACL grant for
the credentials item survives rebuilds instead of re-prompting every update.
Nothing about the cert enters the repo.

## Public craft (from the prior-art audit)

- **README security section**, audit-anticipating: names the exact Keychain
  service(s) read, states the token is sent only to `api.anthropic.com` over
  HTTPS, never written to disk, never refreshed ("Claude Code owns token
  renewal"), that the cache contains no credentials — and that the native
  Keychain read scopes the macOS grant to Pace.app specifically rather than to
  a shared CLI binary. Undocumented-endpoint limitation and non-affiliation
  stated plainly. Browser-fallback section retains v1's disclosure.
- **Comment sanitation** — public comments must carry self-contained domain
  rationale; internal review codenames (I5, C1, …) are rewritten to say the
  reason itself.

## Error taxonomy (complete)

| Condition | Status | User-visible remediation |
|---|---|---|
| No Keychain items at all | browser mode | claude.ai sign-in window (v1 flow) |
| Items exist, all expired / 401 | `.tokenExpired` | "Open Claude Code and run /login"; last-good shown |
| Network failure / timeout / 5xx | transient | last-good shown, stale label after 10 min |
| JSON shape unrecognized | `.parseError` | "endpoint may have changed"; last-good shown |
| Scrape-path failures | unchanged v1 statuses | unchanged |

Never a wrong number, never a crash, never a silent mode switch.

## Testing

- **PaceCore unit tests** (the bulk): `ApiUsageNormalizer` against three fixture
  families — the 2026-08-19 live capture (sanitized), the legacy
  `five_hour`/`seven_day` shape, and adversarial cases (unknown keys, missing
  `limits`, no scoped lane, unknown severity, string/number type drift).
  `PaceCalculator` MIN_ELAPSED guard, severity override, resets-first flag.
  `UsageSnapshot` cache round-trip including forward-compat decode (extra
  fields present).
- **KeychainCredentialStore selection logic** tested pure by extracting
  "pick latest non-expired from N parsed candidates" into PaceCore.
- **Manual verification checklist** (in the plan): API mode end-to-end,
  expired-token message (temporarily doctored item), Keychain-absent → browser
  mode, notification firing and re-arm, rebuild-without-reprompt under the
  local cert.

## Rollout

Single branch of work on `main` (per repo workflow), pushed when the
fresh-context grade passes. v1 behavior remains reachable (browser mode), so
there is no migration step for existing users beyond `make install`; API mode
activates automatically for anyone with Claude Code credentials.
