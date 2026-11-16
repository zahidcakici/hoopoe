import AppKit
import HoopoeCore
import Security

/// Checks GitHub Releases for a newer version and can replace the running app with it.
///
/// A downloaded update is only installed if it is signed with a Developer ID certificate
/// from the same team as the running app. Unsigned and development builds can still check,
/// but are sent to the release page instead of updating in place.
@MainActor
@Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing(ReleaseInfo)
        case failed(String)
    }

    static let repository = "zahidcakici/hoopoe"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 3600

    private(set) var state: State = .idle
    let currentVersion: AppVersion
    /// Team that signed the running app; nil for ad-hoc and development builds.
    @ObservationIgnored private let teamID: String?
    @ObservationIgnored private var timer: Timer?

    init() {
        let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        currentVersion = bundled.flatMap(AppVersion.init) ?? AppVersion("0.0.0")!
        teamID = Self.teamID(of: Bundle.main.bundleURL)
    }

    private var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Whether an update can be installed without the user downloading it by hand.
    var canInstallInPlace: Bool {
        isAppBundle && teamID != nil
            && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    // MARK: Checking

    /// Checks at most once a day, at launch and then while the app keeps running.
    func startAutomaticChecks() {
        guard isAppBundle, timer == nil else { return }
        automaticCheckIfDue()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheckIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func automaticCheckIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.autoUpdateCheck),
              Date().timeIntervalSince1970 - defaults.double(forKey: Self.lastCheckKey) >= Self.checkInterval
        else { return }
        Task { await check(userInitiated: false) }
    }

    /// Background checks stay silent on failure; a check the user asked for reports it.
    func check(userInitiated: Bool) async {
        if case .checking = state { return }
        if case .installing = state { return }
        let previous = state
        state = .checking
        do {
            var request = URLRequest(url: UpdateFeed.latestReleaseURL(repository: Self.repository), timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Hoopoe", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { // no release published yet
                state = .upToDate
                return
            }
            guard status == 200 else { throw UpdateError("GitHub answered with status \(status).") }
            let release = try UpdateFeed.parse(data, repository: Self.repository)
            state = release.version > currentVersion ? .available(release) : .upToDate
        } catch {
            if userInitiated {
                state = .failed("Could not check for updates: \(error.localizedDescription)")
            } else {
                state = previous == .checking ? .idle : previous
            }
        }
    }

    // MARK: Installing

    func openReleasePage(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.pageURL)
    }

    /// Downloads the release, verifies its signature, swaps it in and relaunches.
    func install(_ release: ReleaseInfo) async {
        guard canInstallInPlace, let teamID, let archiveURL = release.archiveURL else {
            openReleasePage(release)
            return
        }
        state = .installing(release)
        let current = Bundle.main.bundleURL
        var workDirectory: URL?
        do {
            // A scratch directory on the same volume as the app, so the swap is a rename.
            let work = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
            workDirectory = work

            let (downloaded, response) = try await URLSession.shared.download(from: archiveURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download failed.") }
            let archive = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: archive)

            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            try await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
            let newApp = unpacked.appendingPathComponent("Hoopoe.app")

            try Self.verify(newApp, teamID: teamID)
            let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  let version = (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
                  version > currentVersion
            else { throw UpdateError("The downloaded app is not a newer version of Hoopoe.") }

            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
            try? FileManager.default.removeItem(at: work)
            try relaunch(current)
        } catch {
            if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
            state = .failed("Update failed: \((error as? UpdateError)?.message ?? error.localizedDescription)")
        }
    }

    /// Starts a helper that waits for this process to exit and then opens the new app.
    private func relaunch(_ app: URL) throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"",
            app.path,
        ]
        try helper.run()
        NSApp.terminate(nil)
    }

    // MARK: Code signature

    private static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        return code
    }

    private static func teamID(of url: URL) -> String? {
        guard let code = staticCode(url) else { return nil }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Requires a valid, unmodified Developer ID signature from `teamID`.
    private static func verify(_ app: URL, teamID: String) throws {
        let text = """
            anchor apple generic \
            and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
            and certificate leaf[subject.OU] = "\(teamID)"
            """
        var requirement: SecRequirement?
        guard teamID.allSatisfy({ $0.isLetter || $0.isNumber }),
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement, let code = staticCode(app)
        else { throw UpdateError("Could not read the update's signature.") }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateError("The update is not signed by the developer of this app, so it was not installed.")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError("Could not unpack the update."))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
