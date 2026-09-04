import Foundation

public enum PacingEngine {
    static let minimumUsedForBurnProjection = 2

    public static func report(snapshots: [ProviderSnapshot], now: Date) -> PaceReport {
        let byProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        let burn = byProvider[.spend]?.burn
        let laneState = byProvider[.smithy]?.laneState

        var windows: [WindowVerdict] = []
        for p in [ProviderID.claude, .codex] {
            guard let s = byProvider[p] else { continue }
            for lane in s.lanes {
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
        let status = PaceCalculator.status(for: lane, now: now)
        let elapsedFrac = PaceCalculator.elapsedFraction(for: lane, now: now)
        let elapsedPct = elapsedFrac.map { Int($0 * 100) }

        var cap: Date? = nil
        var basis: ProjectionBasis = .none
        if status != .tooEarly, status != .capped, let w = lane.windowLength, w > 0 {
            let start = lane.resetDate.addingTimeInterval(-w)
            let remainingPct = Double(100 - lane.percentUsed)
            if let burn, lane.percentUsed >= minimumUsedForBurnProjection {
                let attributed = burn.tokens(for: lane.kind.provider, from: start, to: now)
                let ratePerSec = burn.rate(for: lane.kind.provider, now: now)
                if attributed > 0, ratePerSec > 0 {
                    let tokensPerPct = Double(attributed) / Double(lane.percentUsed)
                    cap = now.addingTimeInterval(remainingPct * tokensPerPct / ratePerSec)
                    basis = .burnRate
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
                             source: snapshot.source, fetchedAt: snapshot.fetchedAt,
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
        let ahead = windows.filter { $0.status == .ahead || $0.status == .capped }
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
        return windows.filter { $0.status != .tooEarly }
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
