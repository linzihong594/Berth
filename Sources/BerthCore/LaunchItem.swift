import Foundation
import CryptoKit

public enum ItemScope: String, Codable, Sendable, CaseIterable {
    case user, shared, daemon

    public var title: String {
        switch self {
        case .user: "当前用户"
        case .shared: "所有用户"
        case .daemon: "系统服务"
        }
    }
}

public struct LaunchItem: Identifiable, Sendable, Equatable {
    public var id: String { fileURL.path }
    public let fileURL: URL
    public let label: String
    public let executable: String?
    public let scope: ItemScope
    public let fingerprint: String
    public let executableExists: Bool?
    public let parkingRestriction: String?

    public var appBundleURL: URL? {
        guard let executable, executable.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: executable)
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    public var displayName: String {
        appBundleURL?.deletingPathExtension().lastPathComponent ?? label
    }

    public init(fileURL: URL, label: String, executable: String?, scope: ItemScope,
                fingerprint: String, executableExists: Bool?, parkingRestriction: String?) {
        self.fileURL = fileURL
        self.label = label
        self.executable = executable
        self.scope = scope
        self.fingerprint = fingerprint
        self.executableExists = executableExists
        self.parkingRestriction = parkingRestriction
    }
}

public struct ScanLocation: Sendable {
    public let url: URL
    public let scope: ItemScope
    public init(url: URL, scope: ItemScope) { self.url = url; self.scope = scope }

    public static var standard: [ScanLocation] {
        [ScanLocation(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"), scope: .user),
         ScanLocation(url: URL(fileURLWithPath: "/Library/LaunchAgents"), scope: .shared),
         ScanLocation(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), scope: .daemon)]
    }
}

public struct ScanResult: Sendable {
    public let items: [LaunchItem]
    public let warnings: [String]
}

public enum BerthError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

public func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func plistDictionary(_ data: Data) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let label = value["Label"] as? String, validLabel(label) else {
        throw BerthError.message("配置缺少有效的 Label。")
    }
    return value
}

func validLabel(_ label: String) -> Bool {
    !label.isEmpty && !label.hasPrefix("-") && !label.contains("/") &&
    !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
}
