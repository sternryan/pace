import Foundation

/// Extra-usage (overage) spend, converted from the API's minor units.
public struct ExtraUsage: Equatable, Sendable, Codable {
    public let dollarsUsed: Double
    public let isEnabled: Bool

    public init(dollarsUsed: Double, isEnabled: Bool) {
        self.dollarsUsed = dollarsUsed
        self.isEnabled = isEnabled
    }
}

/// One successful fetch result. Also the persisted last-good cache format —
/// contains percentages and timestamps only, never credentials.
public struct UsageSnapshot: Equatable, Sendable, Codable {
    public let lanes: [LaneUsage]
    public let extraUsage: ExtraUsage?
    public let fetchedAt: Date

    public init(lanes: [LaneUsage], extraUsage: ExtraUsage?, fetchedAt: Date) {
        self.lanes = lanes
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }
}
