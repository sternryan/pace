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
    public let hourly: [HourBucket]   // trailing 8 days
    public let daily: [DayBucket]     // trailing 30 d
    public let unparsedLines: Int     // surfaced in UI so a silent zero cannot pass as real
    public init(hourly: [HourBucket], daily: [DayBucket], unparsedLines: Int) {
        self.hourly = hourly; self.daily = daily; self.unparsedLines = unparsedLines
    }

    /// Seconds of `bucket`'s hour that overlap `[from, to)`, clamped to >= 0.
    private static func overlapSeconds(_ bucket: HourBucket, from: Date, to: Date) -> Double {
        let bucketEnd = bucket.start.addingTimeInterval(3600)
        let start = max(bucket.start, from)
        let end = min(bucketEnd, to)
        return max(0, end.timeIntervalSince(start))
    }

    /// Tokens attributed to `provider` between `from` and `to`, pro-rating any
    /// bucket that straddles either boundary by the fraction of its hour that
    /// falls inside the window (rounded to the nearest whole token).
    public func tokens(for provider: ProviderID, from: Date, to: Date) -> Int {
        let sum = hourly.filter { $0.provider == provider }
            .reduce(0.0) { $0 + Double($1.tokens) * Self.overlapSeconds($1, from: from, to: to) / 3600 }
        return Int(sum.rounded())
    }

    /// Tokens per second for `provider` over the trailing `window` ending at
    /// `now`, using the same overlap pro-ration as `tokens(for:from:to:)` so
    /// the two never disagree at an hour boundary.
    public func rate(for provider: ProviderID, now: Date, window: TimeInterval = 3600) -> Double {
        guard window > 0 else { return 0 }
        let from = now.addingTimeInterval(-window)
        let sum = hourly.filter { $0.provider == provider }
            .reduce(0.0) { $0 + Double($1.tokens) * Self.overlapSeconds($1, from: from, to: now) / 3600 }
        return sum / window
    }
}
