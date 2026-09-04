import Foundation

public enum CodexUsageNormalizer {
    /// Reads `rate_limit.primary_window` → `.codexSession`, `rate_limit.secondary_window` → `.codexWeek`.
    public static func lanes(fromJSON data: Data, now: Date) -> [LaneUsage]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = obj["rate_limit"] as? [String: Any] else { return nil }
        var out: [LaneUsage] = []
        for (key, kind) in [("primary_window", LaneKind.codexSession), ("secondary_window", .codexWeek)] {
            guard let w = rl[key] as? [String: Any], let lane = lane(kind: kind, window: w, now: now) else { continue }
            out.append(lane)
        }
        return out.isEmpty ? nil : out
    }

    static func lane(kind: LaneKind, window: [String: Any], now: Date) -> LaneUsage? {
        guard let usedAny = window["used_percent"] else { return nil }
        let used: Int
        if let d = usedAny as? Double { used = Int(d.rounded()) } else if let i = usedAny as? Int { used = i } else { return nil }
        let length = (window["limit_window_seconds"] as? Double).map { TimeInterval($0) }
        let reset: Date
        if let at = window["reset_at"] as? Double { reset = Date(timeIntervalSince1970: at) }
        else if let after = window["reset_after_seconds"] as? Double { reset = now.addingTimeInterval(after) }
        else { return nil }
        let sev: LaneSeverity = used >= 100 ? .exceeded : (used >= 90 ? .warning : .normal)
        return LaneUsage(kind: kind, percentUsed: min(max(used, 0), 100), resetDate: reset, windowLength: length, severity: sev)
    }
}
