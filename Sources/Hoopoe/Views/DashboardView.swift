import HoopoeCore
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview, calendar, tasks, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DashboardView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        VStack(spacing: 0) {
            // Sits in the transparent title bar, centered between the window controls.
            Picker("View", selection: $navigation.tab) {
                ForEach(DashboardTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 8)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch navigation.tab {
                case .overview: OverviewView()
                case .calendar: CalendarView()
                case .tasks: TasksView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Theme.accent)
    }
}
