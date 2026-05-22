import Foundation
import Combine

/// Polls the GitHub Releases API for `apple/container` and exposes whether the
/// locally installed CLI is older than the latest published release.
///
/// The installed version is supplied from the outside (typically parsed from
/// `container system status` by `ServiceManager`). The remote check is rate
/// limited to once per hour so we don't hammer GitHub for users that leave the
/// app open.
@MainActor
final class ContainerReleaseChecker: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var latestReleaseURL: URL?
    @Published private(set) var installedVersion: String?
    @Published private(set) var isChecking: Bool = false
    /// True when an update has been detected and the popup has not yet been
    /// dismissed in this app session. Setting this back to `false` (e.g. when
    /// the alert is dismissed) prevents the popup from reappearing for the
    /// same detected version.
    @Published var shouldPresentUpdateAlert: Bool = false

    /// Tracks the latest version for which the popup has already been shown,
    /// so we don't pester the user repeatedly during the same session.
    private var alertedAboutVersion: String?

    static let releasesPageURL = URL(string: "https://github.com/apple/container/releases")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!
    private static let recheckInterval: TimeInterval = 3600

    private var lastFetchedAt: Date?

    var isUpdateAvailable: Bool {
        guard let installed = installedVersion, let latest = latestVersion else { return false }
        return Self.compareVersions(installed, latest) == .orderedAscending
    }

    func updateInstalledVersion(_ version: String?) {
        let sanitized = version.map(Self.sanitize)
        if sanitized != installedVersion {
            installedVersion = sanitized
            refreshUpdateAlertState()
        }
        Task { await checkForUpdateIfNeeded() }
    }

    /// Re-evaluates whether the update alert should fire. Called whenever the
    /// installed or remote version changes.
    private func refreshUpdateAlertState() {
        guard isUpdateAvailable, let latest = latestVersion else { return }
        if alertedAboutVersion != latest {
            alertedAboutVersion = latest
            shouldPresentUpdateAlert = true
        }
    }

    func checkForUpdateIfNeeded(force: Bool = false) async {
        if !force, let lastFetchedAt,
           Date().timeIntervalSince(lastFetchedAt) < Self.recheckInterval {
            return
        }
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            if let tag = json["tag_name"] as? String {
                latestVersion = Self.sanitize(tag)
            }
            if let urlString = json["html_url"] as? String, let url = URL(string: urlString) {
                latestReleaseURL = url
            } else {
                latestReleaseURL = Self.releasesPageURL
            }
            lastFetchedAt = Date()
            refreshUpdateAlertState()
        } catch {
            // Network errors are non-fatal: the banner simply stays hidden.
        }
    }

    private static func sanitize(_ raw: String) -> String {
        var version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.first == "v" || version.first == "V" {
            version.removeFirst()
        }
        return version
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericComponents(of: lhs)
        let rhsParts = numericComponents(of: rhs)
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericComponents(of version: String) -> [Int] {
        sanitize(version)
            .split(separator: ".")
            .map { component -> Int in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}
