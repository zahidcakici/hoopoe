import Foundation
import SQLite3

public struct DatabaseError: Error, CustomStringConvertible {
    public let description: String
}

/// Thin wrapper over the system SQLite. All access happens on the main actor via `TrackerStore`.
public final class Database {
    private var handle: OpaquePointer?

    enum Bind {
        case int(Int64)
        case real(Double)
        case text(String)
        case null
    }

    /// Pass `":memory:"` for a throwaway database (used by tests).
    public init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            let message = lastMessage
            sqlite3_close(handle)
            throw DatabaseError(description: "Cannot open database: \(message)")
        }
        try exec("PRAGMA foreign_keys = ON")
        try exec("PRAGMA journal_mode = WAL")
        try exec("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                started_at REAL NOT NULL,
                ended_at REAL
            );
            CREATE INDEX IF NOT EXISTS entries_started_at ON entries(started_at);
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value REAL NOT NULL);
            """)
    }

    deinit { sqlite3_close(handle) }

    /// Default on-disk location: ~/Library/Application Support/Hoopoe/hoopoe.sqlite
    public static func defaultURL() throws -> URL {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Hoopoe", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hoopoe.sqlite")
    }

    // MARK: Tasks

    public func tasks() throws -> [TaskItem] {
        try query("SELECT id, name, created_at FROM tasks ORDER BY created_at, id") { row in
            TaskItem(id: row.int(0), name: row.text(1), createdAt: row.date(2))
        }
    }

    public func insertTask(name: String, createdAt: Date) throws -> TaskItem {
        try run("INSERT INTO tasks (name, created_at) VALUES (?, ?)", [.text(name), .real(createdAt.timeIntervalSince1970)])
        return TaskItem(id: sqlite3_last_insert_rowid(handle), name: name, createdAt: createdAt)
    }

    public func renameTask(id: Int64, name: String) throws {
        try run("UPDATE tasks SET name = ? WHERE id = ?", [.text(name), .int(id)])
    }

    /// Deletes the task and, through the foreign key, all of its entries.
    public func deleteTask(id: Int64) throws {
        try run("DELETE FROM tasks WHERE id = ?", [.int(id)])
    }

    // MARK: Entries

    private static let entryColumns = "id, task_id, started_at, ended_at"

    private static func entry(_ row: Row) -> TimeEntry {
        TimeEntry(id: row.int(0), taskID: row.int(1), start: row.date(2), end: row.optionalDate(3))
    }

    /// Entries that overlap `interval`, including a running one that started before its end.
    public func entries(overlapping interval: DateInterval) throws -> [TimeEntry] {
        try query(
            "SELECT \(Self.entryColumns) FROM entries WHERE started_at < ? AND (ended_at IS NULL OR ended_at > ?) ORDER BY started_at",
            [.real(interval.end.timeIntervalSince1970), .real(interval.start.timeIntervalSince1970)],
            map: Self.entry
        )
    }

    public func runningEntry() throws -> TimeEntry? {
        try query("SELECT \(Self.entryColumns) FROM entries WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1", map: Self.entry).first
    }

    public func latestEntry() throws -> TimeEntry? {
        try query("SELECT \(Self.entryColumns) FROM entries ORDER BY started_at DESC LIMIT 1", map: Self.entry).first
    }

    public func insertEntry(taskID: Int64, start: Date, end: Date?) throws -> TimeEntry {
        try run(
            "INSERT INTO entries (task_id, started_at, ended_at) VALUES (?, ?, ?)",
            [.int(taskID), .real(start.timeIntervalSince1970), end.map { .real($0.timeIntervalSince1970) } ?? .null]
        )
        return TimeEntry(id: sqlite3_last_insert_rowid(handle), taskID: taskID, start: start, end: end)
    }

    public func updateEntry(_ entry: TimeEntry) throws {
        try run(
            "UPDATE entries SET task_id = ?, started_at = ?, ended_at = ? WHERE id = ?",
            [.int(entry.taskID), .real(entry.start.timeIntervalSince1970),
             entry.end.map { .real($0.timeIntervalSince1970) } ?? .null, .int(entry.id)]
        )
    }

    public func deleteEntry(id: Int64) throws {
        try run("DELETE FROM entries WHERE id = ?", [.int(id)])
    }

    /// All-time tracked seconds per task; a running entry counts up to `now`.
    public func totalsByTask(now: Date) throws -> [Int64: TimeInterval] {
        let rows = try query(
            "SELECT task_id, SUM(COALESCE(ended_at, ?) - started_at) FROM entries GROUP BY task_id",
            [.real(now.timeIntervalSince1970)]
        ) { ($0.int(0), $0.double(1)) }
        return Dictionary(uniqueKeysWithValues: rows)
    }

    // MARK: Meta

    public func meta(_ key: String) throws -> Double? {
        try query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.double(0) }.first
    }

    public func setMeta(_ key: String, _ value: Double) throws {
        try run("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.text(key), .real(value)])
    }

    // MARK: Plumbing

    struct Row {
        let statement: OpaquePointer?
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(statement, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
        func text(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
        func date(_ i: Int32) -> Date { Date(timeIntervalSince1970: double(i)) }
        func optionalDate(_ i: Int32) -> Date? {
            sqlite3_column_type(statement, i) == SQLITE_NULL ? nil : date(i)
        }
    }

    private var lastMessage: String {
        handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError(description: lastMessage)
        }
    }

    private func run(_ sql: String, _ binds: [Bind] = []) throws {
        _ = try query(sql, binds) { _ in () }
    }

    private func query<T>(_ sql: String, _ binds: [Bind] = [], map: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError(description: lastMessage)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, bind) in binds.enumerated() {
            let index = Int32(offset + 1)
            switch bind {
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .real(let value): sqlite3_bind_double(statement, index, value)
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }

        var results: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: results.append(map(Row(statement: statement)))
            case SQLITE_DONE: return results
            default: throw DatabaseError(description: lastMessage)
            }
        }
    }
}
