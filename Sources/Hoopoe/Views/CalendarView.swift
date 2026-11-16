import HoopoeCore
import SwiftUI

/// Month grid with hours per day, plus the selected day's entries, which can be added, edited and deleted.
struct CalendarView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Ticker.self) private var ticker
    @State private var month = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var draft: EntryDraft?
    private let calendar = Calendar.current

    var body: some View {
        let _ = store.revision
        let now = ticker.coarseNow(store)
        let interval = Period.month.interval(containing: month, calendar: calendar)
        let days = Stats.buckets(store.entries(in: interval), in: interval, by: .day, calendar: calendar, now: now)

        HStack(spacing: 0) {
            monthGrid(interval: interval, days: days)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            dayDetail(now: now)
                .frame(width: 280)
        }
        .sheet(item: $draft) { EntryEditor(draft: $0) }
    }

    // MARK: Month grid

    private func monthGrid(interval: DateInterval, days: [Bucket]) -> some View {
        let peak = max(days.map(\.duration).max() ?? 0, 1)
        let leadingBlanks = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(interval.start.formatted(.dateTime.month(.wide).year()))
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(Format.duration(days.reduce(0) { $0 + $1.duration }))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    IconButton(symbol: "chevron.left", help: "Previous month") { move(-1) }
                    Button("Today") {
                        month = Date()
                        selectedDay = calendar.startOfDay(for: Date())
                    }
                    .controlSize(.small)
                    IconButton(symbol: "chevron.right", help: "Next month") { move(1) }
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(symbols[(index + calendar.firstWeekday - 1) % 7])
                        .sectionLabel()
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 58) }
                ForEach(days) { day in
                    DayCell(
                        day: calendar.component(.day, from: day.start),
                        duration: day.duration,
                        intensity: day.duration / peak,
                        isToday: calendar.isDateInToday(day.start),
                        isSelected: day.start == selectedDay
                    ) { selectedDay = day.start }
                }
            }
        }
    }

    private func move(_ amount: Int) {
        month = Period.month.shift(month, by: amount, calendar: calendar)
    }

    // MARK: Day detail

    private func dayDetail(now: Date) -> some View {
        let interval = Period.day.interval(containing: selectedDay, calendar: calendar)
        let entries = store.entries(in: interval)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.headline)
                Text(Format.duration(Stats.total(entries, in: interval, now: now)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        EntryRow(
                            name: store.task(entry.taskID)?.name ?? "Deleted task",
                            entry: entry,
                            duration: Stats.overlap(entry, interval, now: now),
                            edit: { draft = EntryDraft(editing: entry) },
                            delete: { store.deleteEntry(id: entry.id) }
                        )
                    }
                    if entries.isEmpty {
                        Text("No time tracked on this day.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
            Button {
                draft = EntryDraft(newOn: selectedDay, taskID: store.lastTaskID ?? store.tasks.first?.id, calendar: calendar)
            } label: {
                Label("Add time", systemImage: "plus")
            }
            .disabled(store.tasks.isEmpty)
            .help(store.tasks.isEmpty ? "Create a task first" : "Add time on this day by hand")
            .padding(12)
        }
    }
}

private struct DayCell: View {
    let day: Int
    let duration: TimeInterval
    let intensity: Double
    let isToday: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(day)")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
                if duration >= 60 {
                    Text(Format.duration(duration))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .topLeading)
            // One hue, stronger with more tracked time.
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        duration >= 60 ? Theme.accent.opacity(0.12 + 0.38 * intensity) : Color.primary.opacity(0.04)
    }
}

private struct EntryRow: View {
    let name: String
    let entry: TimeEntry
    let duration: TimeInterval
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                Text("\(time(entry.start)) – \(entry.end.map(time) ?? "now")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if hovering {
                IconButton(symbol: "pencil", help: "Edit", action: edit)
                IconButton(symbol: "trash", help: "Delete", action: delete)
            } else {
                Text(Format.duration(duration))
                    .monospacedDigit()
                    .foregroundStyle(entry.isRunning ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit", action: edit)
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: Editor

struct EntryDraft: Identifiable {
    let id = UUID()
    var entryID: Int64?
    var taskID: Int64
    var start: Date
    var end: Date
    var isRunning = false

    init(editing entry: TimeEntry) {
        entryID = entry.id
        taskID = entry.taskID
        start = entry.start
        end = entry.end ?? Date()
        isRunning = entry.isRunning
    }

    /// A new one-hour entry at 09:00 on `day`.
    init(newOn day: Date, taskID: Int64?, calendar: Calendar) {
        self.taskID = taskID ?? 0
        start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        end = start.addingTimeInterval(3600)
    }
}

struct EntryEditor: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: EntryDraft

    private var isValid: Bool {
        draft.isRunning ? draft.start < Date() : draft.end > draft.start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.entryID == nil ? "Add time" : "Edit time").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Task").foregroundStyle(.secondary)
                    Picker("Task", selection: $draft.taskID) {
                        ForEach(store.tasks) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Start").foregroundStyle(.secondary)
                    DatePicker("Start", selection: $draft.start).labelsHidden()
                }
                GridRow {
                    Text("End").foregroundStyle(.secondary)
                    if draft.isRunning {
                        Text("Still running")
                    } else {
                        DatePicker("End", selection: $draft.end).labelsHidden()
                    }
                }
            }

            HStack {
                if !isValid {
                    Text(draft.isRunning ? "Start must be in the past." : "End must be after start.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !draft.isRunning {
                    Text(Format.duration(draft.end.timeIntervalSince(draft.start)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 340)
        .tint(Theme.accent)
    }

    private func save() {
        let saved: Bool
        if let entryID = draft.entryID {
            saved = store.updateEntry(TimeEntry(
                id: entryID, taskID: draft.taskID, start: draft.start, end: draft.isRunning ? nil : draft.end))
        } else {
            saved = store.addEntry(taskID: draft.taskID, start: draft.start, end: draft.end)
        }
        if saved { dismiss() }
    }
}
