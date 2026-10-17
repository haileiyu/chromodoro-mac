import Foundation
import Testing
@testable import MacodoroCore

// Ported from the Chrome extension's tests/timer.test.js.

let epoch = Date(timeIntervalSince1970: 0)
func minutes(_ n: Double) -> TimeInterval { n * 60 }
func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
  pomodoroCalendar().date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Test func badgeRoundsUp() {
  var s = PomodoroState()
  s.toggle(now: epoch)
  #expect(s.badge(now: epoch + minutes(9)).text == "16m")
  #expect(s.badge(now: epoch + minutes(10)).text == "15m")
  #expect(s.badge(now: epoch + minutes(24) + 59).text == "1m")
  #expect(s.badge(now: epoch).style == .focus)
}

@Test func pauseResumeExcludesPausedTimeAcrossSerialization() throws {
  var s = PomodoroState()
  let id = UUID()
  s.toggle(now: epoch, id: id)
  s.toggle(now: epoch + minutes(9))
  var restored = try JSONDecoder().decode(PomodoroState.self, from: JSONEncoder().encode(s))
  let dayLater = epoch + 86400
  #expect(restored.timer?.remaining(at: dayLater) == minutes(16))
  #expect(restored.badge(now: dayLater).style == .paused)
  #expect(restored.settle(now: dayLater) == nil)
  restored.toggle(now: dayLater)
  #expect(restored.timer?.endsAt == dayLater + minutes(16))
  #expect(restored.timer?.id == id)
}

@Test func lateAndDuplicateCompletionsRecordOnce() {
  var s = PomodoroState()
  let id = UUID()
  s.toggle(now: epoch, id: id)
  #expect(s.settle(now: epoch + minutes(25) - 0.001) == nil)
  #expect(s.settle(now: epoch + 86400)?.id == id)
  #expect(s.settle(now: epoch + 86400) == nil)
  #expect(s.days[dayKey(epoch + minutes(25))] == DayTotal(count: 1, minutes: 25))
  #expect(s.nextPhase == .shortBreak)
}

@Test func completionBelongsToLocalDeadlineDateAfterMidnight() {
  var s = PomodoroState()
  s.toggle(now: local(2026, 9, 5, 23, 50))
  _ = s.settle(now: local(2026, 9, 7, 10))
  #expect(s.days == ["2026-09-06": DayTotal(count: 1, minutes: 25)])
}

@Test func fourFocusSessionsUnlockALongBreak() {
  var s = PomodoroState()
  var now = local(2026, 9, 5, 10)
  for n in 1...4 {
    s.toggle(now: now)
    now = s.timer!.endsAt!
    _ = s.settle(now: now)
    #expect(s.nextPhase == (n == 4 ? .longBreak : .shortBreak))
    s.toggle(now: now)
    now = s.timer!.endsAt!
    _ = s.settle(now: now)
    #expect(s.nextPhase == .focus)
    #expect(s.days[dayKey(now)]?.count == n)
  }
  #expect(s.days[dayKey(now)]?.minutes == 100)
}

@Test func changingSettingsKeepsTheCurrentDuration() throws {
  var s = PomodoroState()
  s.toggle(now: epoch)
  var longer = Settings()
  longer.focus = 50
  try s.apply(longer)
  _ = s.settle(now: epoch + minutes(25))
  #expect(s.days[dayKey(epoch + minutes(25))]?.minutes == 25)
  s.nextPhase = .focus
  s.toggle(now: epoch + minutes(25))
  #expect(s.timer?.duration == minutes(50))
}

@Test func rejectsOutOfRangeSettings() {
  for value in [0, -1, 181] {
    var bad = Settings()
    bad.focus = value
    #expect(throws: UserError("Focus must be a whole number between 1 and 180.")) { try bad.validated() }
  }
  for key in [\Settings.shortBreak, \Settings.longBreak] {
    var bad = Settings()
    bad[keyPath: key] = -1
    #expect(throws: UserError.self) { try bad.validated() }
  }
  var noEvery = Settings()
  noEvery.longEvery = 0
  #expect(throws: UserError("Long break every must be a whole number between 1 and 12.")) { try noEvery.validated() }
  for target in [-1, 101] {
    var bad = Settings()
    bad.dailyTarget = target
    #expect(throws: UserError("Daily target must be a whole number between 0 and 100.")) { try bad.validated() }
  }
  var off = Settings()
  off.shortBreak = 0
  off.longBreak = 0
  #expect(throws: Never.self) { try off.validated() }
}

@Test func switchedOffBreaksAreSkippedAndTheLongBreakScheduleHolds() {
  func run(_ change: (inout Settings) -> Void, focusSessions: Int) -> (PomodoroState, [Phase], Date) {
    var s = PomodoroState()
    change(&s.settings)
    var now = local(2026, 9, 5, 10)
    var phases: [Phase] = []
    while phases.filter({ $0 == .focus }).count < focusSessions {
      s.toggle(now: now)
      #expect(s.timer!.duration > 0)
      phases.append(s.timer!.phase)
      now = s.timer!.endsAt!
      _ = s.settle(now: now)
    }
    return (s, phases, now)
  }
  let (F, S, L) = (Phase.focus, Phase.shortBreak, Phase.longBreak)
  #expect(run({ $0.shortBreak = 0 }, focusSessions: 5).1 == [F, F, F, F, L, F])
  #expect(run({ $0.longBreak = 0 }, focusSessions: 5).1 == [F, S, F, S, F, S, F, F])
  var (s, phases, now) = run({ $0.shortBreak = 0; $0.longBreak = 0 }, focusSessions: 8)
  #expect(phases == Array(repeating: F, count: 8))
  #expect(s.cycle == 8)
  #expect(s.days[dayKey(now)]?.count == 8)
  // Breaks only change what is queued next, so turning one back on applies at once.
  s.settings = Settings()
  s.toggle(now: now)
  _ = s.settle(now: s.timer!.endsAt!)
  #expect(s.nextPhase == .shortBreak)
}

@Test func aQueuedBreakThatWasSwitchedOffStartsFocus() {
  var s = PomodoroState()
  s.nextPhase = .longBreak
  s.settings.longBreak = 0
  s.toggle(now: epoch)
  #expect(s.timer?.phase == .focus)
  #expect(s.timer?.duration == minutes(25))
}

@Test func nextRefreshLandsOnMinuteBoundariesAndTheDeadline() {
  var s = PomodoroState()
  #expect(s.nextRefresh(now: epoch) == nil)
  s.toggle(now: epoch)
  #expect(s.nextRefresh(now: epoch) == epoch + minutes(1))
  #expect(s.nextRefresh(now: epoch + 30) == epoch + minutes(1))
  #expect(s.nextRefresh(now: epoch + minutes(24) + 1) == epoch + minutes(25))
  s.toggle(now: epoch + 10)
  #expect(s.nextRefresh(now: epoch + 10) == nil)
}

@Test func heatmapWindowIs53WholeSundayFirstWeeks() {
  let calendar = pomodoroCalendar()
  // Includes the US spring-forward and fall-back weekends.
  for now in [local(2026, 3, 8, 3), local(2026, 11, 1, 1), local(2026, 10, 17, 23, 59)] {
    let days = heatmapDays(now: now)
    #expect(days.count == heatmapWeeks * 7)
    #expect(calendar.component(.weekday, from: days[0]) == 1)
    #expect(Set(days.map { dayKey($0) }).count == days.count)
    for (a, b) in zip(days, days.dropFirst()) {
      #expect(calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day == 1)
    }
    #expect(days.contains { dayKey($0) == dayKey(now) })
    #expect(calendar.component(.weekday, from: days.last!) == 7)
  }
}

@Test func heatmapLevelsAreFixedBuckets() {
  #expect([0, 1, 2, 3, 4, 5, 6, 7, 40].map(heatmapLevel) == [0, 1, 1, 2, 2, 3, 3, 4, 4])
}
