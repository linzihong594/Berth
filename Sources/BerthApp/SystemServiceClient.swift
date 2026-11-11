import Foundation
import BerthCore

struct SystemServiceClient: Sendable {
    private var receiptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Berth/SystemServiceReceipts.json")
    }

    func cachedRecords() throws -> [ArchiveRecord] {
        guard FileManager.default.fileExists(atPath: receiptURL.path) else { return [] }
        return try JSONDecoder().decode([ArchiveRecord].self, from: Data(contentsOf: receiptURL))
    }

    func perform(_ arguments: [String]) throws -> ServiceToolResponse {
        guard let main = Bundle.main.executableURL else { throw BerthError.message("无法定位服务工具。") }
        let tool = main.deletingLastPathComponent().appendingPathComponent("BerthServiceTool")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw BerthError.message("应用中缺少服务工具，请重新构建。") }
        let script = try AuthorizationCommand.script(executable: tool, arguments: arguments)
        let result = try CommandRunner().run("/usr/bin/osascript", arguments: ["-e", script], timeout: 60)
        if result.timedOut { throw BerthError.message("操作等待已超时，结果尚未确认。请用“同步系统暂存区”核对，不会自动重试。") }
        guard result.status == 0 else { throw BerthError.message("系统认证已取消或服务工具未能运行。") }
        guard let response = try? JSONDecoder().decode(ServiceToolResponse.self, from: Data(result.output.utf8)), response.version == 1 else {
            throw BerthError.message("服务工具的返回格式无法识别，操作结果尚未确认。")
        }
        // Receipts are for display only. Restore trusts the protected root-owned record, never this copy.
        let directory = receiptURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(response.records).write(to: receiptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptURL.path)
        return response
    }
}
