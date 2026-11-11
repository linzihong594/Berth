import Foundation
@testable import BerthCore

final class FakeController: LaunchControlling, @unchecked Sendable {
    var loaded = false
    var failUnload = false
    var failLoad = false
    var mismatchedSource = false
    var unloadCount = 0
    var loadCount = 0
    var afterUnload: (() throws -> Void)?
    func loadedJobs() throws -> [String: Int?] { loaded ? ["dev.example.agent": nil] : [:] }
    func isLoaded(_ label: String) throws -> Bool { loaded }
    func validateLoadedSource(label: String, fileURL: URL) throws {
        if mismatchedSource { throw BerthError.message("模拟同名服务来源不同") }
    }
    func unload(_ label: String) throws {
        unloadCount += 1
        if failUnload { throw BerthError.message("模拟停止失败") }
        loaded = false
        try afterUnload?()
    }
    func load(_ fileURL: URL) throws {
        loadCount += 1
        if failLoad { throw BerthError.message("模拟载入失败") }
        loaded = true
    }
}

final class Fixture {
    let directory: URL
    let agents: URL
    let archive: URL
    let controller = FakeController()
    var store: ParkingStore { ParkingStore(root: archive, agentsDirectory: agents, controller: controller) }
    var file: URL { agents.appendingPathComponent("dev.example.agent.plist") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("berth-tests-" + UUID().uuidString)
        agents = directory.appendingPathComponent("LaunchAgents")
        archive = directory.appendingPathComponent("Archives")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    @discardableResult
    func write(label: String = "dev.example.agent", executable: String = "/usr/bin/true", binary: Bool = false, extra: [String: Any] = [:]) throws -> LaunchItem {
        var dict: [String: Any] = ["Label": label, "ProgramArguments": [executable], "RunAtLoad": true]
        dict.merge(extra) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: binary ? .binary : .xml, options: 0)
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        return try ItemScanner().readItem(at: file, scope: .user)
    }

    func recordURL(_ record: ArchiveRecord) -> URL { archive.appendingPathComponent(record.id.uuidString).appendingPathComponent("record.json") }
    func backupURL(_ record: ArchiveRecord) -> URL { archive.appendingPathComponent(record.id.uuidString).appendingPathComponent("original.plist") }
}
