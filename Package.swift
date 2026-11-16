// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Hoopoe",
    platforms: [.macOS(.v14)],
    targets: [
        // Storage, timer state machine and statistics. No UI, fully unit tested.
        .target(name: "HoopoeCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Hoopoe", dependencies: ["HoopoeCore"]),
        .testTarget(name: "HoopoeCoreTests", dependencies: ["HoopoeCore"]),
    ]
)
