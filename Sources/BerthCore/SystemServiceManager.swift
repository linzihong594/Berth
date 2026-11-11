import Foundation

public struct ServiceToolResponse: Codable, Sendable {
    public let version: Int
    public let records: [ArchiveRecord]
    public let error: String?
    public init(records: [ArchiveRecord], error: String?) { version = 1; self.records = records; self.error = error }
}

/// The executable host must require root. Directory arguments are injectable for fixture tests only;
/// the host always supplies the two fixed system directories below.
public struct SystemServiceManager: Sendable {
    public static let sourceDirectory = URL(fileURLWithPath: "/Library/LaunchDaemons")
    public static let archiveDirectory = URL(fileURLWithPath: "/Library/Application Support/Berth/SystemArchives")
    private let source: URL
    private let store: ParkingStore

    public init(source: URL = SystemServiceManager.sourceDirectory,
                archive: URL = SystemServiceManager.archiveDirectory,
                controller: any LaunchControlling = LaunchController(systemDomain: true)) {
        self.source = source
        store = ParkingStore(root: archive, agentsDirectory: source, controller: controller, managedScope: .daemon)
    }

    public func perform(_ arguments: [String]) -> ServiceToolResponse {
        var failure: String?
        do {
            switch arguments.first {
            case "list" where arguments.count == 1: break
            case "park" where arguments.count == 4:
                let filename = arguments[1], label = arguments[2], hash = arguments[3]
                guard Self.validFilename(filename), validLabel(label), !label.hasPrefix("com.apple."),
                      hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else {
                    throw BerthError.message("服务请求包含无效的文件名、标识符或校验值。")
                }
                let file = source.appendingPathComponent(filename)
                let scanned = try ItemScanner().readItem(at: file, scope: .daemon)
                guard scanned.label == label, scanned.fingerprint == hash else {
                    throw BerthError.message("服务配置已变化，未停止服务。请重新读取并核对。")
                }
                let validated = LaunchItem(fileURL: file, label: scanned.label, executable: scanned.executable,
                    scope: .daemon, fingerprint: scanned.fingerprint, executableExists: scanned.executableExists, parkingRestriction: nil)
                try store.park(validated)
            case "restore" where arguments.count == 2:
                guard let id = UUID(uuidString: arguments[1]) else { throw BerthError.message("暂存记录 ID 无效。") }
                try store.restore(id)
            default: throw BerthError.message("不支持的服务操作。")
            }
        } catch { failure = error.localizedDescription }
        let listing = store.list()
        if failure == nil, !listing.warnings.isEmpty { failure = listing.warnings.joined(separator: "\n") }
        return ServiceToolResponse(records: listing.records, error: failure)
    }

    private static func validFilename(_ name: String) -> Bool {
        name.hasSuffix(".plist") && !name.hasPrefix(".") && !name.contains("/") &&
        !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
