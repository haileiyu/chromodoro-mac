import Carbon.HIToolbox

enum HotKeyAction: UInt32, CaseIterable {
  case startFocus = 1, startBreak = 2

  var keyCode: UInt32 { UInt32(self == .startFocus ? kVK_ANSI_8 : kVK_ANSI_9) }
  var keyEquivalent: String { self == .startFocus ? "8" : "9" }
  var display: String { "⇧⌘\(keyEquivalent)" }
}

/// System-wide ⇧⌘8 and ⇧⌘9. Carbon hotkeys need no Accessibility permission, unlike an
/// event tap, and they only fire for the exact combination.
@MainActor
final class HotKeys {
  static var handler: (HotKeyAction) -> Void = { _ in }
  private var refs: [EventHotKeyRef] = []
  private var handlerInstalled = false
  private(set) var enabled: Bool?

  /// Returns the shortcuts that another app already holds, or nil when nothing changed.
  func set(enabled: Bool) -> Set<HotKeyAction>? {
    guard enabled != self.enabled else { return nil }
    self.enabled = enabled
    refs.forEach { UnregisterEventHotKey($0) }
    refs = []
    guard enabled else { return [] }
    installHandler()
    var failed = Set<HotKeyAction>()
    for action in HotKeyAction.allCases {
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: OSType(0x4D43_4452), id: action.rawValue) // "MCDR"
      let status = RegisterEventHotKey(action.keyCode, UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref)
      if status == noErr, let ref { refs.append(ref) } else { failed.insert(action) }
    }
    return failed
  }

  private func installHandler() {
    guard !handlerInstalled else { return }
    handlerInstalled = true
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      var id = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &id)
      // Carbon delivers application-target events on the main thread.
      MainActor.assumeIsolated {
        if let action = HotKeyAction(rawValue: id.id) { HotKeys.handler(action) }
      }
      return noErr
    }, 1, &spec, nil, nil)
  }
}
