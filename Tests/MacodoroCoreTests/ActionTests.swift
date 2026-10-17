import Foundation
import Testing
@testable import MacodoroCore

// Ported from the Chrome extension's tests/background.test.js: the menu, shortcut,
// and settings handlers that lived in background.js are pure functions here.

private func finishFocus(_ s: inout PomodoroState, _ now: inout Date) {
  s.startFocus(now: now)
  now = s.timer!.endsAt!
  _ = s.settle(now: now)
}

@Test func startFocusSkipsABreakOrRestartsFocusAndKeepsTheCycle() {
  var s = PomodoroState()
  var now = local(2026, 9, 5, 9)
  s.toggle(now: now)
  now += minutes(25)
  _ = s.settle(now: now)
  #expect(s.nextPhase == .shortBreak)

  // One click replaces the queued break with a running focus session.
  s.startFocus(now: now)
  #expect(s.timer?.phase == .focus)
  #expect(s.timer?.status == .running)
  #expect(s.lastCompletion == nil)
  #expect(s.cycle == 1)
  #expect(s.badge(now: now).text == "25m")

  // Mid-focus it restarts: the unfinished ten minutes are dropped, not banked.
  now += minutes(10)
  #expect(s.settle(now: now) == nil)
  s.startFocus(now: now)
  #expect(s.timer?.endsAt == now + minutes(25))
  #expect(s.cycle == 1)
  #expect(s.days[dayKey(now)]?.count == 1)

  // Skipping a running break discards break time and records nothing.
  now += minutes(25)
  _ = s.settle(now: now)
  #expect(s.cycle == 2)
  s.toggle(now: now)
  #expect(s.timer?.phase == .shortBreak)
  now += minutes(2)
  s.startFocus(now: now)
  #expect(s.timer?.phase == .focus)
  #expect(s.cycle == 2)
  #expect(s.days[dayKey(now)]?.count == 2)

  // Skipped breaks do not disturb the long break owed after four focus sessions.
  now += minutes(25)
  _ = s.settle(now: now)
  #expect(s.nextPhase == .shortBreak)
  finishFocus(&s, &now)
  #expect(s.cycle == 4)
  #expect(s.nextPhase == .longBreak)
  #expect(s.days[dayKey(now)]?.count == 4)
}

@Test func startBreakTakesTheDueBreakAndAbandonsLiveFocus() throws {
  var s = PomodoroState()
  var now = local(2026, 9, 19, 9)

  // Nothing completed yet, so no long break is owed: a short one.
  s.startBreak(now: now)
  #expect(s.timer?.phase == .shortBreak)
  #expect(s.timer?.duration == minutes(5))

  // Mid-focus: the unfinished session is dropped, nothing is recorded.
  s.startFocus(now: now)
  now += minutes(10)
  #expect(s.settle(now: now) == nil)
  s.startBreak(now: now)
  #expect(s.timer?.phase == .shortBreak)
  #expect(s.days.isEmpty)
  #expect(s.cycle == 0)

  // After a completed focus session with a long break owed, it is the long one.
  var settings = s.settings
  settings.longEvery = 1
  try s.apply(settings)
  finishFocus(&s, &now)
  #expect(s.nextPhase == .longBreak)
  s.startBreak(now: now)
  #expect(s.timer?.phase == .longBreak)
  #expect(s.timer?.duration == minutes(15))
  #expect(s.cycle == 1)
}

@Test func switchedOffBreaksCannotBeStartedAndSettingsRequeue() throws {
  var s = PomodoroState()
  var now = local(2026, 10, 15, 9)
  let base = s.settings
  var noShort = base
  noShort.shortBreak = 0
  try s.apply(noShort)

  // Focus completes and focus is queued: no phantom break.
  finishFocus(&s, &now)
  #expect(s.nextPhase == .focus)
  #expect(s.timer == nil)
  #expect(s.badge(now: now).text == "")
  #expect(s.lastCompletion?.phase == .focus)

  // Start break falls back to the long break.
  #expect(s.breakDue == .longBreak)
  s.startBreak(now: now)
  #expect(s.timer?.phase == .longBreak)

  // With every break off, Start break leaves the running session alone.
  s.startFocus(now: now)
  var noBreaks = noShort
  noBreaks.longBreak = 0
  try s.apply(noBreaks)
  let running = s.timer
  #expect(s.breakDue == nil)
  s.startBreak(now: now)
  #expect(s.timer == running)

  // Switching a queued break off in Settings queues focus in its place.
  try s.apply(base)
  now = s.timer!.endsAt!
  _ = s.settle(now: now)
  #expect(s.nextPhase == .shortBreak)
  try s.apply(noShort)
  #expect(s.nextPhase == .focus)
  // And turning it back on, while idle after focus, queues it again.
  try s.apply(base)
  #expect(s.nextPhase == .shortBreak)
}

@Test func invalidSettingsLeaveStateUntouched() {
  var s = PomodoroState()
  let before = s
  var bad = s.settings
  bad.focus = 0
  #expect(throws: UserError.self) { try s.apply(bad) }
  #expect(s == before)
}

@Test func importedHistoryAddsToLocalHistory() {
  var s = PomodoroState()
  let now = local(2026, 10, 17, 12)
  s.days[dayKey(now)] = DayTotal(count: 2, minutes: 50)
  s.imported = [dayKey(now): DayTotal(count: 3, minutes: 75), "2025-01-02": DayTotal(count: 1, minutes: 25)]
  #expect(s.todayCount(now: now) == 5)
  #expect(s.allDays["2025-01-02"] == DayTotal(count: 1, minutes: 25))
  #expect(s.todayProgress(now: now) == "5")
  s.settings.dailyTarget = 8
  #expect(s.todayProgress(now: now) == "5/8")
}

@Test func savedStateWithMissingOrBadFieldsStillLoads() throws {
  let json = #"{"settings":{"focus":0,"shortBreak":7,"notify":false},"days":{"2026-10-01":{"count":2,"minutes":50}},"cycle":3}"#
  let s = try JSONDecoder().decode(PomodoroState.self, from: Data(json.utf8))
  #expect(s.settings.focus == 25)
  #expect(s.settings.shortBreak == 7)
  #expect(s.settings.notify == false)
  #expect(s.settings.completionWindow == true)
  #expect(s.days["2026-10-01"]?.count == 2)
  #expect(s.cycle == 3)
  #expect(s.nextPhase == .focus)
}
