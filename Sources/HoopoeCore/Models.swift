import Foundation

public struct TaskItem: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    public var createdAt: Date

    public init(id: Int64, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// A span of tracked time. `end == nil` means the timer is still running.
public struct TimeEntry: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var taskID: Int64
    public var start: Date
    public var end: Date?

    public init(id: Int64, taskID: Int64, start: Date, end: Date?) {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
    }

    public var isRunning: Bool { end == nil }

    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}
