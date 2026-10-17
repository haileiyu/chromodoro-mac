import AppKit
import SwiftUI

/// History and Settings in one sidebar window, like the extension's two pages.
@MainActor
final class MainWindowController {
  private let model: AppModel
  private var window: NSWindow?

  init(model: AppModel) { self.model = model }

  func show(_ page: Page) {
    model.page = page
    if window == nil {
      let hosting = NSHostingController(rootView: MainView(model: model))
      hosting.sizingOptions = [.minSize]
      let window = NSWindow(contentViewController: hosting)
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      window.setContentSize(NSSize(width: 1000, height: 700))
      window.isReleasedWhenClosed = false
      window.center()
      window.setFrameAutosaveName("MacodoroMain")
      self.window = window
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }
}

/// The stand-in for the extension's end-of-session tab: hard to miss, and it closes
/// itself as soon as a session starts anywhere.
@MainActor
final class CompletionWindowController {
  private let model: AppModel
  private var window: NSWindow?

  init(model: AppModel) { self.model = model }

  func show() {
    if window == nil {
      let hosting = NSHostingController(rootView: CompletionView(model: model))
      hosting.sizingOptions = [.preferredContentSize]
      // A non-activating panel floats above other apps and its buttons work on the first
      // click, but it never takes keyboard focus: Return typed into the app in use must
      // not land on "Start break".
      let panel = NSPanel(contentViewController: hosting)
      panel.styleMask = [.titled, .closable, .nonactivatingPanel]
      panel.title = "Session complete"
      panel.isReleasedWhenClosed = false
      panel.isFloatingPanel = true
      panel.becomesKeyOnlyIfNeeded = true
      panel.hidesOnDeactivate = false
      panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
      window = panel
    }
    window?.center()
    window?.orderFrontRegardless()
  }

  func close() { window?.close() }
}

/// An accessory app has no visible menu bar, but its main menu still routes key
/// equivalents: without it, ⌘C, ⌘V, ⌘W, and ⌘Q do nothing in our windows.
@MainActor
enum MainMenu {
  static func make(settingsTarget: AnyObject) -> NSMenu {
    let main = NSMenu()
    let app = submenu(main, "Macodoro")
    app.addItem(withTitle: "About Macodoro", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    app.addItem(.separator())
    let settings = app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
    settings.target = settingsTarget
    app.addItem(.separator())
    app.addItem(withTitle: "Quit Macodoro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let edit = submenu(main, "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    let window = submenu(main, "Window")
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    return main
  }

  private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
    let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    item.submenu = menu
    return menu
  }
}
