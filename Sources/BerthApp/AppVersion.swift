import Foundation

enum AppVersion {
    static var display: String {
        Bundle.main.object(forInfoDictionaryKey: "BerthReleaseVersion") as? String ?? "Development"
    }
}
