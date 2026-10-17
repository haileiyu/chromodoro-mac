import Foundation

public enum Phase: String, Codable, CaseIterable, Sendable {
  case focus, shortBreak, longBreak

  public var label: String {
    switch self {
    case .focus: "Focus"
    case .shortBreak: "Short break"
    case .longBreak: "Long break"
    }
  }
}

public struct UserError: LocalizedError, Equatable, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

public struct Settings: Codable, Equatable, Sendable {
  public var focus = 25
  public var shortBreak = 5
  public var longBreak = 15
  public var longEvery = 4
  public var dailyTarget = 0
  public var notify = true
  public var completionWindow = true
  public var hotkeys = true

  public init() {}

  // Breaks may be 0 to switch them off. Focus and longEvery may not: a 0-minute focus
  // session means nothing, and cycle % 0 would trap, so no long break would ever come.
  public static var numberFields: [(name: String, label: String, key: WritableKeyPath<Settings, Int>, range: ClosedRange<Int>)] {
    [("focus", "Focus", \.focus, 1...180), ("shortBreak", "Short break", \.shortBreak, 0...60),
     ("longBreak", "Long break", \.longBreak, 0...90), ("longEvery", "Long break every", \.longEvery, 1...12),
     ("dailyTarget", "Daily target", \.dailyTarget, 0...100)]
  }

  public static func range(of key: WritableKeyPath<Settings, Int>) -> ClosedRange<Int> {
    numberFields.first { $0.key == key }?.range ?? 0...0
  }

  public func minutes(for phase: Phase) -> Int {
    switch phase {
    case .focus: focus
    case .shortBreak: shortBreak
    case .longBreak: longBreak
    }
  }

  public func validated() throws -> Settings {
    for field in Self.numberFields where !field.range.contains(self[keyPath: field.key]) {
      throw UserError("\(field.label) must be a whole number between \(field.range.lowerBound) and \(field.range.upperBound).")
    }
    return self
  }

  // Missing or out-of-range values fall back to defaults, so a file from an older
  // version, or one edited by hand, still loads instead of wiping history.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    for field in Self.numberFields {
      if let key = CodingKeys(stringValue: field.name), let value = try? c.decode(Int.self, forKey: key), field.range.contains(value) {
        self[keyPath: field.key] = value
      }
    }
    notify = (try? c.decode(Bool.self, forKey: .notify)) ?? notify
    completionWindow = (try? c.decode(Bool.self, forKey: .completionWindow)) ?? completionWindow
    hotkeys = (try? c.decode(Bool.self, forKey: .hotkeys)) ?? hotkeys
  }
}

public struct Session: Codable, Equatable, Sendable {
  public enum Status: String, Codable, Sendable { case running, paused }

  public var id: UUID
  public var phase: Phase
  public var status: Status
  public var duration: TimeInterval
  /// Authoritative only while paused; a running session derives it from `endsAt`.
  public var remaining: TimeInterval
  public var endsAt: Date?

  public func remaining(at now: Date) -> TimeInterval {
    max(0, status == .running ? (endsAt ?? now).timeIntervalSince(now) : remaining)
  }
}

public struct Completion: Codable, Equatable, Sendable {
  public var id: UUID
  public var phase: Phase
  public var endedAt: Date
  public var minutes: Int
}

public struct DayTotal: Codable, Equatable, Sendable {
  public var count: Int
  public var minutes: Int
  public init(count: Int, minutes: Int) { self.count = count; self.minutes = minutes }
}

public struct PomodoroState: Codable, Equatable, Sendable {
  public var version = 1
  public var settings = Settings()
  public var timer: Session?
  public var nextPhase: Phase = .focus
  /// Completed focus sessions; drives the long break and never moves on skips.
  public var cycle = 0
  /// Completed here, keyed by local date (yyyy-MM-dd).
  public var days: [String: DayTotal] = [:]
  /// Imported from the Chrome extension's CSV export. Kept apart from `days`, so a
  /// day with sessions in both places adds up, and a second import replaces the first.
  public var imported: [String: DayTotal] = [:]
  public var lastCompletion: Completion?

  public init() {}

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
    timer = try? c.decodeIfPresent(Session.self, forKey: .timer)
    nextPhase = (try? c.decode(Phase.self, forKey: .nextPhase)) ?? .focus
    cycle = max(0, (try? c.decode(Int.self, forKey: .cycle)) ?? 0)
    days = try c.decodeIfPresent([String: DayTotal].self, forKey: .days) ?? [:]
    imported = try c.decodeIfPresent([String: DayTotal].self, forKey: .imported) ?? [:]
    lastCompletion = try? c.decodeIfPresent(Completion.self, forKey: .lastCompletion)
  }
}
