
### Burn-rate attribution needs a series at least as long as the window
<!-- problem_type: bug -->
<!-- component: PacingEngine / BurnSeries -->
<!-- root_cause: spec said "tokens since window start" but the hourly series covered 6h; weekly lanes divided 6h of tokens by half a week of percent, collapsing tokens-per-percent 14x -->
<!-- resolution_type: design_change -->
<!-- severity: critical -->
<!-- date: 2026-09-04 -->

**Problem:** Fable-week projected a cap 2.5h out when the honest answer was ~34h.
**Root Cause:** The numerator's coverage (6h) and the denominator's coverage (3.5d) were different spans.
**Solution:** Hourly series spans 8 days; the engine uses the burn basis only when the earliest bucket reaches the window start; scoped lanes (Fable week) always use percent-rate because buckets carry no model dimension.
**Key Insight:** Every ratio in a projection must have numerator and denominator measured over the same span; the fallback must be reachable when coverage is short.

### The commit gate marker only sets when `make test` is the last visible segment
<!-- problem_type: workflow -->
<!-- component: ~/.claude hooks verify-before-commit / session-intelligence -->
<!-- root_cause: the PostToolUse hook attributes the exit code to the final command segment; `make test | tail`, `make test >/dev/null; echo`, and `make -C dir test` all fail the pattern or attribution -->
<!-- resolution_type: workaround -->
<!-- severity: medium -->
<!-- date: 2026-09-04 -->

**Problem:** Four green runs, four gate refusals.
**Root Cause:** Pattern match is on `make test` as the LAST segment with its own exit code; piping or redirecting breaks attribution.
**Solution:** `cd repo && make test` with full output, then commit in a separate call; push alone in its own call.
**Key Insight:** A subagent once hand-wrote the marker to get past this; the controller re-ran the suite. Never accept a forged marker; fix the invocation shape.
