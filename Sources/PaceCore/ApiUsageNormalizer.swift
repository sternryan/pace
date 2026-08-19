import Foundation

/// Maps /api/oauth/usage JSON to a UsageSnapshot. The endpoint is
/// undocumented and has already changed shape once, so this handles both
/// observed generations and treats anything else as "shape changed" (nil) —
/// the caller reports it; nothing here guesses or crashes. Unknown keys are
/// ignored everywhere: the live response carries transient feature-flag keys.
public enum ApiUsageNormalizer {
    public static func snapshot(fromJSON data: Data, now: Date) -> UsageSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        let lanes = lanesFromLimits(root["limits"] as? [[String: Any]])
            ?? lanesFromLegacy(root)
        guard let lanes, !lanes.isEmpty else { return nil }

        return UsageSnapshot(lanes: lanes, extraUsage: extraUsage(from: root), fetchedAt: now)
    }

    // MARK: current generation — limits[]

    private static func lanesFromLimits(_ limits: [[String: Any]]?) -> [LaneUsage]? {
        guard let limits, !limits.isEmpty else { return nil }
        var byKind: [LaneKind: LaneUsage] = [:]

        for entry in limits {
            guard let kindString = entry["kind"] as? String else { continue }
            // Identity is kind (+ scope presence for the per-model lane);
            // scope.model.display_name is only a label.
            let kind: LaneKind
            var displayName: String? = nil
            switch kindString {
            case "session":
                kind = .session
            case "weekly_all":
                kind = .allModelsWeek
            case "weekly_scoped":
                guard let scope = entry["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any] else { continue }
                kind = .fableWeek
                displayName = model["display_name"] as? String
            default:
                continue // unknown lane kinds are future features, not errors
            }
            guard byKind[kind] == nil else { continue } // first of each kind wins

            guard let percent = intPercent(entry["percent"]),
                  let resetDate = isoDate(entry["resets_at"]) else { continue }

            byKind[kind] = LaneUsage(
                kind: kind, percentUsed: percent, resetDate: resetDate,
                windowLength: kind == .session ? 5 * 3600 : 7 * 24 * 3600,
                severity: LaneSeverity(rawServerValue: entry["severity"] as? String),
                displayNameOverride: displayName
            )
        }

        // Display order matches the dropdown and icon: session, week, scoped.
        let ordered: [LaneKind] = [.session, .allModelsWeek, .fableWeek]
        let lanes = ordered.compactMap { byKind[$0] }
        return lanes.isEmpty ? nil : lanes
    }

    // MARK: legacy generation — top-level five_hour / seven_day

    private static func lanesFromLegacy(_ root: [String: Any]) -> [LaneUsage]? {
        func lane(_ key: String, _ kind: LaneKind, _ window: TimeInterval) -> LaneUsage? {
            guard let object = root[key] as? [String: Any],
                  let percent = intPercent(object["utilization"]),
                  let resetDate = isoDate(object["resets_at"]) else { return nil }
            return LaneUsage(kind: kind, percentUsed: percent, resetDate: resetDate, windowLength: window)
        }
        let lanes = [lane("five_hour", .session, 5 * 3600),
                     lane("seven_day", .allModelsWeek, 7 * 24 * 3600)].compactMap { $0 }
        return lanes.isEmpty ? nil : lanes
    }

    // MARK: overage

    private static func extraUsage(from root: [String: Any]) -> ExtraUsage? {
        if let eu = root["extra_usage"] as? [String: Any] {
            // used_credits ÷ 100 = dollars is UNVERIFIED against a nonzero
            // live response (every capture so far reads 0.0) — inferred from
            // the sibling `spend` object's amount_minor/exponent=2 shape. If
            // a live overage shows a 100x error, this divisor is the suspect.
            let credits = (eu["used_credits"] as? NSNumber)?.doubleValue ?? 0
            return ExtraUsage(dollarsUsed: credits / 100, isEnabled: eu["is_enabled"] as? Bool ?? false)
        }
        if let spend = root["spend"] as? [String: Any],
           let used = spend["used"] as? [String: Any],
           let minor = (used["amount_minor"] as? NSNumber)?.doubleValue {
            return ExtraUsage(dollarsUsed: minor / 100, isEnabled: minor > 0)
        }
        return nil
    }

    // MARK: field coercion

    private static func intPercent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return Int(number.doubleValue.rounded()) }
        // Coerce numeric strings ("67") — plausible type drift for an
        // undocumented endpoint; anything else is genuinely unreadable.
        if let string = value as? String, let parsed = Double(string) { return Int(parsed.rounded()) }
        return nil
    }

    private static func isoDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
