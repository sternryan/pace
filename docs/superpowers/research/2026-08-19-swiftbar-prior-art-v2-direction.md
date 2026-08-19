# Prior art: claude-code-usage-swiftbar → what Pace v2 should be

Date: 2026-08-19
Source: https://github.com/agusalvarez6/claude-code-usage-swiftbar (MIT, single-file
SwiftBar/Node plugin, audited in full). Clone reviewed at commit HEAD as of this date.

## The headline: our feasibility finding is falsified

The 2026-08-18 design spec's foundational claim — "no clean API integration
available; the only reliable way to get this data is to read the rendered page" —
is wrong. There IS an endpoint, and it is the same one Claude Code's `/usage`
command uses:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <Claude Code OAuth access token>
anthropic-beta: oauth-2025-04-20
```

The token lives in the macOS Keychain under service `"Claude Code-credentials"`,
as JSON: `{claudeAiOauth: {accessToken, refreshToken, expiresAt, scopes,
rateLimitTier, subscriptionType}}`.

**Why our trace missed it:** we traced ONE client (the claude.ai web app, which
gets the numbers via its RSC/bootstrap payload) and concluded absence for the
ACCOUNT. Claude Code is a second client of the same quota with its own clean JSON
endpoint. Process lesson: when hunting for an API, enumerate every client of the
same data (web, CLI, mobile) before concluding absence.

## Response shape (from the plugin's normalizer — it has survived one schema churn)

Current generation: `limits: [{kind, percent, resets_at, severity}]` with kinds
including `"session"` and `"weekly_all"`. Legacy generation: top-level
`five_hour`/`seven_day` objects with `utilization` + `resets_at`. Overage:
`extra_usage: {used_credits (cents), is_enabled}` or `spend.used.amount_minor`.
Severity values seen: `normal | warning | critical | exceeded`.

## Verification gates — RESOLVED by live probe (2026-08-19, fresh login)

1. ✅ **All three lanes exist.** `limits[]` carries:
   - `{kind: "session", group: "session", percent, severity, resets_at, is_active}`
   - `{kind: "weekly_all", group: "weekly", ...}`
   - `{kind: "weekly_scoped", group: "weekly", scope: {model: {id: null,
     display_name: "Fable"}, surface: null}, ...}` — the Fable · week lane.
     Match on `kind == "weekly_scoped" && scope.model != nil`; `scope.model.id`
     is null, so display_name is the only model identifier (don't hard-match the
     string "Fable" for lane *identity* — a scoped weekly IS the per-model lane;
     use display_name only as the label).
   - Legacy top-level `five_hour`/`seven_day` objects are ALSO still present
     alongside `limits[]` (utilization + resets_at, no severity, no scoped lane).
2. ✅ `extra_usage` is richer than the plugin's read: `{is_enabled, monthly_limit,
   used_credits, utilization, currency, disabled_reason, user_disabled,
   spend_limit_reached, credits_ever_enabled}` plus a parallel `spend` object
   with severity. Many other top-level keys are feature-flag noise
   (codename keys churn) — normalizer must ignore unknown keys.
3. ⚠⚠ **Keychain trap found during the probe**: this machine has TWO generic-password
   items with service `"Claude Code-credentials"` (acct "Claude Code", stale
   April token; acct "ryanstern", the fresh one) plus a suffixed item
   `"Claude Code-credentials-dc26d867"` (also stale). A naive
   `find-generic-password -s` / single-match `SecItemCopyMatching` returns the
   STALE item and reports "revoked" forever — exactly what happened live. The
   v2 credential read MUST enumerate all matches (`kSecMatchLimitAll`) across
   the service (and its suffixed variants), parse each, and pick the credential
   with the latest non-expired `expiresAt`. His plugin has this bug latently.
4. The endpoint is undocumented and has already changed shape once. v2 keeps the
   dual-generation normalizer and treats shape churn as a designed-for failure
   (same posture v1 already takes toward DOM churn).

## What v2 deletes (all of it exists only because of the WKWebView choice)

- `UsageFetcher`'s hidden WKWebView + NSWindow, login-window lifecycle,
  `isPresentingLogin`/`isRefreshing` re-entrancy guards, the post-login poll task.
- All DOM selectors, `innerText` slicing, and the text parsers
  (`parsePercent`/`parseRelativeReset`/`parseWeekdayReset` calendar math) — the
  API returns integer percents and ISO `resets_at` directly.
- TODOS #1 (WKNavigationDelegate load-waiting) and #3 (WebView teardown /
  100–300MB idle memory) die outright. TODO #2 (notifications) becomes trivial.

What replaces it: a small `UsageClient` — `SecItemCopyMatching` Keychain read +
one `URLSession` call + a pure-Swift normalizer in PaceCore, unit-tested against
captured JSON fixtures of BOTH schema generations.

## Security note that favors native v2 over his approach

His plugin reads the Keychain via the `security` CLI, so the user's "Always
Allow" grant attaches to `/usr/bin/security` — after which ANY local CLI process
can read the token unprompted. A native Swift `SecItemCopyMatching` call scopes
the ACL grant to Pace.app specifically. v2 should do the native read and say so
in the README.

## Craft to steal (independent of data source)

- **Audit-anticipating README**: a "Security and data" section that names the
  exact Keychain item, the single host the token is sent to, what is never
  written to disk, and what the tool deliberately does NOT do (refresh tokens —
  "Claude Code owns token renewal", an ownership-boundary statement). Plus an
  explicit undocumented-endpoint limitation and a not-affiliated line.
- **Self-contained public comments**: his comments carry domain rationale a
  stranger can follow. Ours reference internal review-ticket codes ("review
  finding I5", "C1") that mean nothing outside our process — rewrite public-facing
  comments to carry the reason itself.
- **Persisted last-good cache with age-labeled staleness**: render the last
  successful result on failure; only label it stale after a threshold (his:
  10 min). Ours keeps last-known readings in memory only and loses them on
  relaunch.
- **MIN_ELAPSED guard on pace math**: he suppresses projections until 10 min of
  window history exists. Our `PaceCalculator` has no such guard — at minute 1 of
  a session, 1% used > 0% elapsed flags ahead-of-pace and the icon goes red on
  trivial usage. Add minimum-elapsed (and/or minimum-percent) hysteresis.
- **"(resets first)" on the projection**: the projected time-to-cap is annotated
  with whether the reset arrives before the cap — it answers the user's actual
  question ("do I need to care?").
- **Honor server severity over local thresholds**: `critical`/`exceeded` from the
  server wins even when the local percent math wouldn't alarm.
- **Edge-armed notifications**: fire once on upward crossing of the threshold,
  re-arm when the window resets below it. The pattern for TODO #2.
- **Overage lane**: he surfaces extra-usage dollars. We show no overage at all;
  once a plan is in overage that is the most pace-relevant number on the panel.
- **Hard deadlines on everything**: fetch timeout + keychain-exec timeout, so a
  hung call can't wedge a refresh cycle.

## What v1 already does better (keep, don't cargo-cult)

- The pace concept itself (used-vs-elapsed tick, red only when ahead of pace) —
  his shows raw % + projection; ours answers ahead/behind at a glance.
- A real unit-tested pure core (his repo has zero tests). v2 shrinks the untested
  app target and moves the new normalizer into the tested PaceCore lane.
- Appearance-aware native rendering; monochrome-until-alarm discipline.
- TODOS.md with reasoned deferrals; the spec/plan/research paper trail. The
  feasibility-finding correction should be made IN those docs, visibly — showing
  the update is itself good public craft.
