# Pace — deferred items

## 1. Overage dollar divisor is unverified

**What:** Pace divides the extra-usage endpoint's raw credits/cents figure by
100 to get a dollar amount (`Sources/PaceCore/ApiUsageNormalizer.swift`).

**Why it's open:** That divisor was picked from the field's apparent scale,
not confirmed against a real overage bill. If a live overage ever shows a
100x-off dollar figure, this divisor is the first suspect.

**Depends on:** A real account actually incurring overage spend to check the
displayed figure against the billed amount.

## 2. Scheduler/lease field names confirmed 2026-09-04

**What:** `SmithyProvider` maps the fabric scheduler's `hearth:8085/v1/models`
response and the GPU box's `anvil:8001/lease` response to Pace's three-state
`LaneState`. The lease server's `state` field is `free`, `held`, or `wedged`
— confirmed live against the running services on 2026-09-04, not just read
out of a spec. `free` maps to `serving`; `held`/`wedged` map to `leasedAway`;
anything that doesn't answer maps to `unreachable`.

**Why it's open:** Field names and value sets on internal services can drift
without notice, same caveat as the two usage endpoints. Re-verify if the
smithy lane starts reading `unreachable` while the scheduler is known to be
up.
