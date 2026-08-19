import Foundation
import UserNotifications
import PaceCore

/// Thin UNUserNotificationCenter wrapper. Permission is requested lazily on
/// the first alert and AWAITED — posting before authorization resolves would
/// silently drop the first (most important) notification. Denial is tolerated
/// silently: the icon remains the primary signal and a menu bar utility must
/// not nag for permissions.
@MainActor
final class PaceNotifier {
    func post(_ alert: LaneAlert) async {
        // Bundle guard FIRST: UNUserNotificationCenter.current() itself traps
        // in a bundle-less process (`swift run` of the bare binary).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pace"
        content.body = alert.message
        try? await center.add(UNNotificationRequest(identifier: "pace-\(alert.kind.rawValue)-\(UUID().uuidString)",
                                                    content: content, trigger: nil))
    }
}
