import AppKit
import MacodoroCore
import ServiceManagement
import SwiftUI

struct MainView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationSplitView {
      List(Page.allCases, selection: Binding<Page?>(get: { model.page }, set: { if let page = $0 { model.page = page } })) { page in
        Label(page.title, systemImage: page.symbol).tag(page)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
    } detail: {
      switch model.page {
      case .history: HistoryView(model: model)
      case .settings: SettingsView(model: model)
      }
    }
    .frame(minWidth: 860, minHeight: 560)
  }
}

struct ErrorText: View {
  let message: String?
  var body: some View {
    if let message {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
  }
}

// MARK: - Completion

struct CompletionView: View {
  let model: AppModel

  var body: some View {
    // Re-read each minute so an idle window left open overnight shows today's count.
    TimelineView(.everyMinute) { context in
      let state = model.state
      let done = state.lastCompletion
      let count = state.todayCount(now: context.date)
      VStack(spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 72, height: 72)
        Text(done == nil ? "Timer idle" : done?.phase == .focus ? "Focus complete" : "Break complete")
          .font(.largeTitle.weight(.medium))
        if let done {
          Text("\(done.minutes) minutes").foregroundStyle(.secondary)
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(state.todayProgress(now: context.date))
            .font(.system(size: 34, weight: .medium))
            .monospacedDigit()
          Text("Pomodoro\(count == 1 ? "" : "s") completed today").foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        HStack(spacing: 10) {
          // Only worth offering when the queued phase is a break we could skip past.
          if state.nextPhase != .focus {
            Button("Skip to focus") { model.startFocus() }
              .controlSize(.large)
          }
          Button("Start \(state.nextPhase.label.lowercased())") { model.toggle() }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(.top, 10)
        ErrorText(message: model.errorMessage)
      }
      .padding(.horizontal, 48)
      .padding(.vertical, 32)
      .frame(minWidth: 420)
    }
  }
}

// MARK: - History

struct HistoryView: View {
  @Bindable var model: AppModel

  var body: some View {
    // Re-render each minute so today's total and the heatmap roll over at midnight.
    TimelineView(.everyMinute) { context in
      let now = context.date
      let state = model.state
      let all = state.allDays
      let today = state.todayCount(now: now)
      ScrollView {
        VStack(alignment: .leading, spacing: 32) {
          ErrorText(message: model.errorMessage)

          VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.title3.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(state.todayProgress(now: now)).font(.system(size: 40, weight: .medium)).monospacedDigit()
              Text("completed Pomodoro\(today == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
          }

          HeatmapSection(days: all, now: now)

          ImportSection(model: model)
        }
        .padding(32)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .navigationTitle("Pomodoro history")
    .toolbar {
      ToolbarItemGroup {
        Button { model.importHistory() } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
          .help("Import history exported from Chromodoro for Chrome")
        Button { model.exportHistory() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
          .help("Export every day with completed Pomodoros as CSV")
      }
    }
  }
}

struct ImportSection: View {
  let model: AppModel

  var body: some View {
    let imported = model.state.imported
    VStack(alignment: .leading, spacing: 10) {
      Text("History from Chrome").font(.title3.weight(.medium))
      if imported.isEmpty {
        Text("Moving from the Chrome extension? In Chrome, open Pomodoro history and choose Export CSV. Then import that file here. Imported days add to the days you complete on this Mac.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Import CSV…") { model.importHistory() }
      } else {
        let total = imported.values.reduce(0) { $0 + $1.count }
        Text("Imported \(total) Pomodoro\(total == 1 ? "" : "s") on \(imported.count) day\(imported.count == 1 ? "" : "s"). Importing again replaces this import.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Import Again…") { model.importHistory() }
          Button("Remove Imported History", role: .destructive) { model.removeImportedHistory() }
        }
      }
    }
  }
}

struct HeatmapSection: View {
  let days: [String: DayTotal]
  let now: Date
  @State private var width: CGFloat = 700

  private let gap: CGFloat = 3
  private let labelWidth: CGFloat = 34

  var body: some View {
    let calendar = pomodoroCalendar()
    let dates = heatmapDays(now: now)
    let today = dayKey(now)
    // Days before the first record stay blank: a new install should not open on a year of misses.
    let first = days.keys.min()
    let side = min(16, max(8, (width - labelWidth - CGFloat(heatmapWeeks) * gap) / CGFloat(heatmapWeeks)))
    let total = dates.reduce(0) { $0 + (days[dayKey($1)]?.count ?? 0) }

    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Past year").font(.title3.weight(.medium))
        Spacer()
        Text("\(monthYear(dates[0])) – \(monthYear(now))").foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(total)").font(.system(size: 40, weight: .medium)).monospacedDigit()
        Text("completed Pomodoro\(total == 1 ? "" : "s")").foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        monthLabels(dates, side: side)
        HStack(alignment: .top, spacing: gap) {
          VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7, id: \.self) { weekday in
              Text(weekday % 2 == 1 ? calendar.shortWeekdaySymbols[weekday] : "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth - gap, height: side, alignment: .leading)
            }
          }
          .accessibilityHidden(true)
          ForEach(0..<heatmapWeeks, id: \.self) { week in
            VStack(spacing: gap) {
              ForEach(0..<7, id: \.self) { weekday in
                cell(dates[week * 7 + weekday], today: today, first: first, side: side)
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Completed Pomodoros by day over the last year")

      if first == nil {
        Text("No completed sessions yet.").foregroundStyle(.secondary)
      }
      HStack(spacing: 4) {
        Spacer()
        Text("Less").foregroundStyle(.secondary)
        ForEach(0..<5, id: \.self) { level in
          RoundedRectangle(cornerRadius: 2).fill(Palette.level(level)).frame(width: 11, height: 11)
        }
        Text("More").foregroundStyle(.secondary)
      }
      .font(.callout)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Green intensity increases with completed Pomodoros: 0, 1–2, 3–4, 5–6, 7 or more.")
    }
  }

  @ViewBuilder
  private func cell(_ date: Date, today: String, first: String?, side: CGFloat) -> some View {
    let key = dayKey(date)
    if key > today || first == nil || key < first! {
      Color.clear.frame(width: side, height: side).accessibilityHidden(true)
    } else {
      let day = days[key]
      let count = day?.count ?? 0
      let label = count > 0
        ? "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) — \(count) Pomodoro\(count == 1 ? "" : "s") · \(minutesLabel(day?.minutes ?? 0)) of focus"
        : "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) — no Pomodoros"
      RoundedRectangle(cornerRadius: 2)
        .fill(Palette.level(heatmapLevel(count)))
        .frame(width: side, height: side)
        .help(label)
        .accessibilityLabel(label)
    }
  }

  private func monthLabels(_ dates: [Date], side: CGFloat) -> some View {
    let calendar = pomodoroCalendar()
    var labels: [(week: Int, text: String)] = []
    var previous = -1
    for week in 0..<heatmapWeeks {
      let sunday = dates[week * 7]
      let month = calendar.component(.month, from: sunday)
      guard month != previous else { continue }
      previous = month
      // A window opening mid-month would stack a sliver label on the next month's.
      if week == 0, calendar.component(.day, from: sunday) > 1 { continue }
      labels.append((week, sunday.formatted(.dateTime.month(.abbreviated))))
    }
    return ZStack(alignment: .topLeading) {
      ForEach(labels, id: \.week) { label in
        Text(label.text)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize()
          .offset(x: labelWidth + CGFloat(label.week) * (side + gap))
      }
    }
    .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)
    .accessibilityHidden(true)
  }

  private func monthYear(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).year())
  }

  private func minutesLabel(_ value: Int) -> String {
    value >= 60 ? "\(value / 60)h\(value % 60 > 0 ? " \(value % 60)m" : "")" : "\(value) min"
  }
}

enum Palette {
  // The same contribution-graph greens as the extension, light and dark.
  private static let levels: [Color] = [(0xEBEDF0, 0x2B2B2B), (0x9BE9A8, 0x0E4429), (0x40C463, 0x006D32),
                                        (0x30A14E, 0x26A641), (0x216E39, 0x39D353)].map { Color(light: $0.0, dark: $0.1) }

  static func level(_ level: Int) -> Color { levels[max(0, min(4, level))] }
}

extension Color {
  init(light: UInt32, dark: UInt32) {
    self.init(nsColor: NSColor(name: nil) { appearance in
      let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                     blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
  }
}

// MARK: - Settings

struct SettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    let settings = model.state.settings
    Form {
      if model.errorMessage != nil {
        Section { ErrorText(message: model.errorMessage) }
      }

      Section {
        number("Focus", \.focus, unit: "min")
        number("Short break", \.shortBreak, unit: "min")
        number("Long break", \.longBreak, unit: "min")
        number("Long break every", \.longEvery, unit: "sessions")
      } header: {
        Text("Session length")
      } footer: {
        Text("Set a break to 0 to skip it. Changes apply to the next session.").foregroundStyle(.secondary)
      }

      Section {
        number("Pomodoro target", \.dailyTarget, unit: "sessions")
      } header: {
        Text("Daily goal")
      } footer: {
        Text("Set to 0 for no target.").foregroundStyle(.secondary)
      }

      Section("When a session ends") {
        Toggle("Show a notification", isOn: flag(\.notify))
        if settings.notify, model.notificationsDenied {
          HStack {
            Text("Notifications for Macodoro are off in System Settings.").foregroundStyle(.secondary)
            Spacer()
            Button("Open System Settings") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
          }
        }
        Toggle("Show a completion window", isOn: flag(\.completionWindow))
      }

      Section {
        Toggle("Use keyboard shortcuts", isOn: flag(\.hotkeys))
        ForEach(HotKeyAction.allCases, id: \.self) { action in
          LabeledContent(action == .startFocus ? "Start focusing" : "Start break") {
            if settings.hotkeys, model.hotkeyConflicts.contains(action) {
              Text("\(action.display) · in use by another app").foregroundStyle(.red)
            } else {
              Text(action.display).monospaced().foregroundStyle(settings.hotkeys ? .primary : .secondary)
            }
          }
        }
      } header: {
        Text("Keyboard shortcuts")
      } footer: {
        Text("They work in any app. Each starts a new session and replaces a running or paused one. Start break takes a long break when one is due.")
          .foregroundStyle(.secondary)
      }

      Section("General") {
        Toggle("Open at login", isOn: Binding(get: { model.loginItemStatus == .enabled }, set: { model.setOpenAtLogin($0) }))
          .disabled(!model.canOpenAtLogin)
        if model.loginItemStatus == .requiresApproval {
          HStack {
            Text("Allow Macodoro in Login Items to finish.").foregroundStyle(.secondary)
            Spacer()
            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
          }
        }
        Picker("Appearance", selection: $model.appearance) {
          ForEach(Appearance.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
      }

      Section {
        Text("Macodoro keeps your settings and history on this Mac. It collects no analytics and sends nothing over the network.")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Settings")
  }

  private func flag(_ key: WritableKeyPath<MacodoroCore.Settings, Bool>) -> Binding<Bool> {
    Binding(get: { model.state.settings[keyPath: key] }, set: { value in model.update { $0[keyPath: key] = value } })
  }

  private func number(_ label: String, _ key: WritableKeyPath<MacodoroCore.Settings, Int>, unit: String) -> some View {
    let range = MacodoroCore.Settings.range(of: key)
    let value = Binding<Int>(
      get: { model.state.settings[keyPath: key] },
      set: { value in model.update { $0[keyPath: key] = min(max(value, range.lowerBound), range.upperBound) } }
    )
    return LabeledContent(label) {
      HStack(spacing: 6) {
        TextField(label, value: value, format: .number)
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .frame(width: 56)
        Stepper(label, value: value, in: range).labelsHidden()
        Text(unit).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
      }
    }
  }
}
