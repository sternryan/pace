public struct BarGeometry: Equatable, Sendable {
    public let fillFraction: Double
    public let tickFraction: Double?
    public let isHot: Bool

    public init(fillFraction: Double, tickFraction: Double?, isHot: Bool) {
        self.fillFraction = fillFraction
        self.tickFraction = tickFraction
        self.isHot = isHot
    }
}

public enum IconGeometry {
    public static func barGeometry(for reading: PaceReading) -> BarGeometry {
        BarGeometry(
            fillFraction: Double(reading.lane.percentUsed) / 100.0,
            tickFraction: reading.percentElapsed.map { Double($0) / 100.0 },
            isHot: reading.isAlarmed
        )
    }
}
