# Macodoro

A native macOS menu bar port of [Chromodoro](https://github.com/haileiyu/chromodoro), the Chrome Pomodoro extension. It keeps the same timer rules, badge, history heatmap, and CSV format. It has no dependencies and needs no account or server.

## Build and install

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```sh
./scripts/build-app.sh            # builds build/Macodoro.app
./scripts/build-app.sh --install  # also copies it to /Applications and opens it
```

The app is signed ad hoc for this Mac. Macodoro has no Dock icon; look for the tomato in the menu bar. On a Mac with a notch, a full menu bar puts the newest items under the notch, where they are hidden. To make room, hide other items in **System Settings → Menu Bar**, or ⌘-drag other icons out of the menu bar.

## Use

| Action | Result |
| --- | --- |
| Click the tomato when idle | Start the queued focus session or break |
| Click while running | Pause and keep the remaining time |
| Click while paused | Resume |
| Look at the badge | Remaining minutes, rounded up: `16m`, `15m`, … `1m` |
| Red badge / green badge / gray badge | Focus running / break running / paused |
| Gray tomato without a badge | Idle |
| Right-click (or Control-click) | Menu: status, Start focusing, Start break, history, settings, quit |
| ⇧⌘8 | Start focusing, replacing the current session |
| ⇧⌘9 | Start the break that is due, replacing the current session |

Defaults: 25-minute focus, 5-minute short break, and a 15-minute long break after every 4 completed focus sessions. Every session starts manually. Set a break to 0 to skip it. Start focusing and Start break replace whatever is running, so they are also how you abandon a session. An unfinished focus session is not recorded.

When a session ends, Macodoro can show a notification, a completion window, both, or neither. The completion window floats above other windows but does not take keyboard focus, so typing in another app cannot start a session by accident. It closes itself when a session starts anywhere. Click a notification to open your history.

## What changed from the Chrome extension

```
Chrome extension                      Macodoro
─────────────────────────────────     ─────────────────────────────────────
Toolbar icon + badge              →   Menu bar tomato + badge
Right-click context menu          →   Right-click menu
Shortcuts while Chrome is active  →   Global shortcuts in any app (can be turned off)
chrome.notifications              →   macOS notifications
End-of-session tab                →   Completion window
Options and history pages         →   One window with a History / Settings sidebar
chrome.storage.local              →   ~/Library/Application Support/Macodoro/state.json
Chrome Sync across devices        →   Not available; use CSV export and import
(none)                            →   Open at login
```

- **No sync.** iCloud sync needs a paid Apple developer signing identity, so this version keeps history on one Mac. Back it up with **Export CSV**.
- **Global shortcuts.** ⇧⌘8 and ⇧⌘9 now work in every app. If another app already holds one, Settings says so. Turn them off in **Settings → Keyboard shortcuts**. The shortcuts are fixed; they cannot be changed yet.
- **Settings apply at once.** There is no Save button, as is usual on macOS. A change affects the next session; a running session keeps its length.

## Bring your history from Chrome

1. In Chrome, open **Pomodoro history** and choose **Export CSV**.
2. In Macodoro, open **Pomodoro history** and choose **Import CSV**.

Imported days are stored apart from the days you complete on the Mac, and the two add up. Importing again replaces the earlier import, so importing the same Chrome file twice does not double-count. Import only the Chrome extension's export: a Mac export already contains your Mac days, so importing it counts them twice. **Remove Imported History** removes only the imported days. **Export CSV** writes both, in the same format as the extension.

## Timing

Running timers use wall-clock time, including time while the Mac sleeps. The deadline is authoritative: on wake, Macodoro records at most one completion and never starts another session on its own. A session counts on the local date of its scheduled end. A paused timer stays paused across restarts.

## Source

```
Sources/
├── MacodoroCore/        Pure Swift, no AppKit. Unit-tested.
│   ├── Model.swift        State, settings (with tolerant decoding), sessions
│   ├── Rules.swift        settle, toggle, startFocus, startBreak, apply, badge
│   ├── Dates.swift        Day keys, heatmap window and levels
│   └── HistoryCSV.swift   Export and import in the extension's format
└── Macodoro/            The app
    ├── MacodoroApp.swift       Entry point; wires updates, timers, wake, alerts
    ├── AppModel.swift            Owns state; every change goes through transact()
    ├── StatusItemController.swift Menu bar item, badge image, right-click menu
    ├── HotKeys.swift             Global shortcuts (Carbon; no Accessibility permission)
    ├── Notifier.swift            macOS notifications
    ├── Windows.swift             Main window, completion window, main menu
    └── Views.swift               SwiftUI: history heatmap, settings, completion
```

`MacodoroCore` is a port of the extension's `timer.js` and of the session rules in `background.js`. The tests in `Tests/MacodoroCoreTests` port the matching cases from `tests/timer.test.js` and `tests/background.test.js`, plus CSV and decoding tests.

```sh
./scripts/test.sh
```

The script adds the Swift Testing framework path that the Command Line Tools need. With full Xcode it runs plain `swift test`.

For development, set `MACODORO_STATE_DIR` to keep test data away from your real history:

```sh
open --env MACODORO_STATE_DIR=/tmp/macodoro-dev build/Macodoro.app
```

## Privacy

Settings and history stay in one JSON file on your Mac. Macodoro collects no analytics and makes no network requests.
