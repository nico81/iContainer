import Foundation
import Combine

/// Polls the GitHub Releases API for `nico81/iContainer` and exposes whether
/// the running app bundle is older than the latest published release.
///
/// Mirrors `ContainerReleaseChecker` — same caching, same one-popup-per-session
/// behaviour — but the "installed" version is read from the app bundle rather
/// than supplied from the outside.
@MainActor
final class AppReleaseChecker: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var latestReleaseURL: URL?
    @Published private(set) var latestReleaseName: String?
    @Published private(set) var latestReleaseNotes: String?
    @Published private(set) var isChecking: Bool = false
    @Published var shouldPresentUpdateAlert: Bool = false

    private var alertedAboutVersion: String?

    static let releasesPageURL = URL(string: "https://github.com/nico81/iContainer/releases")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/nico81/iContainer/releases/latest")!
    private static let recheckInterval: TimeInterval = 3600

    private var lastFetchedAt: Date?

    let installedVersion: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return AppReleaseChecker.sanitize(raw)
    }()

    var isUpdateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.compareVersions(installedVersion, latest) == .orderedAscending
    }

    /// Forces the update alert to (re)appear if a newer version is known —
    /// the background check is gated by `alertedAboutVersion` to avoid
    /// pestering the user, but a manual "Check for Updates…" from the menu
    /// should always surface the popup when there's something to install.
    func presentUpdateAlertIfAvailable() {
        guard isUpdateAvailable else { return }
        shouldPresentUpdateAlert = true
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
            latestReleaseName = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            latestReleaseNotes = (json["body"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            lastFetchedAt = Date()
            refreshUpdateAlertState()
        } catch {
            // Network errors are non-fatal: the banner simply stays hidden.
        }
    }

    private func refreshUpdateAlertState() {
        guard isUpdateAvailable, let latest = latestVersion else { return }
        if alertedAboutVersion != latest {
            alertedAboutVersion = latest
            shouldPresentUpdateAlert = true
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
