import Foundation

public struct HourBucket: Equatable, Codable, Sendable {
    public let start: Date            // truncated to the hour, UTC
    public let provider: ProviderID   // .claude or .codex
    public let tokens: Int            // input + output + cache tokens
    public let costUSD: Double
    public init(start: Date, provider: ProviderID, tokens: Int, costUSD: Double) {
        self.start = start; self.provider = provider; self.tokens = tokens; self.costUSD = costUSD
    }
}

public struct DayBucket: Equatable, Codable, Sendable {
    public let day: String            // "YYYY-MM-DD" local
    public let provider: ProviderID
    public let tokens: Int
    public let costUSD: Double
    public init(day: String, provider: ProviderID, tokens: Int, costUSD: Double) {
        self.day = day; self.provider = provider; self.tokens = tokens; self.costUSD = costUSD
    }
}

public struct BurnSeries: Equatable, Codable, Sendable {
    public let hourly: [HourBucket]   // trailing 6 h
    public let daily: [DayBucket]     // trailing 30 d
    public let unparsedLines: Int     // surfaced in UI so a silent zero cannot pass as real
    public init(hourly: [HourBucket], daily: [DayBucket], unparsedLines: Int) {
        self.hourly = hourly; self.daily = daily; self.unparsedLines = unparsedLines
    }

    /// Tokens attributed to `provider` between `from` and `to` from the hourly buckets.
    public func tokens(for provider: ProviderID, from: Date, to: Date) -> Int {
        hourly.filter { $0.provider == provider && $0.start >= from && $0.start < to }
              .reduce(0) { $0 + $1.tokens }
    }

    /// Tokens per second for `provider` over the trailing `window` ending at `now`.
    public func rate(for provider: ProviderID, now: Date, window: TimeInterval = 3600) -> Double {
        let t = tokens(for: provider, from: now.addingTimeInterval(-window), to: now)
        return window > 0 ? Double(t) / window : 0
    }
}
