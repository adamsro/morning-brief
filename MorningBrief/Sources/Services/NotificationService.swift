import Foundation
import UserNotifications

extension Notification.Name {
  static let openChatWindow = Notification.Name("openChatWindow")
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationService()

  private nonisolated static let reportReadyCategory = "REPORT_READY"
  private nonisolated static let errorCategory = "GENERATION_ERROR"

  private var isAvailable = false

  func setup() {
    // UNUserNotificationCenter requires a proper app bundle.
    // Guard against crashes when running via `swift run`.
    guard Bundle.main.bundleIdentifier != nil else {
      isAvailable = false
      return
    }
    isAvailable = true
    UNUserNotificationCenter.current().delegate = self
  }

  func requestPermission() async -> Bool {
    guard isAvailable else { return false }
    do {
      return try await UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound])
    } catch {
      return false
    }
  }

  func postReportReady(date: Date) {
    guard isAvailable else { return }
    let content = UNMutableNotificationContent()
    content.title = "Morning Brief"
    content.body = "Your daily report is ready."
    content.sound = .default
    content.categoryIdentifier = Self.reportReadyCategory

    let request = UNNotificationRequest(
      identifier: "report-\(date.timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  func postError(_ message: String) {
    guard isAvailable else { return }
    let content = UNMutableNotificationContent()
    content.title = "Morning Brief"
    content.body = message
    content.sound = .default
    content.categoryIdentifier = Self.errorCategory

    let request = UNNotificationRequest(
      identifier: "error-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.content.categoryIdentifier == Self.reportReadyCategory {
      NotificationCenter.default.post(name: .openChatWindow, object: nil)
    }
    completionHandler()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
