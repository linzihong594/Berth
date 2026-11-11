import Foundation

public enum BackgroundSource: String, Codable, Sendable {
    case bundledAgent, bundledDaemon, loginHelper, accessoryApp, systemRecord

    public var title: String {
        switch self {
        case .bundledAgent: "App 内置代理"
        case .bundledDaemon: "App 内置服务"
        case .loginHelper: "App 登录助手"
        case .accessoryApp: "常驻 App"
        case .systemRecord: "系统后台记录"
        }
    }
}

/// Read-only discoveries. These can never be passed to ParkingStore.
public struct BackgroundItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let identifier: String
    public let source: BackgroundSource
    public let sourceURL: URL?
    public let executable: String?
    public let appURL: URL?
    public let details: [String: String]
    public let members: [BackgroundItem]?

    public init(id: String, name: String, identifier: String, source: BackgroundSource,
                sourceURL: URL?, executable: String?, appURL: URL?, details: [String: String] = [:], members: [BackgroundItem]? = nil) {
        self.id = id; self.name = name; self.identifier = identifier; self.source = source
        self.sourceURL = sourceURL; self.executable = executable; self.appURL = appURL; self.details = details
        self.members = members
    }
}

public struct BackgroundInventory: Sendable {
    public let items: [BackgroundItem]
    public let warnings: [String]
    public let applicationsChecked: Int
}
