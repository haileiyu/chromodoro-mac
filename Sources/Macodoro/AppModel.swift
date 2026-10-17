import AppKit
import MacodoroCore
import Observation
import ServiceManagement
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
  case history, settings
  var id: Self { self }
  var title: String { self == .history ? "History" : "Settings" }
  var symbol: String { self == .history ? "chart.bar.xaxis" : "slider.horizontal.3" }
}

enum Appearance: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: Self { self }
  var title: String { rawValue.capitalized }
  var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

/// The one owner of saved state. Every change goes through `transact` on the main actor,
/// which serializes clicks, hotkeys, wake-ups, and settings the way the extension's queue did.
@MainActor @Observable
final class AppModel {
  private(set) var state: PomodoroState
  var page: Page = .history
  var errorMessage: String?
  var notificationsDenied = false
  var hotkeyConflicts: Set<HotKeyAction> = []
  private(set) var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
  var appearance: Appearance {
    didSet {
      UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
      NSApp.appearance = appearance.nsAppearance
    }
  }

  /// Called after every transaction with the session that just finished, if any.
  @ObservationIgnored var didChange: (Completion?) -> Void = { _ in }
  @ObservationIgnored private let fileURL: URL

  init(directory: URL) {
    fileURL = directory.appendingPathComponent("state.json")
    appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    (state, errorMessage) = Self.load(fileURL)
    NSApp.appearance = appearance.nsAppearance
  }

  /// ~/Library/Application Support/Macodoro, or $MACODORO_STATE_DIR for development.
  static func defaultDirectory() -> URL {
    if let custom = ProcessInfo.processInfo.environment["MACODORO_STATE_DIR"], !custom.isEmpty {
      return URL(fileURLWithPath: custom, isDirectory: true)
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("Macodoro", isDirectory: true)
  }

  private static func load(_ url: URL) -> (PomodoroState, String?) {
    guard FileManager.default.fileExists(atPath: url.path) else { return (PomodoroState(), nil) }
    do {
      return (try decoder.decode(PomodoroState.self, from: Data(contentsOf: url)), nil)
    } catch {
      // Never overwrite history we failed to read: set it aside for recovery.
      let aside = url.deletingLastPathComponent().appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
      try? FileManager.default.moveItem(at: url, to: aside)
      return (PomodoroState(), "Saved data could not be read, so Macodoro started fresh. The old file is kept as \(aside.lastPathComponent).")
    }
  }

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .millisecondsSince1970
    return d
  }()

  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .millisecondsSince1970
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
  }()

  private func save() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
    } catch {
      errorMessage = "Could not save: \(error.localizedDescription)"
    }
  }

  // Settle first, so a session that ended while the Mac slept is banked before any
  // action runs, and is still banked if that action fails validation.
  @discardableResult
  private func transact(_ action: ((inout PomodoroState) throws -> Void)? = nil) -> Bool {
    var next = state
    let completion = next.settle()
    if completion != nil {
      state = next
      save()
    }
    var ok = true
    do {
      try action?(&next)
      if action != nil { errorMessage = nil }
      if next != state {
        state = next
        save()
      }
    } catch {
      errorMessage = error.localizedDescription
      ok = false
    }
    didChange(completion)
    return ok
  }

  func refresh() { transact() }
  func toggle() { transact { $0.toggle() } }
  func startFocus() { transact { $0.startFocus() } }
  func startBreak() { transact { $0.startBreak() } }

  func update(_ change: (inout Settings) -> Void) {
    var settings = state.settings
    change(&settings)
    transact { try $0.apply(settings) }
  }

  func removeImportedHistory() { transact { $0.imported = [:] } }

  func importHistory() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.commaSeparatedText, .plainText]
    panel.message = "Choose a history CSV exported from Chromodoro for Chrome."
    panel.prompt = "Import"
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let days = try HistoryCSV.parse(String(contentsOf: url, encoding: .utf8))
      transact { $0.imported = days }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func exportHistory() {
    refresh()
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "macodoro-history-\(dayKey(Date())).csv"
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try HistoryCSV.export(state.allDays).write(to: url, atomically: true, encoding: .utf8)
    } catch {
      errorMessage = "Could not export: \(error.localizedDescription)"
    }
  }

  /// Login items only work from a real .app bundle, not from `swift run`.
  var canOpenAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

  func setOpenAtLogin(_ enabled: Bool) {
    do {
      if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      errorMessage = "Could not change Open at login: \(error.localizedDescription)"
    }
    loginItemStatus = SMAppService.mainApp.status
  }

  func refreshLoginItemStatus() { loginItemStatus = SMAppService.mainApp.status }
}
