import Foundation
import Darwin

public protocol LaunchControlling: Sendable {
    func loadedJobs() throws -> [String: Int?]
    func isLoaded(_ label: String) throws -> Bool
    func validateLoadedSource(label: String, fileURL: URL) throws
    func unload(_ label: String) throws
    func load(_ fileURL: URL) throws
}

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public let timedOut: Bool
}

private final class CommandDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var expired = false
    func expire() { lock.lock(); expired = true; lock.unlock() }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return expired }
}

public struct CommandRunner: Sendable {
    public init() {}

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval = 10) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = CommandDeadline()
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        watchdog.schedule(deadline: .now() + timeout)
        watchdog.setEventHandler {
            if process.isRunning { deadline.expire(); process.terminate() }
        }
        watchdog.resume()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self), timedOut: deadline.timedOut)
    }
}

public struct LaunchController: LaunchControlling {
    private let runner = CommandRunner()
    private let systemDomain: Bool
    private var domain: String { systemDomain ? "system" : "gui/\(getuid())" }
    public init(systemDomain: Bool = false) { self.systemDomain = systemDomain }

    public func loadedJobs() throws -> [String: Int?] {
        if systemDomain && geteuid() != 0 { throw BerthError.message("系统服务操作需要管理员认证。") }
        let result = try runner.run("/bin/launchctl", arguments: ["list"])
        guard result.status == 0 else { throw BerthError.message("无法读取载入状态：\(result.output)") }
        return try Self.parseJobs(result.output)
    }

    public static func parseJobs(_ text: String) throws -> [String: Int?] {
        let lines = text.split(separator: "\n")
        guard let header = lines.first, header.split(whereSeparator: \.isWhitespace).map(String.init) == ["PID", "Status", "Label"] else {
            throw BerthError.message("无法识别系统返回的状态格式，已保留未知状态。")
        }
        var result: [String: Int?] = [:]
        for line in lines.dropFirst() {
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 3, Int(fields[1]) != nil,
                  fields[0] == "-" || Int(fields[0]) != nil else {
                throw BerthError.message("系统返回了无法识别的载入状态。")
            }
            result[String(fields[2])] = .some(Int(fields[0]))
        }
        return result
    }

    public func isLoaded(_ label: String) throws -> Bool {
        guard validLabel(label) else { throw BerthError.message("无效的服务标识符。") }
        return try loadedJobs().keys.contains(label)
    }

    public func unload(_ label: String) throws {
        guard validLabel(label) else { throw BerthError.message("无效的服务标识符。") }
        let result = try runner.run("/bin/launchctl", arguments: ["bootout", "\(domain)/\(label)"])
        guard result.status == 0 else { throw BerthError.message("停止项目失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))") }
        guard try !isLoaded(label) else { throw BerthError.message("项目仍处于载入状态，配置未移出。") }
    }

    public func validateLoadedSource(label: String, fileURL: URL) throws {
        guard validLabel(label) else { throw BerthError.message("无效的服务标识符。") }
        let result = try runner.run("/bin/launchctl", arguments: ["print", "\(domain)/\(label)"])
        guard result.status == 0, let path = Self.sourcePath(result.output),
              URL(fileURLWithPath: path).standardizedFileURL == fileURL.standardizedFileURL else {
            throw BerthError.message("无法确认已载入服务来自这份配置。可能存在同名服务，操作已停止。")
        }
    }

    /// `print` is not a stable API; unrecognised or ambiguous output must fail closed.
    public static func sourcePath(_ output: String) -> String? {
        let paths = output.split(separator: "\n").compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("path = /") else { return nil }
            return String(text.dropFirst("path = ".count))
        }
        return paths.count == 1 ? paths[0] : nil
    }

    public func load(_ fileURL: URL) throws {
        let result = try runner.run("/bin/launchctl", arguments: ["bootstrap", domain, fileURL.path])
        guard result.status == 0 else {
            throw BerthError.message("配置已还原，载入失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))。可再次点按恢复。")
        }
    }
}
