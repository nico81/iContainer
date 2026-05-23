import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` that funnels app-level
/// notifications (container stopped / action failed) through the user's
/// preferences. Permission is requested lazily the first time a notification
/// is actually posted.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var authorizationRequested = false
    private var authorizationGranted = false

    private init() {}

    func notifyContainerStopped(name: String) {
        guard SettingsManager.shared.notifyContainerStopped else { return }
        post(
            identifier: "container.stopped.\(name)",
            title: "Container stopped",
            body: "Container \"\(name)\" is no longer running."
        )
    }

    func notifyActionFailed(action: String, target: String, message: String?) {
        guard SettingsManager.shared.notifyActionFailed else { return }
        let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let detail, !detail.isEmpty {
            body = "\(action) failed for \"\(target)\": \(detail)"
        } else {
            body = "\(action) failed for \"\(target)\"."
        }
        post(
            identifier: "action.failed.\(action).\(target).\(UUID().uuidString)",
            title: "Action failed",
            body: body
        )
    }

    private func post(identifier: String, title: String, body: String) {
        Task { await ensureAuthorization() }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    private func ensureAuthorization() async {
        if authorizationGranted { return }
        if authorizationRequested { return }
        authorizationRequested = true
        do {
            authorizationGranted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorizationGranted = false
        }
    }
}
