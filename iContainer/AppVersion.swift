import Foundation

enum AppVersion {
    static var displayString: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }

    static var shortDisplayString: String {
        "v\(marketingVersion) (\(buildNumber))"
    }

    private static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

