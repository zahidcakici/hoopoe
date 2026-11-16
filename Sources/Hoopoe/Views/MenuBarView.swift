import AppKit
import HoopoeCore
import SwiftUI

/// What sits in the menu bar: the bird, plus the elapsed time while a timer runs (optional).
struct MenuBarLabel: View {
    let store: TrackerStore
    let ticker: Ticker
    @AppStorage(Prefs.showTimer) private var showTimer = true
    @AppStorage(Prefs.showSeconds) private var showSeconds = false

    var body: some View {
        if let running = store.running {
            if showTimer {
                HStack(spacing: 4) {
                    Image(systemName: "bird.fill")
                    Text(Format.clock(running.duration(now: ticker.now), showSeconds: showSeconds))
                        .monospacedDigit()
                }
            } else {
                Image(systemName: "bird.fill")
            }
        } else {
            Image(systemName: "bird")
        }
    }
}

/// The popover under the menu bar item: start, stop, switch and add tasks.
struct MenuBarView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Ticker.self) private var ticker
    @Environment(UpdateService.self) private var updates
    @State private var newTask = ""

    var body: some View {
        let now = ticker.liveNow(store)
        let today = Period.day.interval(containing: now, calendar: .current)
        let totals = Stats.totalsByTask(store.entries(in: today), in: today, now: now)

        VStack(spacing: 0) {
            header(now: now)
            Divider()
            taskList(totals: totals)
            Divider()
            if case .available(let release) = updates.state {
                updateBanner(release)
                Divider()
            }
            footer(total: totals.values.reduce(0, +))
        }
        .frame(width: 300)
    }

    private func header(now: Date) -> some View {
        let resumable = store.lastTaskID.flatMap(store.task) ?? store.tasks.first
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let task = store.runningTask {
                    Text(task.name).font(.headline).lineLimit(1)
                } else {
                    Text(resumable.map { "Paused · \($0.name)" } ?? "No tasks yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(Format.clock(store.running?.duration(now: now) ?? 0, showSeconds: true))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.running == nil ? .tertiary : .primary)
            }
            Spacer(minLength: 0)
            Button(action: store.toggle) {
                Image(systemName: store.running == nil ? "play.fill" : "stop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(resumable == nil)
            .opacity(resumable == nil ? 0.4 : 1)
            .help(store.running == nil ? "Resume \(resumable?.name ?? "")" : "Stop timer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func taskList(totals: [Int64: TimeInterval]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.tasks) { task in
                        TaskButton(task: task, today: totals[task.id] ?? 0, isRunning: store.running?.taskID == task.id) {
                            store.running?.taskID == task.id ? store.stop() : store.start(taskID: task.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
            }
            .frame(maxHeight: 264)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField("New task", text: $newTask)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if store.addTask(name: newTask) != nil { newTask = "" }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private func updateBanner(_ release: ReleaseInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
            Text("Hoopoe \(release.version.description) is available")
            Spacer()
            Button("Update") {
                NSApp.keyWindow?.close()
                AppModel.shared.showDashboard(tab: .settings)
            }
            .controlSize(.small)
        }
        .font(.callout)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
    }

    private func footer(total: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Text("Today").foregroundStyle(.secondary)
            Text(Format.duration(total)).fontWeight(.semibold).monospacedDigit()
            Spacer()
            Button("Dashboard") {
                NSApp.keyWindow?.close() // dismiss the popover
                AppModel.shared.showDashboard()
            }
            .controlSize(.small)
            IconButton(symbol: "power", help: "Quit Hoopoe") { NSApp.terminate(nil) }
        }
        .font(.callout)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }
}

private struct TaskButton: View {
    let task: TaskItem
    let today: TimeInterval
    let isRunning: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isRunning ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .opacity(isRunning || hovering ? 1 : 0.45)
                    .frame(width: 16)
                Text(task.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(today > 0 ? Format.duration(today) : "–")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isRunning ? "Stop \(task.name)" : "Start \(task.name)")
    }

    private var background: Color {
        if isRunning { return Theme.accent.opacity(0.14) }
        return Color.primary.opacity(hovering ? 0.07 : 0)
    }
}
