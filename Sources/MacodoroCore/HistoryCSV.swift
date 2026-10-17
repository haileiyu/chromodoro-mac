import Foundation

/// The same format the Chrome extension exports, so history moves in either direction.
public enum HistoryCSV {
  public static let header = "Date,Pomodoros,Focus minutes"

  public static func export(_ days: [String: DayTotal]) -> String {
    let rows = days.sorted { $0.key < $1.key }.map { "\($0.key),\($0.value.count),\($0.value.minutes)" }
    return ([header] + rows).joined(separator: "\r\n") + "\r\n"
  }

  public static func parse(_ text: String, calendar: Calendar = pomodoroCalendar()) throws -> [String: DayTotal] {
    var days: [String: DayTotal] = [:]
    let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    for (index, line) in lines.enumerated() where !line.isEmpty {
      // Tolerate a byte-order mark and the header row.
      let cleaned = line.hasPrefix("\u{FEFF}") ? String(line.dropFirst()) : line
      if index == 0, cleaned.lowercased().hasPrefix("date") { continue }
      let fields = cleaned.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
      guard fields.count == 3, isDate(fields[0], calendar: calendar),
            let count = Int(fields[1]), count >= 0,
            let minutes = Double(fields[2]), minutes.isFinite, minutes >= 0 else {
        throw UserError("Line \(index + 1) is not a Pomodoro history row. Expected Date,Pomodoros,Focus minutes.")
      }
      guard count > 0 else { continue }
      let day = days[fields[0]] ?? DayTotal(count: 0, minutes: 0)
      days[fields[0]] = DayTotal(count: day.count + count, minutes: day.minutes + Int(minutes.rounded()))
    }
    guard !days.isEmpty else { throw UserError("This file has no completed Pomodoros to import.") }
    return days
  }

  private static func isDate(_ text: String, calendar: Calendar) -> Bool {
    let parts = text.split(separator: "-")
    guard text.count == 10, parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return false }
    let components = DateComponents(calendar: calendar, year: y, month: m, day: d)
    return components.isValidDate && (1...12).contains(m)
  }
}
