import Foundation

public enum PaceFormatter {
    public static func resetLabel(for lane: LaneUsage, now: Date) -> String {
        let interval = lane.resetDate.timeIntervalSince(now)
        if interval <= 0 { return "resets shortly" }
        if interval < 24 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "resets \(formatter.string(from: lane.resetDate))"
    }

    public static func projectionLabel(capDate: Date, resetDate: Date) -> String {
        let hours = max(0, Int(resetDate.timeIntervalSince(capDate)) / 3600)
        return hours <= 0 ? "before reset" : "~\(hours)h before reset"
    }
}
