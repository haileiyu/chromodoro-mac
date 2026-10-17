import AppKit
import MacodoroCore

/// The menu bar item: the toolbar button of the Chrome extension.
/// Click to start, pause, or resume. Right-click or Control-click for the menu.
@MainActor
final class StatusItemController: NSObject {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let model: AppModel
  private let show: (Page) -> Void

  init(model: AppModel, show: @escaping (Page) -> Void) {
    self.model = model
    self.show = show
    super.init()
    item.autosaveName = "Macodoro"
    if let button = item.button {
      button.target = self
      button.action = #selector(clicked)
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.imagePosition = .imageOnly
    }
  }

  func render() {
    let state = model.state
    let badge = state.badge()
    guard let button = item.button else { return }
    button.image = StatusImage.make(badge: badge, active: state.timer?.status == .running)
    button.toolTip = badge.title
    button.setAccessibilityLabel(badge.title)
  }

  @objc private func clicked() {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      // A menu attached to the item would swallow left clicks, so attach it only for this click.
      item.menu = makeMenu()
      item.button?.performClick(nil)
      item.menu = nil
    } else {
      model.toggle()
    }
  }

  private func makeMenu() -> NSMenu {
    model.refresh()
    let state = model.state
    let menu = NSMenu()
    menu.autoenablesItems = false

    let status: String
    if let t = state.timer {
      status = "\(t.phase.label) · \(state.badge().text.dropLast()) min left\(t.status == .paused ? " (paused)" : "")"
    } else {
      status = "Idle · Next: \(state.nextPhase.label)"
    }
    menu.addItem(info(status))
    menu.addItem(info("Today: \(state.todayProgress()) Pomodoro\(state.todayCount() == 1 ? "" : "s")"))
    menu.addItem(.separator())

    let hotkeys = state.settings.hotkeys
    menu.addItem(action("Start focusing", #selector(startFocus), key: hotkeys ? HotKeyAction.startFocus : nil))
    let breakItem = action(state.breakDue == .longBreak ? "Start long break" : "Start break", #selector(startBreak),
                           key: hotkeys ? HotKeyAction.startBreak : nil)
    breakItem.isEnabled = state.breakDue != nil
    menu.addItem(breakItem)
    menu.addItem(.separator())
    menu.addItem(action("Pomodoro history…", #selector(openHistory)))
    let settings = action("Settings…", #selector(openSettings))
    settings.keyEquivalent = ","
    settings.keyEquivalentModifierMask = [.command]
    menu.addItem(settings)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Macodoro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)
    return menu
  }

  private func info(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func action(_ title: String, _ selector: Selector, key: HotKeyAction? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: key?.keyEquivalent ?? "")
    item.keyEquivalentModifierMask = [.command, .shift]
    item.target = self
    return item
  }

  @objc private func startFocus() { model.startFocus() }
  @objc private func startBreak() { model.startBreak() }
  @objc private func openHistory() { show(.history) }
  @objc private func openSettings() { show(.settings) }
}

/// The tomato plus a Chrome-style badge: red for focus, green for a break, gray when paused.
enum StatusImage {
  static func make(badge: Badge, active: Bool) -> NSImage {
    let icon = Bundle.main.image(forResource: active ? "icon32" : "idle32")
      ?? NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
      ?? NSImage()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
      .foregroundColor: NSColor.white
    ]
    let text = NSAttributedString(string: badge.text, attributes: attributes)
    let textSize = text.size()
    let iconSide: CGFloat = 16, height: CGFloat = 18, gap: CGFloat = 3
    let pillWidth = badge.text.isEmpty ? 0 : ceil(textSize.width) + 8
    let size = NSSize(width: iconSide + (pillWidth > 0 ? gap + pillWidth : 0), height: height)

    let image = NSImage(size: size)
    image.lockFocus()
    icon.draw(in: NSRect(x: 0, y: (height - iconSide) / 2, width: iconSide, height: iconSide))
    if pillWidth > 0 {
      let pill = NSRect(x: iconSide + gap, y: 2, width: pillWidth, height: 14)
      color(badge.style).setFill()
      NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
      text.draw(at: NSPoint(x: pill.minX + (pill.width - textSize.width) / 2, y: pill.minY + (pill.height - textSize.height) / 2))
    }
    image.unlockFocus()
    return image
  }

  static func color(_ style: Badge.Style) -> NSColor {
    switch style {
    case .focus: NSColor(srgbRed: 0xD5 / 255, green: 0x2B / 255, blue: 0x1E / 255, alpha: 1)
    case .rest: NSColor(srgbRed: 0x3B / 255, green: 0x7F / 255, blue: 0x32 / 255, alpha: 1)
    case .idle, .paused: NSColor(srgbRed: 0x77 / 255, green: 0x73 / 255, blue: 0x6B / 255, alpha: 1)
    }
  }
}
