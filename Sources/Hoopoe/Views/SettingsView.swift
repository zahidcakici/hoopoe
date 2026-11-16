import AppKit
import HoopoeCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.showTimer) private var showTimer = true
    @AppStorage(Prefs.showSeconds) private var showSeconds = false
    @AppStorage(Prefs.stopOnLock) private var stopOnLock = true
    @AppStorage(Prefs.resumeOnUnlock) private var resumeOnUnlock = false
    @AppStorage(Prefs.autoUpdateCheck) private var autoUpdateCheck = true
    @Environment(UpdateService.self) private var updates
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show elapsed time next to the icon", isOn: $showTimer)
                Toggle("Include seconds", isOn: $showSeconds)
                    .disabled(!showTimer)
            }

            Section {
                Toggle("Stop the timer when the screen locks or the Mac sleeps", isOn: $stopOnLock)
                Toggle("Resume it when I unlock", isOn: $resumeOnUnlock)
                    .disabled(!stopOnLock)
            } header: {
                Text("Away from the Mac")
            } footer: {
                Text("Closing the lid puts the Mac to sleep, so it stops the timer too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open Hoopoe at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("General")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $autoUpdateCheck)
                LabeledContent {
                    updateAction
                } label: {
                    Text("Hoopoe \(updates.currentVersion.description)")
                    Text(updateStatus)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Checking contacts GitHub once a day. Nothing about you or your tracked time is sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                LabeledContent("Stored only on this Mac") {
                    Button("Show in Finder") {
                        if let url = try? Database.defaultURL() {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 560)
    }

    private var updateStatus: String {
        switch updates.state {
        case .idle: "Not checked yet"
        case .checking: "Checking…"
        case .upToDate: "You have the latest version"
        case .available(let release): "Version \(release.version.description) is available"
        case .installing(let release): "Downloading and installing \(release.version.description)…"
        case .failed(let message): message
        }
    }

    @ViewBuilder private var updateAction: some View {
        switch updates.state {
        case .available(let release):
            HStack {
                Button("Release notes") { updates.openReleasePage(release) }
                if updates.canInstallInPlace, release.archiveURL != nil {
                    Button("Install and relaunch") { Task { await updates.install(release) } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Download") { updates.openReleasePage(release) }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .checking, .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Check now") { Task { await updates.check(userInitiated: true) } }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
