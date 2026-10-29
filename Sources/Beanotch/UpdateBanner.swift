import Foundation
import UserNotifications

// A new version in Notification Center too, beside the notch's own notice, with an Update button, for when the notch
// is out of sight. macOS asks once whether Beanotch may notify.
@MainActor
final class UpdateBanner: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UpdateBanner()
    var onUpdate: (() -> Void)?

    // Only inside the app bundle: Notification Center has nothing to attach a bare executable's banners to.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let update = UNNotificationAction(identifier: "update", title: "Update", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "update", actions: [update], intentIdentifiers: [])])
    }

    func post(version: String) {
        guard available else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Beanotch \(version) is out"
            content.body = "Click Update to install it. Beanotch is back a few seconds later."
            content.categoryIdentifier = "update"
            try? await center.add(UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil))
        }
    }

    // Update, or a click on the banner itself, installs it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == "update" || response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { UpdateBanner.shared.onUpdate?() }
    }

    // Shown even while Beanotch is the app in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
