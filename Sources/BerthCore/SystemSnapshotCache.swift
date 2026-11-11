import Foundation
import Darwin

public struct SystemSnapshot: Codable, Sendable {
    public let version: Int
    public let readAt: Date
    public let items: [BackgroundItem]

    public init(readAt: Date = Date(), items: [BackgroundItem]) {
        self.version = 1; self.readAt = readAt; self.items = items
    }
}

public struct SystemSnapshotCache: Sendable {
    public let fileURL: URL
    public init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Berth/SystemSnapshot.json")) {
        self.fileURL = fileURL
    }

    public func load() throws -> SystemSnapshot? {
        guard FileSafety.exists(fileURL) else { return nil }
        try FileSafety.checkRegularOwnedFile(fileURL)
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { throw BerthError.message("系统快照超过大小限制。") }
        let snapshot = try JSONDecoder().decode(SystemSnapshot.self, from: Data(contentsOf: fileURL))
        guard snapshot.version == 1, snapshot.items.allSatisfy({ $0.source == .systemRecord }) else {
            throw BerthError.message("系统快照格式不符合要求。")
        }
        return snapshot
    }

    public func save(_ snapshot: SystemSnapshot) throws {
        guard snapshot.items.allSatisfy({ $0.source == .systemRecord }) else {
            throw BerthError.message("仅可缓存已读取的系统记录。")
        }
        let directory = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard directory.resolvingSymlinksInPath().path == directory.path,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw BerthError.message("系统快照目录不属于当前用户，或包含符号链接。")
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let allowed = Set(["UUID", "Name", "Developer Name", "Type", "Disposition", "Identifier", "URL",
                           "Executable Path", "Parent Identifier", "Team Identifier", "Assoc. Bundle IDs", "UID"])
        let sanitized = snapshot.items.map { item in
            BackgroundItem(id: item.id, name: item.name, identifier: item.identifier, source: .systemRecord,
                sourceURL: item.sourceURL, executable: item.executable, appURL: item.appURL,
                details: item.details.filter { allowed.contains($0.key) })
        }
        let data = try JSONEncoder().encode(SystemSnapshot(readAt: snapshot.readAt, items: sanitized))
        try data.write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
