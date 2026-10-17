import AppKit
import MacodoroCore
@preconcurrency import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  var onClick: () -> Void = {}
  var onDeniedChange: (Bool) -> Void = { _ in }

  /// UNUserNotificationCenter traps outside an app bundle, such as under `swift run`.
  private var center: UNUserNotificationCenter? {
    Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
  }

  func start() {
    center?.delegate = self
    refreshStatus()
  }

  func requestAuthorization() {
    guard let center else { return }
    Task {
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
      refreshStatus()
    }
  }

  func refreshStatus() {
    guard let center else { return }
    Task {
      let settings = await center.notificationSettings()
      onDeniedChange(settings.authorizationStatus == .denied)
    }
  }

  func announce(_ completion: Completion, state: PomodoroState) {
    guard let center else { return }
    let focus = completion.phase == .focus
    let content = UNMutableNotificationContent()
    content.title = focus ? "Focus complete" : "Break complete"
    // With that break switched off, focus is queued next, not a break.
    content.body = focus && state.nextPhase != .focus
      ? "Your focus session is saved. Click Macodoro in the menu bar to start your break."
      : focus ? "Your focus session is saved. Click Macodoro in the menu bar to start your next focus session."
      : "Click Macodoro in the menu bar to start your next focus session."
    content.sound = .default
    let request = UNNotificationRequest(identifier: "macodoro-\(completion.id)", content: content, trigger: nil)
    center.add(request) { error in
      if let error { NSLog("Macodoro: notification unavailable: \(error.localizedDescription)") }
    }
  }

  // Show banners even while a Macodoro window is frontmost.
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    await clicked()
  }

  private func clicked() { onClick() }
}
