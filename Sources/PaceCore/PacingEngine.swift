import Foundation

public enum PacingEngine {
    static let minimumUsedForBurnProjection = 2

    public static func report(snapshots: [ProviderSnapshot], now: Date) -> PaceReport {
        // A duplicate provider in the input must not trap — keep whichever
        // snapshot was fetched more recently.
        let byProvider = Dictionary(snapshots.map { ($0.provider, $0) }) { a, b in
            a.fetchedAt >= b.fetchedAt ? a : b
        }
        let burn = byProvider[.spend]?.burn
        let laneState = byProvider[.smithy]?.laneState

        var windows: [WindowVerdict] = []
        var seenKinds: Set<LaneKind> = []
        for p in [ProviderID.claude, .codex] {
            guard let s = byProvider[p] else { continue }
            for lane in s.lanes {
                // A lane kind must appear at most once — a duplicate (e.g.
                // two codexSession lanes from a race between the live fetch
                // and a local fallback) would double-count in pickHeadline's
                // aggregate scans. Keep the first (the one already fresher,
                // per the provider-level dedupe above).
                guard seenKinds.insert(lane.kind).inserted else { continue }
                windows.append(verdict(for: lane, snapshot: s, burn: burn, now: now))
            }
        }

        let headline = pickHeadline(windows)
        let advice = advice(for: headline, laneState: laneState)
        let providers = snapshots.map {
            ProviderStatus(provider: $0.provider, source: $0.source, fetchedAt: $0.fetchedAt, error: $0.error?.message)
        }
        let stale = snapshots.contains { $0.error != nil || $0.source == .cache }
        return PaceReport(generatedAt: now, headline: headline, advice: advice, windows: windows,
                          laneState: laneState, burn: burn, providers: providers, stale: stale)
    }

    static func verdict(for lane: LaneUsage, snapshot: ProviderSnapshot, burn: BurnSeries?, now: Date) -> WindowVerdict {
        // The overage lane's "percentUsed" is actually a raw dollar figure
        // (see ClaudeProvider), not a percent of anything with a window or a
        // pace to be ahead/behind of — it always reads onPace, with no
        // projection, and its own dollar-labelled verdict line.
        if lane.kind == .overage {
            return WindowVerdict(kind: lane.kind, provider: lane.kind.provider, percentUsed: lane.percentUsed,
                                 percentElapsed: nil, resetsAt: lane.resetDate, status: .onPace,
                                 projectedCapAt: nil, resetsFirst: false, projectionBasis: .none,
                                 severity: lane.severity, source: snapshot.source, fetchedAt: snapshot.fetchedAt,
                                 verdict: "Extra usage: $\(lane.percentUsed) used (unverified ÷100 of raw credits)")
        }

        var status = PaceCalculator.status(for: lane, now: now)
        // Server-asserted alarm wins (v2 parity): the server can see caps
        // the local pace model can't, so a critical/exceeded severity
        // promotes an otherwise-calm verdict to `.ahead` rather than being
        // silently dropped once `status` has already been computed.
        if lane.severity.isAlarming, status == .onPace || status == .tooEarly {
            status = .ahead
        }
        let elapsedFrac = PaceCalculator.elapsedFraction(for: lane, now: now)
        let elapsedPct = elapsedFrac.map { Int($0 * 100) }

        var cap: Date? = nil
        var basis: ProjectionBasis = .none
        if status != .tooEarly, status != .capped, let w = lane.windowLength, w > 0 {
            let start = lane.resetDate.addingTimeInterval(-w)
            let remainingPct = Double(100 - lane.percentUsed)
            // Burn attribution (BurnSeries) is per provider, not per model —
            // a scoped lane like fableWeek shares its provider's token
            // stream with every other Claude lane, so "tokens since window
            // start" can't be isolated to just this lane. Scoped lanes
            // always use the plain percent-rate projection instead.
            if lane.kind != .fableWeek, let burn, lane.percentUsed >= minimumUsedForBurnProjection {
                // The burn series only covers a trailing window (see
                // BurnSeries.hourly). A lane whose window is longer than that
                // coverage (a weekly lane against a few hours of buckets)
                // would collapse "tokens since window start" into a tiny
                // slice of real usage and wildly overstate the rate — only
                // trust burnRate when the earliest bucket for this provider
                // actually reaches back to the window start.
                let earliestStart = burn.hourly.filter { $0.provider == lane.kind.provider }.map(\.start).min()
                if let earliestStart, earliestStart <= start {
                    let attributed = burn.tokens(for: lane.kind.provider, from: start, to: now)
                    let ratePerSec = burn.rate(for: lane.kind.provider, now: now)
                    if attributed > 0, ratePerSec > 0 {
                        let tokensPerPct = Double(attributed) / Double(lane.percentUsed)
                        cap = now.addingTimeInterval(remainingPct * tokensPerPct / ratePerSec)
                        basis = .burnRate
                    }
                }
            }
            if cap == nil, let c = PaceCalculator.reading(for: lane, now: now).projectedCapDate {
                cap = c; basis = .percentRate
            }
        }
        let resetsFirst = cap.map { $0 >= lane.resetDate } ?? false
        if resetsFirst { cap = nil }

        return WindowVerdict(kind: lane.kind, provider: lane.kind.provider, percentUsed: lane.percentUsed,
                             percentElapsed: elapsedPct, resetsAt: lane.resetDate, status: status,
                             projectedCapAt: cap, resetsFirst: resetsFirst, projectionBasis: basis,
                             severity: lane.severity, source: snapshot.source, fetchedAt: snapshot.fetchedAt,
                             verdict: verdictLine(lane: lane, elapsedPct: elapsedPct, status: status,
                                                  cap: cap, resetsFirst: resetsFirst, now: now))
    }

    static func verdictLine(lane: LaneUsage, elapsedPct: Int?, status: PaceStatus, cap: Date?, resetsFirst: Bool, now: Date) -> String {
        let name = lane.effectiveDisplayName
        let elapsedText = elapsedPct.map { "\($0)% elapsed" } ?? "no window"
        let resetText = "resets " + PaceFormatter.shortClock(lane.resetDate, now: now)
        switch status {
        case .tooEarly: return "\(name): \(lane.percentUsed)% used, too early to judge (\(resetText))"
        case .capped:   return "\(name): capped (\(resetText))"
        case .ahead, .onPace:
            if let cap { return "\(name): \(lane.percentUsed)% used, \(elapsedText), caps \(PaceFormatter.shortClock(cap, now: now)) at this rate (\(resetText))" }
            if resetsFirst { return "\(name): \(lane.percentUsed)% used, \(elapsedText), \(resetText) first" }
            return "\(name): \(lane.percentUsed)% used, \(elapsedText) (\(resetText))"
        }
    }

    static func pickHeadline(_ windows: [WindowVerdict]) -> WindowVerdict? {
        // The overage lane isn't a pace lane — it has no window, no
        // elapsed fraction, and its "percentUsed" is a raw dollar figure,
        // so it must never be eligible as the headline.
        let candidates = windows.filter { $0.kind != .overage }
        let ahead = candidates.filter { $0.status == .ahead || $0.status == .capped }
        if !ahead.isEmpty {
            return ahead.min { a, b in
                switch (a.projectedCapAt, b.projectedCapAt) {
                case let (x?, y?): return x != y ? x < y : a.percentUsed > b.percentUsed
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.percentUsed > b.percentUsed
                }
            }
        }
        return candidates.filter { $0.status != .tooEarly }
            .max { ($0.percentUsed - ($0.percentElapsed ?? 0)) < ($1.percentUsed - ($1.percentElapsed ?? 0)) }
    }

    static func advice(for headline: WindowVerdict?, laneState: LaneState?) -> String? {
        guard let h = headline, h.status == .ahead || h.status == .capped else { return nil }
        let other = h.provider == .claude ? "Codex" : "Claude"
        switch laneState {
        case .serving?:     return "move bulk/mechanical work to smithy (hearth:8085 local-heavy)"
        case .leasedAway?:  return "smithy GPU is leased; \(other) is the next lane"
        case .unreachable?, nil: return "smithy unreachable, check before routing there"
        }
    }
}
