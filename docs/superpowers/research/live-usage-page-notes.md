# Live claude.ai Usage Panel — Research Findings

Captured 2026-08-18 via claude-in-chrome browser automation against a real, logged-in
claude.ai session (plan: Max (5x)).

## Step 1: Navigation path confirmed

Avatar (bottom of left sidebar) → user menu → "Settings" → "Usage" tab. Matches the
path assumed in Tasks 3/7/8 of the plan. Confirmed by URL hash changing at each step:
`/new` → `/new#settings/general` → `/new#settings/usage`.

## Step 2: Codeable selectors (supersedes the plan's guessed text-match)

The plan's Task 8 placeholder guessed `clickButton(matching: "Ryan", exact: false)` for
the avatar button — i.e. matching on the user's own display name. That works but is
fragile (breaks if the display name changes) and was never actually verified. Live DOM
inspection found **stable `data-testid` attributes on all three navigation elements**,
which should be used instead:

| Step | Selector | Notes |
|---|---|---|
| Avatar / user menu button | `[data-testid="user-menu-button"]` | `<button data-testid="user-menu-button" aria-haspopup="menu" ...>`. Not tied to display name — safe for any account. |
| Settings menu item | `[data-testid="user-menu-settings"]` | `<div role="menuitem" data-testid="user-menu-settings">`. Click the div directly (or its child), not a `<button>` — role="menuitem" on a div. |
| Usage tab | `[data-testid="usage-settings"] button` | The `data-testid` is on the parent `<li>`; the clickable element is the `<button>` inside it. |

None of these use generated/hashed class names — they're stable, intentional test
hooks. **Task 8's `clickThroughToUsagePanel()` should use these `data-testid` selectors
via `document.querySelector(...).click()` in its JS, instead of the text-content-match
`clickButton(matching:exact:)` helper for these three specific clicks.** The direct-URL
redirect problem documented in Task 8 (`claude.ai/settings/usage` → `claude.ai/new#settings/usage`
without opening the modal) is unaffected — the click-through is still required, just
with more reliable selectors than guessed text.

## Step 3: Captured real panel text (verbatim)

Extracted via `document.body.innerText`, sliced from the `"Plan usage limits"` anchor:

```
Plan usage limits
Max (5x)
Current session
Resets in 2 hr 5 min
65% used
Weekly limits

Fable 5 is still included with your Max plan.
If you see a prompt to set up usage credits for it, restart Claude Code.
Learn more about usage limits
All models
Resets Sat 2:00 PM
20% used
Fable
Resets Sat 2:00 PM
25% used
Last updated: less than a minute ago
```

### Reconciliation against Task 3/7 fixtures (Step 6)

Compared against the fixture strings in `Tests/PaceCoreTests/UsageParserTests.swift` and
`Tests/PaceCoreTests/UsagePanelTextExtractorTests.swift`:

- **Percent format**: `"65% used"` — matches fixture format `"21% used"` exactly. No change needed.
- **Relative reset format**: `"Resets in 2 hr 5 min"` — matches fixture format `"Resets in 3 hr 53 min"` exactly (`"X hr Y min"`). No change needed.
- **Weekday reset format**: `"Resets Sat 2:00 PM"` — byte-for-byte identical to the fixture. No change needed.
- **Extra banner lines** (`"If you see a prompt to set up usage credits for it, restart Claude Code."` and `"Learn more about usage limits"`) appear between the Fable-5-banner and the `"All models"` anchor in the real text but were not in the Task 7 fixture. **This will not break `UsagePanelTextExtractor`** (Task 7, not yet implemented — checked against the plan's Task 7 code block): its planned chunking is anchor-to-anchor (`"Current session"` → `"All models"` → `"Fable"`), and `UsageParser.parsePercent`/`parseRelativeReset` both take the *first* match within a chunk, so extra non-matching lines before the real percent/reset text are harmless. Traced by hand against the plan's Task 7 code; no fixture or planned-implementation changes required.
- **Real "Fable" section header vs. "Fable 5 is still included..." banner substring**: confirmed the planned line-anchored regex (`(?m)^Fable$`) in the Task 7 code block correctly skips the banner sentence (not an exact-line match) and anchors on the real `"Fable"` header — exactly the collision the plan's own code comment already calls out. No change needed when Task 7 is implemented.

**Conclusion: no fixture changes required for Task 3, and no change needed to Task 7's
planned implementation (not yet written) when it is implemented.** The reconstructed
design-time fixtures turned out to be accurate.

## Step 4: Session window length — CONFIRMED via Anthropic support docs

Per the plan's explicit shortcut ("If Anthropic documents this value directly, record
that as the source instead"): Anthropic's help center confirms a fixed **5-hour**
session window for Pro/Max/Team/seat-based Enterprise plans.

> "how much of your plan's five-hour session limit you've used thus far"
> — https://support.claude.com/en/articles/9797557-usage-limit-best-practices

This is a within-session snapshot ("65% used", "Resets in 2 hr 5 min" remaining), not a
before/after observation spanning an actual reset — per the brief's own rule, that kind
of single-session snapshot is NOT valid evidence for window length on its own. It is not
used as evidence here. The support-doc citation above is the sole source for the
5-hour figure.

**Action for Task 8/9: `SessionWindow.confirmedLength` should be set to `5 * 3600` (18000
seconds), not left as `nil`**, with a comment citing the support article above as the
source. This lane can now get a real pace tick and projection, not just "no tick".

## Step 5: Findings summary (for Task 8/9 implementers)

1. Use `data-testid` selectors (`user-menu-button`, `user-menu-settings`,
   `usage-settings`) for the three click-through steps, not text-content matching.
2. No changes needed to `UsageParser` or `UsagePanelTextExtractor` — real text matches
   the fixture format exactly.
3. `SessionWindow.confirmedLength = 5 * 3600` (18000s), sourced from
   support.claude.com/en/articles/9797557-usage-limit-best-practices ("five-hour session
   limit"), applies to Pro/Max/Team/Enterprise plans.
