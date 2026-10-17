import AppKit
import MacodoroCore

@main
@MainActor
enum MacodoroApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar only, like a toolbar extension: no Dock icon.
    app.setActivationPolicy(.accessory)
    app.run()
    _ = delegate
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: AppModel!
  private var statusItem: StatusItemController!
  private var mainWindow: MainWindowController!
  private var completionWindow: CompletionWindowController!
  private let hotKeys = HotKeys()
  private let notifier = Notifier()
  private var refreshTimer: Timer?
  private var activity: NSObjectProtocol?
  private var notifyWasOn = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
      NSApp.terminate(nil)
      return
    }
    model = AppModel(directory: AppModel.defaultDirectory())
    mainWindow = MainWindowController(model: model)
    completionWindow = CompletionWindowController(model: model)
    statusItem = StatusItemController(model: model) { [unowned self] page in mainWindow.show(page) }
    NSApp.mainMenu = MainMenu.make(settingsTarget: self)

    HotKeys.handler = { [unowned self] action in
      action == .startFocus ? model.startFocus() : model.startBreak()
    }
    notifier.onClick = { [unowned self] in mainWindow.show(.history) }
    notifier.onDeniedChange = { [unowned self] denied in model.notificationsDenied = denied }
    notifier.start()

    // The deadline is authoritative, so any of these just re-settles and redraws.
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    for name in [Notification.Name.NSSystemClockDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
      NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
    }

    model.didChange = { [unowned self] completion in update(completion) }
    model.refresh()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    notifier.refreshStatus()
    model?.refreshLoginItemStatus()
  }

  @objc func showSettings() { mainWindow.show(.settings) }
  @objc private func refresh() { model.refresh() }

  private func update(_ completion: Completion?) {
    let state = model.state
    statusItem.render()
    schedule(state)

    // Starting a session anywhere makes the completion window stale.
    if state.timer != nil { completionWindow.close() }

    if let conflicts = hotKeys.set(enabled: state.settings.hotkeys) { model.hotkeyConflicts = conflicts }

    if state.settings.notify, !notifyWasOn { notifier.requestAuthorization() }
    notifyWasOn = state.settings.notify

    // Either alert can be switched off or fail without touching the other;
    // the session is already banked either way.
    if let completion {
      if state.settings.notify { notifier.announce(completion, state: state) }
      if state.settings.completionWindow { completionWindow.show() }
    }
  }

  /// One timer at the next moment the badge text changes; the last one is the deadline.
  private func schedule(_ state: PomodoroState) {
    refreshTimer?.invalidate()
    refreshTimer = nil
    if let fireAt = state.nextRefresh() {
      let timer = Timer(fireAt: fireAt.addingTimeInterval(0.05), interval: 0, target: self, selector: #selector(refresh),
                        userInfo: nil, repeats: false)
      timer.tolerance = 0.2
      // .common keeps it firing while a menu is open.
      RunLoop.main.add(timer, forMode: .common)
      refreshTimer = timer
    }
    // Keep App Nap from delaying the deadline while a session runs. Sleep is still
    // allowed; the wake notification settles whatever finished meanwhile.
    let running = state.timer?.status == .running
    if running, activity == nil {
      activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Pomodoro session running")
    } else if !running, let token = activity {
      ProcessInfo.processInfo.endActivity(token)
      activity = nil
    }
  }
}
