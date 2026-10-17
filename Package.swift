// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "Macodoro",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Macodoro", targets: ["Macodoro"])],
  targets: [
    // Timer rules, dates, and CSV: no AppKit, so every rule is unit-tested.
    .target(name: "MacodoroCore"),
    // Menu bar item, windows, notifications, hotkeys, and the saved state file.
    .executableTarget(name: "Macodoro", dependencies: ["MacodoroCore"]),
    .testTarget(name: "MacodoroCoreTests", dependencies: ["MacodoroCore"])
  ]
)
