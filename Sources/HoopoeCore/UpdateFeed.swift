import Foundation

/// Dotted numeric version such as "1.2.3". A leading "v" is ignored.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.parts = parts.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let (l, r) = (lhs.part(index), rhs.part(index))
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var significant = parts
        while significant.last == 0 { significant.removeLast() }
        hasher.combine(significant)
    }

    private func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let pageURL: URL
    /// Zipped app bundle attached to the release, if there is one. Needed for in-place updates.
    public let archiveURL: URL?
}

/// Reads the latest release of the app from GitHub Releases.
public enum UpdateFeed {
    public struct ParseError: Error {}

    public static func latestReleaseURL(repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// Parses the GitHub "latest release" response. Only download links that point at
    /// this repository's own release assets over HTTPS are accepted.
    public static func parse(_ data: Data, repository: String) throws -> ReleaseInfo {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            let tag_name: String
            let html_url: String
            let assets: [Asset]
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let trusted = "https://github.com/\(repository)/releases/"
        guard let version = AppVersion(payload.tag_name),
              payload.html_url.hasPrefix(trusted),
              let pageURL = URL(string: payload.html_url) else { throw ParseError() }

        let archive = payload.assets.first {
            $0.name.hasPrefix("Hoopoe") && $0.name.hasSuffix(".zip")
                && $0.browser_download_url.hasPrefix(trusted + "download/")
        }
        return ReleaseInfo(version: version, pageURL: pageURL, archiveURL: archive.flatMap { URL(string: $0.browser_download_url) })
    }
}
