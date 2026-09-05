# Pace — deferred items

Captured from the 2026-08-18 eng review. Each was an explicit "keep as
designed, revisit if it turns out to matter" call — not an oversight.

## 1. WKNavigationDelegate-based load waiting

**What:** Replace the fixed `Task.sleep` waits in `UsageFetcher` (3s initial
load, 0.5s per click) with a real `WKNavigationDelegate` "page ready" signal.

**Why:** On a slow connection, the fixed sleeps can produce a false
`.navigationFailed`/`.needsLogin` even though nothing is actually broken.

**Pros:** Removes the false-positive class entirely; more correct engineering.

**Cons:** Real added complexity — a delegate class, continuation-based async
bridging — for a failure mode that's cosmetic (one dimmed icon until the next
6-minute tick self-heals), not data-damaging.

**Context:** Raised as Architecture finding 3 in the 2026-08-18 eng review
(see `docs/superpowers/plans/2026-08-18-pace-menubar-implementation.md` Task
8). Kept as-is deliberately. Revisit only if Task 15's manual verification
(or ongoing use) shows false failures happening often.

**Depends on:** Nothing — self-contained change to `UsageFetcher`.

## 2. Native notifications for ahead-of-pace alerts

**What:** Add a native macOS notification when a lane crosses from on/behind
pace into ahead-of-pace, instead of the icon color being the only signal.

**Why:** The spec explicitly chose passive-only alerting to start ("revisit
later if the passive signal turns out to be too easy to miss").

**Pros:** Harder to miss than a menu bar icon you have to glance at.

**Cons:** Notification fatigue risk; more code (UNUserNotificationCenter);
the whole point of the pace design was a glanceable, non-interrupting signal.

**Context:** Spec non-goal, `docs/superpowers/specs/2026-08-18-pace-menubar-design.md`
"Non-goals" section. Genuinely undecided — depends on real usage.

**Depends on:** Nothing — additive, doesn't change existing behavior.

## 3. Tear down/recreate the WKWebView between refreshes

**What:** Instead of a WKWebView + NSWindow living for the app's entire
lifetime, construct one lazily per-refresh (and per sign-in) and release it
after, since cookies persist in `WKWebsiteDataStore.default()` independent
of the WKWebView instance's lifetime.

**Why:** Cuts steady-state memory from continuous (~100-300MB the whole time
Pace runs) to ~3-5s of cost every 6 minutes.

**Pros:** Meaningfully lower idle memory footprint for a background utility.

**Cons:** Real lifecycle complexity — the login window needs to exist
on-demand for a user-initiated sign-in click, not just scheduled scrapes;
construct/teardown races; not a problem at the scale of one background
utility on a modern Mac.

**Context:** Raised as the Performance finding in the 2026-08-18 eng review.
Kept as designed — this was the explicitly chosen tradeoff from the design
phase ("Hidden WKWebView, own login" over alternatives). Revisit only if
Activity Monitor actually shows this mattering in practice.

**Depends on:** Nothing — self-contained change to `UsageFetcher` and how
`presentLoginWindow()`/`hideLoginWindow()` are wired.
