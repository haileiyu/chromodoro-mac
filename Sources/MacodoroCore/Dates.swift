import Foundation

/// Gregorian in the Mac's current time zone, so keys match the Chrome extension's CSV
/// even when the user's calendar is set to another system.
public func pomodoroCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  return calendar
}

/// Local calendar date as yyyy-MM-dd. Historical keys never move if the time zone changes.
public func dayKey(_ date: Date, calendar: Calendar = pomodoroCalendar()) -> String {
  let c = calendar.dateComponents([.year, .month, .day], from: date)
  return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

public let heatmapWeeks = 53

// Sunday-first columns ending with the week containing `now`. Dates are built from a
// noon anchor with calendar arithmetic, so a DST shift can never skip or repeat a day.
public func heatmapDays(now: Date = Date(), weeks: Int = heatmapWeeks, calendar: Calendar = pomodoroCalendar()) -> [Date] {
  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
  let weekday = calendar.component(.weekday, from: noon) // 1 is Sunday
  let start = calendar.date(byAdding: .day, value: -(weekday - 1) - (weeks - 1) * 7, to: noon) ?? noon
  return (0..<weeks * 7).map { calendar.date(byAdding: .day, value: $0, to: start) ?? start }
}

// Fixed buckets, not quartiles of the user's own max: a Pomodoro is a fixed unit
// of work, so a shade means the same thing in every month and for every user.
public func heatmapLevel(_ count: Int) -> Int {
  count <= 0 ? 0 : count <= 2 ? 1 : count <= 4 ? 2 : count <= 6 ? 3 : 4
}
