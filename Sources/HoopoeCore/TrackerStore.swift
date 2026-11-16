import Foundation
import Observation

/// Single source of truth for tasks, entries and the running timer.
@MainActor
@Observable
public final class TrackerStore {
    public private(set) var tasks: [TaskItem] = []
    /// The entry currently being timed, if any. Only one timer runs at a time.
    public private(set) var running: TimeEntry?
    /// Task that `resume()` starts: the most recently tracked one.
    public private(set) var lastTaskID: Int64?
    /// Incremented whenever stored entries change, so views know to re-query.
    public private(set) var revision = 0
    /// Set when the timer was stopped by lock or sleep, so it can be resumed on unlock.
    public private(set) var autoPausedTaskID: Int64?
    public var lastError: String?

    @ObservationIgnored private let db: Database
    @ObservationIgnored private let now: () -> Date

    /// Sessions shorter than this are treated as accidental clicks and discarded.
    static let minimumSession: TimeInterval = 1
    private static let heartbeatKey = "heartbeat"

    public init(database: Database, now: @escaping () -> Date = { Date() }) {
        self.db = database
        self.now = now
        attempt {
            try closeOrphanedEntry()
            tasks = try db.tasks()
            lastTaskID = try db.latestEntry()?.taskID
        }
    }

    public func task(_ id: Int64) -> TaskItem? { tasks.first { $0.id == id } }
    public var runningTask: TaskItem? { running.flatMap { task($0.taskID) } }

    // MARK: Timer

    /// Starts timing `taskID`, stopping whatever was running before.
    public func start(taskID: Int64) {
        guard running?.taskID != taskID, task(taskID) != nil else { return }
        stop()
        attempt {
            let date = now()
            running = try db.insertEntry(taskID: taskID, start: date, end: nil)
            try db.setMeta(Self.heartbeatKey, date.timeIntervalSince1970)
            lastTaskID = taskID
            revision += 1
        }
    }

    public func stop() {
        autoPausedTaskID = nil
        guard var entry = running else { return }
        attempt {
            entry.end = now()
            if entry.duration(now: now()) < Self.minimumSession {
                try db.deleteEntry(id: entry.id)
            } else {
                try db.updateEntry(entry)
            }
            running = nil
            revision += 1
        }
    }

    /// Continues the most recently tracked task (or the first task if nothing was tracked yet).
    public func resume() {
        guard running == nil else { return }
        let candidate = lastTaskID.flatMap(task)?.id ?? tasks.first?.id
        if let candidate { start(taskID: candidate) }
    }

    public func toggle() {
        running == nil ? resume() : stop()
    }

    /// Called on screen lock or sleep. Remembers the task so `systemResume()` can continue it.
    public func systemPause() {
        guard let taskID = running?.taskID else { return }
        stop()
        autoPausedTaskID = taskID
    }

    /// Called on unlock or wake. Only restarts a timer that `systemPause()` stopped.
    public func systemResume() {
        guard let taskID = autoPausedTaskID else { return }
        autoPausedTaskID = nil
        start(taskID: taskID)
    }

    /// Records that the app is alive. If it later dies without stopping the timer,
    /// the open entry is closed at the last heartbeat instead of counting the downtime.
    public func heartbeat() {
        guard running != nil else { return }
        attempt { try db.setMeta(Self.heartbeatKey, now().timeIntervalSince1970) }
    }

    private func closeOrphanedEntry() throws {
        guard var entry = try db.runningEntry() else { return }
        let heartbeat = try db.meta(Self.heartbeatKey).map(Date.init(timeIntervalSince1970:))
        entry.end = max(entry.start, heartbeat ?? entry.start)
        if entry.duration(now: entry.start) < Self.minimumSession {
            try db.deleteEntry(id: entry.id)
        } else {
            try db.updateEntry(entry)
        }
    }

    // MARK: Tasks

    @discardableResult
    public func addTask(name: String) -> TaskItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var created: TaskItem?
        attempt {
            let task = try db.insertTask(name: trimmed, createdAt: now())
            tasks.append(task)
            created = task
        }
        return created
    }

    public func renameTask(id: Int64, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        attempt {
            try db.renameTask(id: id, name: trimmed)
            tasks[index].name = trimmed
        }
    }

    /// Deletes the task together with all time tracked on it.
    public func deleteTask(id: Int64) {
        if running?.taskID == id { stop() }
        attempt {
            try db.deleteTask(id: id)
            tasks.removeAll { $0.id == id }
            if autoPausedTaskID == id { autoPausedTaskID = nil }
            lastTaskID = try db.latestEntry()?.taskID
            revision += 1
        }
    }

    // MARK: Entries

    public func entries(in interval: DateInterval) -> [TimeEntry] {
        var result: [TimeEntry] = []
        attempt { result = try db.entries(overlapping: interval) }
        return result
    }

    public func allTimeTotals() -> [Int64: TimeInterval] {
        var result: [Int64: TimeInterval] = [:]
        attempt { result = try db.totalsByTask(now: now()) }
        return result
    }

    /// Adds a finished entry by hand. Returns false if the range is empty or the task is unknown.
    @discardableResult
    public func addEntry(taskID: Int64, start: Date, end: Date) -> Bool {
        guard end > start, task(taskID) != nil else { return false }
        var saved = false
        attempt {
            _ = try db.insertEntry(taskID: taskID, start: start, end: end)
            lastTaskID = try db.latestEntry()?.taskID
            revision += 1
            saved = true
        }
        return saved
    }

    /// Saves edits to an entry. For the running entry only the task and start can change.
    @discardableResult
    public func updateEntry(_ entry: TimeEntry) -> Bool {
        var entry = entry
        let isRunning = entry.id == running?.id
        if isRunning { entry.end = nil }
        guard task(entry.taskID) != nil, entry.start < (entry.end ?? now()) else { return false }
        var saved = false
        attempt {
            try db.updateEntry(entry)
            if isRunning { running = entry }
            lastTaskID = try db.latestEntry()?.taskID
            revision += 1
            saved = true
        }
        return saved
    }

    public func deleteEntry(id: Int64) {
        attempt {
            try db.deleteEntry(id: id)
            if running?.id == id { running = nil }
            lastTaskID = try db.latestEntry()?.taskID
            revision += 1
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { lastError = String(describing: error) }
    }
}
