import Foundation

public struct Badge: Equatable, Sendable {
  public enum Style: Sendable { case idle, paused, focus, rest }
  public var text: String
  public var style: Style
  public var title: String
}

extension PomodoroState {
  // A break set to 0 minutes is switched off. It is skipped, never started as a 0-second
  // timer that would instantly "complete" with a notification. Each break is checked on
  // its own, so short breaks can be off while the long break still comes round.
  public func phaseAfterFocus() -> Phase {
    let phase: Phase = cycle % settings.longEvery == 0 ? .longBreak : .shortBreak
    return settings.minutes(for: phase) > 0 ? phase : .focus
  }

  /// The break that Start break would take now, or nil when both breaks are off.
  public var breakDue: Phase? {
    let due: Phase = nextPhase == .focus ? .shortBreak : nextPhase
    return [due, .shortBreak, .longBreak].first { settings.minutes(for: $0) > 0 }
  }

  // The deadline is authoritative. A late wake never adds time or counts twice.
  // The record belongs to the deadline's local date, even if the Mac wakes tomorrow.
  public mutating func settle(now: Date = Date()) -> Completion? {
    guard let t = timer, t.status == .running, let endsAt = t.endsAt, endsAt <= now else { return nil }
    let completion = Completion(id: t.id, phase: t.phase, endedAt: endsAt, minutes: Int((t.duration / 60).rounded()))
    if t.phase == .focus {
      let key = dayKey(endsAt)
      let day = days[key] ?? DayTotal(count: 0, minutes: 0)
      days[key] = DayTotal(count: day.count + 1, minutes: day.minutes + completion.minutes)
      cycle += 1
      nextPhase = phaseAfterFocus()
    } else {
      nextPhase = .focus
    }
    timer = nil
    lastCompletion = completion
    return completion
  }

  /// Click on the menu bar item: start the queued session, pause, or resume.
  public mutating func toggle(now: Date = Date(), id: UUID = UUID()) {
    guard var t = timer else {
      // Backstop: a break switched off after it was queued is skipped, not run for 0 seconds.
      if settings.minutes(for: nextPhase) <= 0 { nextPhase = .focus }
      let duration = TimeInterval(settings.minutes(for: nextPhase) * 60)
      timer = Session(id: id, phase: nextPhase, status: .running, duration: duration, remaining: duration,
                      endsAt: now.addingTimeInterval(duration))
      lastCompletion = nil
      return
    }
    if t.status == .running {
      t.remaining = t.remaining(at: now)
      t.endsAt = nil
      t.status = .paused
    } else {
      t.endsAt = now.addingTimeInterval(t.remaining)
      t.status = .running
    }
    timer = t
  }

  // Both start actions replace whatever is running. With no reset control, they are also
  // how a session gets abandoned. settle() has already banked anything that finished, so
  // only unfinished time is dropped. `cycle` is untouched, so the long-break schedule
  // only ever moves on completed focus sessions.
  public mutating func startFocus(now: Date = Date(), id: UUID = UUID()) {
    timer = nil
    nextPhase = .focus
    toggle(now: now, id: id)
  }

  /// Takes the long break when one is owed and a short one otherwise. With both breaks
  /// off there is nothing to take, so the current session is left alone.
  public mutating func startBreak(now: Date = Date(), id: UUID = UUID()) {
    guard let phase = breakDue else { return }
    timer = nil
    nextPhase = phase
    toggle(now: now, id: id)
  }

  /// Settings affect future sessions; a running or paused session keeps its duration.
  public mutating func apply(_ new: Settings) throws {
    settings = try new.validated()
    if timer == nil, lastCompletion?.phase == .focus { nextPhase = phaseAfterFocus() }
    if settings.minutes(for: nextPhase) <= 0 { nextPhase = .focus }
  }

  public func badge(now: Date = Date()) -> Badge {
    guard let t = timer else {
      return Badge(text: "", style: .idle, title: "Macodoro · Click to start \(nextPhase.label.lowercased()). Right-click for more.")
    }
    let minutes = max(1, Int((t.remaining(at: now) / 60).rounded(.up)))
    let paused = t.status == .paused
    let style: Badge.Style = paused ? .paused : t.phase == .focus ? .focus : .rest
    return Badge(text: "\(minutes)m", style: style,
                 title: "Macodoro · \(t.phase.label) · \(minutes) min left\(paused ? " (paused)" : ""). Click to \(paused ? "resume" : "pause"). Right-click for more.")
  }

  /// When the badge text next changes: each whole-minute boundary, and the deadline itself.
  public func nextRefresh(now: Date = Date()) -> Date? {
    guard let t = timer, t.status == .running, let endsAt = t.endsAt else { return nil }
    let remaining = t.remaining(at: now)
    let wholeMinutesLeft = max(0, (remaining / 60).rounded(.up) - 1)
    return endsAt.addingTimeInterval(-wholeMinutesLeft * 60)
  }

  /// Completed here plus imported, per day. This is what history shows and exports.
  public var allDays: [String: DayTotal] {
    days.merging(imported) { DayTotal(count: $0.count + $1.count, minutes: $0.minutes + $1.minutes) }
  }

  public func todayCount(now: Date = Date()) -> Int {
    allDays[dayKey(now)]?.count ?? 0
  }

  /// "5" or, with a daily target, "5/10".
  public func todayProgress(now: Date = Date()) -> String {
    let count = todayCount(now: now)
    return settings.dailyTarget > 0 ? "\(count)/\(settings.dailyTarget)" : "\(count)"
  }
}
