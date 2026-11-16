import AppKit
import HoopoeCore
import SwiftUI

@main
struct HoopoeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model.store)
                .environment(model.ticker)
                .environment(model.updates)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel(store: model.store, ticker: model.ticker)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon until the dashboard is opened.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            Snapshot.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.store.stop()
    }
}

enum Prefs {
    static let showTimer = "showMenuBarTimer"
    static let showSeconds = "menuBarSeconds"
    static let stopOnLock = "stopOnLock"
    static let resumeOnUnlock = "resumeOnUnlock"
    static let autoUpdateCheck = "autoUpdateCheck"
}

/// Owns the long-lived pieces of the app and the dashboard window.
@MainActor
final class AppModel: NSObject, NSWindowDelegate {
    static let shared = AppModel()

    let store: TrackerStore
    let ticker = Ticker()
    let updates = UpdateService()
    let navigation = Navigation()
    private var monitor: SystemMonitor?
    private var dashboard: NSWindow?

    private override init() {
        UserDefaults.standard.register(defaults: [
            Prefs.showTimer: true,
            Prefs.showSeconds: false,
            Prefs.stopOnLock: true,
            Prefs.resumeOnUnlock: false,
            Prefs.autoUpdateCheck: true,
        ])

        // `--demo` runs against throwaway sample data and never touches the real database.
        let demo = CommandLine.arguments.contains("--demo")
        var openError: String?
        let database: Database
        do {
            database = try Database(path: demo ? ":memory:" : Database.defaultURL().path)
        } catch {
            openError = "Could not open the database, so nothing will be saved: \(error)"
            database = try! Database(path: ":memory:")
        }
        store = TrackerStore(database: database)
        store.lastError = openError
        super.init()

        if demo { DemoData.seed(store) }
        ticker.onHeartbeat = { [store] in store.heartbeat() }
        monitor = SystemMonitor(store: store)
        observeRunning()
        if !demo { updates.startAutomaticChecks() }
    }

    /// Keeps the one-second ticker alive only while a timer is running.
    private func observeRunning() {
        withObservationTracking {
            ticker.setActive(store.running != nil)
        } onChange: {
            Task { @MainActor [weak self] in self?.observeRunning() }
        }
    }

    func showDashboard(tab: DashboardTab? = nil) {
        if let tab { navigation.tab = tab }
        if dashboard == nil {
            let root = DashboardView()
                .environment(store)
                .environment(ticker)
                .environment(updates)
                .environment(navigation)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "Hoopoe"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 800, height: 580))
            window.contentMinSize = NSSize(width: 720, height: 500)
            window.center()
            window.setFrameAutosaveName("Dashboard")
            window.delegate = self
            dashboard = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the window and its views so the idle app holds only the menu bar item.
        dashboard = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Which dashboard tab is showing; shared so the menu bar can open a specific one.
@MainActor
@Observable
final class Navigation {
    var tab: DashboardTab = .overview
}

/// Publishes the current time once a second while a timer is running, and not at all otherwise.
@MainActor
@Observable
final class Ticker {
    /// Updated every second. Used by the live clock.
    private(set) var now = Date()
    /// Updated every 15 seconds. Used by statistics, which only show minutes.
    private(set) var coarse = Date()

    @ObservationIgnored var onHeartbeat: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0

    func setActive(_ active: Bool) {
        guard active != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard active else { return }

        ticks = 0
        now = Date()
        coarse = now
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        ticks += 1
        now = Date()
        if ticks % 15 == 0 { coarse = now }
        if ticks % 30 == 0 { onHeartbeat?() }
    }

    func liveNow(_ store: TrackerStore) -> Date { store.running == nil ? Date() : now }
    func coarseNow(_ store: TrackerStore) -> Date { store.running == nil ? Date() : coarse }
}

/// Stops the timer when the screen locks or the Mac sleeps (which includes closing the lid).
@MainActor
final class SystemMonitor {
    private let store: TrackerStore

    init(store: TrackerStore) {
        self.store = store
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter

        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // After waking, the screen is usually still locked; the unlock notification resumes then.
            MainActor.assumeIsolated {
                guard let self, !Self.isScreenLocked else { return }
                self.resume()
            }
        }
    }

    private func pause() {
        guard UserDefaults.standard.bool(forKey: Prefs.stopOnLock) else { return }
        store.systemPause()
    }

    private func resume() {
        guard UserDefaults.standard.bool(forKey: Prefs.resumeOnUnlock) else { return }
        store.systemResume()
    }

    private static var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
