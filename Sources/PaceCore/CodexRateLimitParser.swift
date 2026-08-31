import Foundation

/// Decodes the rate-limit events Codex writes to its local session stream.
/// The stream is authoritative for the signed-in CLI session and carries the
/// actual windows for the current account rather than plan-specific guesses.
public enum CodexRateLimitParser {
    public static func snapshot(fromJSONLines text: String, now: Date = Date()) -> UsageSnapshot? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)),
                  let limits = event.payload?.rateLimits else { continue }

            let lanes = [
                lane(limits.primary, kind: .primary),
                lane(limits.secondary, kind: .secondary)
            ].compactMap { $0 }
            guard !lanes.isEmpty else { continue }
            return UsageSnapshot(lanes: lanes, extraUsage: nil, fetchedAt: now)
        }
        return nil
    }

    private static func lane(_ limit: Window?, kind: LaneKind) -> LaneUsage? {
        guard let limit, limit.windowMinutes > 0, limit.resetsAt > 0 else { return nil }
        let window = TimeInterval(limit.windowMinutes * 60)
        let label = label(for: limit.windowMinutes)
        return LaneUsage(kind: kind,
                         percentUsed: min(100, max(0, Int(limit.usedPercent.rounded()))),
                         resetDate: Date(timeIntervalSince1970: limit.resetsAt),
                         windowLength: window,
                         displayNameOverride: label)
    }

    private static func label(for minutes: Int) -> String {
        switch minutes {
        case 300: return "5-hour window"
        case 10_080: return "Weekly window"
        case let m where m % 1_440 == 0: return "\(m / 1_440)-day window"
        case let m where m % 60 == 0: return "\(m / 60)-hour window"
        default: return "\(minutes)-minute window"
        }
    }

    private struct Event: Decodable {
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let rateLimits: Limits?

        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    private struct Limits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decode(Double.self, forKey: .usedPercent) {
                usedPercent = value
            } else {
                usedPercent = Double(try container.decode(Int.self, forKey: .usedPercent))
            }
            windowMinutes = try container.decode(Int.self, forKey: .windowMinutes)
            resetsAt = try container.decode(TimeInterval.self, forKey: .resetsAt)
        }
    }
}
