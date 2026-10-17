import Foundation
import Testing
@testable import MacodoroCore

@Test func exportMatchesTheChromeExtensionFormat() {
  let csv = HistoryCSV.export(["2026-10-02": DayTotal(count: 3, minutes: 75), "2026-09-30": DayTotal(count: 1, minutes: 25)])
  #expect(csv == "Date,Pomodoros,Focus minutes\r\n2026-09-30,1,25\r\n2026-10-02,3,75\r\n")
}

@Test func importReadsAChromeExportAndRoundTrips() throws {
  let days = ["2026-10-02": DayTotal(count: 3, minutes: 75), "2025-02-28": DayTotal(count: 12, minutes: 300)]
  #expect(try HistoryCSV.parse(HistoryCSV.export(days)) == days)
  let chrome = "\u{FEFF}Date,Pomodoros,Focus minutes\r\n2026-10-01,2,50\r\n2026-10-01,1,25.4\r\n2026-10-03,0,0\r\n\r\n"
  #expect(try HistoryCSV.parse(chrome) == ["2026-10-01": DayTotal(count: 3, minutes: 75)])
}

@Test func importRejectsRowsThatAreNotHistory() {
  for bad in ["Date,Pomodoros,Focus minutes\n2026-13-01,1,25", "2026-02-30,1,25", "2026-10-01,-1,25",
              "2026-10-01,1", "2026-10-01,one,25", "hello world"] {
    #expect(throws: UserError.self) { try HistoryCSV.parse(bad) }
  }
  #expect(throws: UserError("This file has no completed Pomodoros to import.")) {
    try HistoryCSV.parse("Date,Pomodoros,Focus minutes\r\n")
  }
}
