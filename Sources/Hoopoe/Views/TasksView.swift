import HoopoeCore
import SwiftUI

/// Create, rename and delete tasks.
struct TasksView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Ticker.self) private var ticker
    @State private var newTask = ""
    @State private var pendingDelete: TaskItem?

    var body: some View {
        let _ = (store.revision, ticker.coarse)
        let totals = store.allTimeTotals()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tasks").font(.title2.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("New task name", text: $newTask)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("Name").sectionLabel()
                        Spacer()
                        Text("All time").sectionLabel()
                        Color.clear.frame(width: 24, height: 1)
                    }
                    .padding(.bottom, 8)

                    if store.tasks.isEmpty {
                        Text("No tasks yet. Add your first one above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(store.tasks) { task in
                        Divider()
                        TaskRow(task: task, total: totals[task.id] ?? 0, isRunning: store.running?.taskID == task.id) {
                            pendingDelete = task
                        }
                    }
                }
                .card()
            }
            .padding(20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { task in
            Button("Delete task and its time", role: .destructive) { store.deleteTask(id: task.id) }
        } message: { task in
            let tracked = totals[task.id] ?? 0
            Text(tracked > 0
                ? "This also deletes the \(Format.duration(tracked)) tracked on it. This cannot be undone."
                : "This cannot be undone.")
        }
    }

    private func add() {
        if store.addTask(name: newTask) != nil { newTask = "" }
    }
}

private struct TaskRow: View {
    @Environment(TrackerStore.self) private var store
    let task: TaskItem
    let total: TimeInterval
    let isRunning: Bool
    let delete: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Theme.accent : .clear)
                .frame(width: 6, height: 6)
                .help(isRunning ? "Timer running" : "")
            TextField("Task name", text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(commit)
            Text(Format.duration(total))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            IconButton(symbol: "trash", help: "Delete task", action: delete)
        }
        .padding(.vertical, 6)
        .onAppear { name = task.name }
        .onChange(of: task.name) { _, new in name = new }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    /// Saves the edited name; an empty name reverts to the old one.
    private func commit() {
        store.renameTask(id: task.id, name: name)
        name = store.task(task.id)?.name ?? name
    }
}
