import Foundation

public enum Period: String, CaseIterable, Identifiable, Sendable {
    case day, week, month

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// The calendar day, week or month that contains `date`.
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    public func shift(_ date: Date, by amount: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: component, value: amount, to: date) ?? date
    }

    /// Granularity of the chart for this period: hours within a day, days otherwise.
    public var bucket: Calendar.Component { self == .day ? .hour : .day }

    private var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

public struct Bucket: Identifiable, Hashable, Sendable {
    public let start: Date
    public let duration: TimeInterval
    public var id: Date { start }
}

public enum Stats {
    /// Seconds of `entry` that fall inside `interval`. A running entry counts up to `now`.
    public static func overlap(_ entry: TimeEntry, _ interval: DateInterval, now: Date) -> TimeInterval {
        let start = max(entry.start, interval.start)
        let end = min(entry.end ?? now, interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    public static func total(_ entries: [TimeEntry], in interval: DateInterval, now: Date) -> TimeInterval {
        entries.reduce(0) { $0 + overlap($1, interval, now: now) }
    }

    public static func totalsByTask(_ entries: [TimeEntry], in interval: DateInterval, now: Date) -> [Int64: TimeInterval] {
        var totals: [Int64: TimeInterval] = [:]
        for entry in entries {
            let seconds = overlap(entry, interval, now: now)
            if seconds > 0 { totals[entry.taskID, default: 0] += seconds }
        }
        return totals
    }

    /// Splits `interval` into consecutive hour or day buckets and sums the tracked time in each.
    /// Entries that span a boundary (for example midnight) are divided between the buckets.
    public static func buckets(
        _ entries: [TimeEntry], in interval: DateInterval, by component: Calendar.Component,
        calendar: Calendar, now: Date
    ) -> [Bucket] {
        var result: [Bucket] = []
        var start = interval.start
        while start < interval.end {
            guard let next = calendar.date(byAdding: component, value: 1, to: start), next > start else { break }
            let slot = DateInterval(start: start, end: min(next, interval.end))
            result.append(Bucket(start: start, duration: total(entries, in: slot, now: now)))
            start = next
        }
        return result
    }
}

public enum Format {
    /// "3h 20m", "45m", "0m"
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "1:05" (hours:minutes) or "1:05:09" with seconds.
    public static func clock(_ seconds: TimeInterval, showSeconds: Bool) -> String {
        let total = Int(max(0, seconds))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return showSeconds
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", h, m)
    }
}
