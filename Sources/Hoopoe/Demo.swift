import AppKit
import HoopoeCore
import SwiftUI

/// Sample data for `--demo`, used for screenshots and for trying the app without touching real data.
@MainActor
enum DemoData {
    static func seed(_ store: TrackerStore) {
        let calendar = Calendar.current
        let names = ["Client work", "Deep work", "Email and admin", "Reading"]
        let tasks = names.compactMap { store.addTask(name: $0) }
        let today = calendar.startOfDay(for: Date())

        for offset in 1...45 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  !calendar.isDateInWeekend(day) else { continue }
            // Deterministic pseudo-random plan for the day.
            var hour = 8.5 + Double(offset % 3) * 0.5
            for slot in 0..<(2 + offset % 3) {
                let length = 0.75 + Double((offset * 7 + slot * 5) % 9) * 0.25
                let task = tasks[(offset + slot * 3) % tasks.count]
                let start = day.addingTimeInterval(hour * 3600)
                store.addEntry(taskID: task.id, start: start, end: start.addingTimeInterval(length * 3600))
                hour += length + 0.5
            }
        }

        let morning = today.addingTimeInterval(9 * 3600)
        if morning.addingTimeInterval(2 * 3600) < Date() {
            store.addEntry(taskID: tasks[0].id, start: morning, end: morning.addingTimeInterval(1.5 * 3600))
        }
        // A timer that has been running for 42 minutes.
        store.start(taskID: tasks[1].id)
        if var running = store.running {
            running.start = Date().addingTimeInterval(-42 * 60)
            store.updateEntry(running)
        }
    }
}

#if DEBUG
/// `Hoopoe --demo --snapshot <dir>` renders each screen to a PNG and exits. Development aid only.
@MainActor
enum Snapshot {
    static func run(directory: URL) {
        let model = AppModel.shared
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                for tab in DashboardTab.allCases {
                    model.navigation.tab = tab
                    await render(DashboardView(), size: CGSize(width: 800, height: 580), dark: dark,
                                 to: directory.appendingPathComponent("\(tab.rawValue)-\(suffix).png"), model: model)
                }
                await render(MenuBarView().tint(Theme.accent), size: nil, dark: dark,
                             to: directory.appendingPathComponent("menubar-\(suffix).png"), model: model)
            }
            NSApp.terminate(nil)
        }
    }

    private static func render(_ view: some View, size: CGSize?, dark: Bool, to url: URL, model: AppModel) async {
        let content = view
            .environment(model.store)
            .environment(model.ticker)
            .environment(model.updates)
            .environment(model.navigation)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(700))

        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
#endif
