import Charts
import HoopoeCore
import SwiftUI

/// Totals, chart and per-task breakdown for a day, week or month.
struct OverviewView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Ticker.self) private var ticker
    @State private var period: Period = .week
    @State private var anchor = Date()
    @State private var hovered: Date?
    private let calendar = Calendar.current

    var body: some View {
        let _ = store.revision
        let now = ticker.coarseNow(store)
        let interval = period.interval(containing: anchor, calendar: calendar)
        let entries = store.entries(in: interval)
        let buckets = Stats.buckets(entries, in: interval, by: period.bucket, calendar: calendar, now: now)
        let byTask = Stats.totalsByTask(entries, in: interval, now: now).sorted { $0.value > $1.value }
        let total = byTask.reduce(0) { $0 + $1.value }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(interval: interval)
                tiles(entries: entries, buckets: buckets, byTask: byTask, total: total, interval: interval, now: now)
                chart(buckets: buckets, interval: interval)
                breakdown(byTask: byTask, total: total)
            }
            .padding(20)
        }
    }

    // MARK: Header

    private func header(interval: DateInterval) -> some View {
        HStack(spacing: 10) {
            Text(title(for: interval))
                .font(.title2.weight(.semibold))
            Spacer()
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            HStack(spacing: 2) {
                IconButton(symbol: "chevron.left", help: "Previous \(period.rawValue)") { move(-1) }
                Button("Today") { anchor = Date() }
                    .controlSize(.small)
                    .disabled(interval.contains(Date()))
                IconButton(symbol: "chevron.right", help: "Next \(period.rawValue)") { move(1) }
            }
        }
    }

    private func move(_ amount: Int) {
        anchor = period.shift(anchor, by: amount, calendar: calendar)
        hovered = nil
    }

    private func title(for interval: DateInterval) -> String {
        switch period {
        case .day:
            return interval.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            let formatter = DateIntervalFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: interval.start, to: interval.end.addingTimeInterval(-1))
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        }
    }

    // MARK: Tiles

    private func tiles(
        entries: [TimeEntry], buckets: [Bucket], byTask: [(key: Int64, value: TimeInterval)],
        total: TimeInterval, interval: DateInterval, now: Date
    ) -> some View {
        let activeDays = buckets.filter { $0.duration > 0 }.count
        let longest = entries.map { Stats.overlap($0, interval, now: now) }.max() ?? 0
        return HStack(spacing: 10) {
            StatTile(label: "Total", value: Format.duration(total))
            if period == .day {
                StatTile(label: "Longest session", value: Format.duration(longest))
            } else {
                StatTile(label: "Average per active day", value: Format.duration(activeDays == 0 ? 0 : total / Double(activeDays)))
            }
            StatTile(label: "Sessions", value: "\(entries.count)")
            StatTile(label: "Top task", value: byTask.first.flatMap { store.task($0.key)?.name } ?? "–")
        }
    }

    // MARK: Chart

    private func chart(buckets: [Bucket], interval: DateInterval) -> some View {
        let unit: Calendar.Component = period.bucket
        // A day is charted in minutes per hour, longer periods in hours per day.
        let divisor: Double = period == .day ? 60 : 3600
        let selected = hovered.flatMap { date in
            interval.contains(date) ? buckets.last { $0.start <= date } : nil
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(period == .day ? "Minutes per hour" : "Hours per day").sectionLabel()
                Spacer()
                if let selected {
                    Text("\(bucketLabel(selected.start)) · \(Format.duration(selected.duration))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
            }
            .frame(height: 14)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Time", bucket.start, unit: unit),
                    y: .value("Tracked", bucket.duration / divisor),
                    width: .ratio(0.62)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(Theme.accent)
                .opacity(selected == nil || selected == bucket ? 1 : 0.4)
            }
            .chartXSelection(value: $hovered)
            .chartYScale(domain: 0...yMax(buckets, divisor: divisor))
            .chartXAxis {
                AxisMarks(values: xValues) { _ in
                    AxisValueLabel(format: xFormat, centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(number.formatted(.number.precision(.fractionLength(0...1))))\(period == .day ? "m" : "h")")
                        }
                    }
                }
            }
            .frame(height: 190)
            .overlay {
                if buckets.allSatisfy({ $0.duration == 0 }) {
                    Text("No time tracked in this \(period.rawValue)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func yMax(_ buckets: [Bucket], divisor: Double) -> Double {
        if period == .day { return 60 }
        let peak = (buckets.map(\.duration).max() ?? 0) / divisor
        return max(4, (peak / 2).rounded(.up) * 2)
    }

    private var xValues: AxisMarkValues {
        switch period {
        case .day: .stride(by: .hour, count: 3)
        case .week: .stride(by: .day)
        case .month: .stride(by: .day, count: 3)
        }
    }

    private var xFormat: Date.FormatStyle {
        switch period {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.day()
        }
    }

    private func bucketLabel(_ date: Date) -> String {
        period == .day
            ? date.formatted(.dateTime.hour().minute())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: Breakdown

    private func breakdown(byTask: [(key: Int64, value: TimeInterval)], total: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By task").sectionLabel()
            if byTask.isEmpty {
                Text("Nothing here yet. Start a timer from the menu bar, or add time in the Calendar tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                ForEach(byTask, id: \.key) { taskID, seconds in
                    GridRow {
                        Text(store.task(taskID)?.name ?? "Deleted task")
                            .lineLimit(1)
                            .frame(width: 170, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: max(4, proxy.size.width * seconds / (byTask.first?.value ?? 1)))
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 6)
                        Text(Format.duration(seconds))
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                        Text((seconds / max(total, 1)).formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}
