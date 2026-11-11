import Foundation
import Darwin

public enum ArchivePhase: String, Codable, Sendable {
    case prepared, parked, fileRestored, restored

    public var title: String {
        switch self {
        case .prepared: "操作待核对"
        case .parked: "已暂存"
        case .fileRestored: "待完成恢复"
        case .restored: "已恢复"
        }
    }
}

public struct ArchiveRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let filename: String
    public let executable: String?
    public let createdAt: Date
    public let fingerprint: String
    public let wasLoaded: Bool
    public let originalMode: Int
    public var originalOwnerID: UInt32?
    public var originalGroupID: UInt32?
    public var phase: ArchivePhase
    public var lastError: String?
}

public struct ArchiveListing: Sendable {
    public let records: [ArchiveRecord]
    public let warnings: [String]
}

/// Access from a single worker actor. A file lock also excludes other app instances.
public struct ParkingStore: Sendable {
    public let root: URL
    public let agentsDirectory: URL
    private let controller: any LaunchControlling
    private let managedScope: ItemScope
    private var fm: FileManager { .default }

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Berth/Archives"),
                agentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
                controller: any LaunchControlling = LaunchController(), managedScope: ItemScope = .user) {
        self.root = root.standardizedFileURL
        self.agentsDirectory = agentsDirectory.standardizedFileURL
        self.controller = controller
        self.managedScope = managedScope
    }

    public func list() -> ArchiveListing {
        guard FileSafety.exists(root) else { return ArchiveListing(records: [], warnings: []) }
        var records: [ArchiveRecord] = []
        var warnings: [String] = []
        do {
            try validateDirectory(root)
            for directory in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
                do { records.append(try readRecord(id)) }
                catch { warnings.append("暂存记录 \(id.uuidString)：\(error.localizedDescription)") }
            }
        } catch { warnings.append("暂存区：\(error.localizedDescription)") }
        return ArchiveListing(records: records.sorted { $0.createdAt > $1.createdAt }, warnings: warnings)
    }

    @discardableResult
    public func park(_ item: LaunchItem) throws -> ArchiveRecord {
        try withLock {
            guard item.scope == managedScope, item.parkingRestriction == nil else {
                throw BerthError.message(item.parkingRestriction ?? "此项目仅供查看。")
            }
            try validateFilename(item.fileURL.lastPathComponent)
            try validateDirectory(agentsDirectory)
            guard item.fileURL.standardizedFileURL.deletingLastPathComponent() == agentsDirectory else {
                throw BerthError.message("项目不在此暂存区管理的启动目录内。")
            }
            try FileSafety.checkRegularOwnedFile(item.fileURL)
            let current = try Data(contentsOf: item.fileURL)
            guard fingerprint(current) == item.fingerprint,
                  try plistDictionary(current)["Label"] as? String == item.label else {
                throw BerthError.message("配置自扫描后已变化，请刷新后重试。")
            }
            guard !item.label.hasPrefix("com.apple.") else { throw BerthError.message("Apple 系统项目仅供查看。") }
            let loaded = try controller.isLoaded(item.label)
            if loaded { try controller.validateLoadedSource(label: item.label, fileURL: item.fileURL) }
            let attributes = try fm.attributesOfItem(atPath: item.fileURL.path)
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
            var record = ArchiveRecord(id: UUID(), label: item.label, filename: item.fileURL.lastPathComponent,
                executable: item.executable, createdAt: Date(), fingerprint: item.fingerprint,
                wasLoaded: loaded, originalMode: mode,
                originalOwnerID: (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
                originalGroupID: (attributes[.groupOwnerAccountID] as? NSNumber)?.uint32Value,
                phase: .prepared)
            let directory = recordDirectory(record.id)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            // Keep a separate original even if moving or bootstrapping later fails.
            try fm.copyItem(at: item.fileURL, to: directory.appendingPathComponent("original.plist"))
            guard fingerprint(try Data(contentsOf: directory.appendingPathComponent("original.plist"))) == record.fingerprint else {
                throw BerthError.message("备份校验失败，原文件未修改。")
            }
            try save(record)
            do {
                if loaded {
                    try controller.validateLoadedSource(label: item.label, fileURL: item.fileURL)
                    try controller.unload(item.label)
                }
                try FileSafety.checkRegularOwnedFile(item.fileURL)
                guard fingerprint(try Data(contentsOf: item.fileURL)) == record.fingerprint else {
                    throw BerthError.message("停止服务期间配置发生变化，已保留原文件与备份，请核对。")
                }
                try fm.moveItem(at: item.fileURL, to: directory.appendingPathComponent("parked.plist"))
                record.phase = .parked
                try save(record)
                return record
            } catch {
                record.lastError = error.localizedDescription
                try? save(record)
                throw error
            }
        }
    }

    @discardableResult
    public func restore(_ id: UUID) throws -> ArchiveRecord {
        try withLock {
            var record = try readRecord(id)
            guard record.phase != .restored else { throw BerthError.message("此项目已经恢复。") }
            try validateFilename(record.filename)
            guard !record.label.hasPrefix("com.apple.") else { throw BerthError.message("不能恢复系统项目记录。") }
            let backup = recordDirectory(id).appendingPathComponent("original.plist")
            try FileSafety.checkRegularOwnedFile(backup)
            let data = try Data(contentsOf: backup)
            guard fingerprint(data) == record.fingerprint,
                  try plistDictionary(data)["Label"] as? String == record.label else {
                throw BerthError.message("备份内容与记录不符，恢复已停止。")
            }
            if !FileSafety.exists(agentsDirectory) {
                try fm.createDirectory(at: agentsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            }
            try validateDirectory(agentsDirectory)
            let destination = agentsDirectory.appendingPathComponent(record.filename)
            if FileSafety.exists(destination) {
                try FileSafety.checkRegularOwnedFile(destination)
                guard fingerprint(try Data(contentsOf: destination)) == record.fingerprint else {
                    throw BerthError.message("原位置已有不同内容的同名配置。已保留两个版本，请先核对；不会覆盖。")
                }
            } else {
                // copyItem fails if a file appeared at the destination in the meantime.
                try fm.copyItem(at: backup, to: destination)
                var ownership: [FileAttributeKey: Any] = [:]
                if let owner = record.originalOwnerID { ownership[.ownerAccountID] = NSNumber(value: owner) }
                if let group = record.originalGroupID { ownership[.groupOwnerAccountID] = NSNumber(value: group) }
                if !ownership.isEmpty { try fm.setAttributes(ownership, ofItemAtPath: destination.path) }
                try fm.setAttributes([.posixPermissions: record.originalMode], ofItemAtPath: destination.path)
            }
            record.phase = .fileRestored
            record.lastError = nil
            try save(record)
            do {
                if record.wasLoaded, try !controller.isLoaded(record.label) {
                    // Re-check immediately before handing the restored file to launchd.
                    try FileSafety.checkRegularOwnedFile(destination)
                    guard fingerprint(try Data(contentsOf: destination)) == record.fingerprint else {
                        throw BerthError.message("恢复期间配置发生变化，未载入。")
                    }
                    try controller.load(destination)
                    guard try controller.isLoaded(record.label) else {
                        throw BerthError.message("配置已还原，但尚未确认载入；请检查后重试。")
                    }
                }
                if record.wasLoaded {
                    try controller.validateLoadedSource(label: record.label, fileURL: destination)
                }
                record.phase = .restored
                try save(record)
                return record
            } catch {
                record.lastError = error.localizedDescription
                try? save(record)
                throw error
            }
        }
    }

    private func readRecord(_ id: UUID) throws -> ArchiveRecord {
        let directory = recordDirectory(id)
        try validateDirectory(directory)
        let file = directory.appendingPathComponent("record.json")
        try FileSafety.checkRegularOwnedFile(file)
        let record = try JSONDecoder().decode(ArchiveRecord.self, from: Data(contentsOf: file))
        guard record.id == id, validLabel(record.label), record.originalOwnerID == nil || record.originalOwnerID == getuid(),
              record.originalMode >= 0, record.originalMode <= 0o777,
              record.originalMode & 0o022 == 0 else { throw BerthError.message("暂存记录无效。") }
        try validateFilename(record.filename)
        return record
    }

    private func save(_ record: ArchiveRecord) throws {
        let url = recordDirectory(record.id).appendingPathComponent("record.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func recordDirectory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func validateFilename(_ filename: String) throws {
        guard !filename.isEmpty, !filename.hasPrefix("."), !filename.contains("/"),
              !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (filename as NSString).pathExtension == "plist" else {
            throw BerthError.message("配置文件名无效。")
        }
    }

    private func validateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              url.resolvingSymlinksInPath().path == url.path else {
            throw BerthError.message("目录包含符号链接或类型不正确，已停止操作。")
        }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o022 == 0 else {
            throw BerthError.message("目录所有者或写入权限不符合要求。")
        }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        if !FileSafety.exists(root) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try validateDirectory(root)
        let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw BerthError.message("无法锁定暂存区。") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw BerthError.message("另一个操作正在使用暂存区，请稍后重试。") }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
