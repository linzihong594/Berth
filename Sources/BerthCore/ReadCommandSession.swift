import Foundation
import Darwin

/// A normal-user child with a line protocol. Keeping the script host alive lets
/// macOS reuse its short-lived authorization; only each fixed read runs elevated.
public final class ReadCommandSession: @unchecked Sendable {
    private let lock = NSLock()
    private let executable: URL
    private let arguments: [String]
    private let idleTimeout: TimeInterval
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var idleWork: DispatchWorkItem?
    private var lastUse = Date.distantPast

    public init(executable: URL, arguments: [String] = [], idleTimeout: TimeInterval = 300) {
        self.executable = executable
        self.arguments = arguments
        self.idleTimeout = idleTimeout
    }

    deinit {
        idleWork?.cancel()
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        try? input?.close(); try? output?.close()
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        stop()
    }

    public func request(_ command: String, timeout: TimeInterval = 60) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard !command.contains(where: \.isNewline) else { throw BerthError.message("读取请求格式无效。") }
        // Scheduled cleanup can be delayed under load. Never reuse an expired
        // host just because its idle callback has not run yet.
        if Date().timeIntervalSince(lastUse) >= idleTimeout { stop() }
        lastUse = Date()
        idleWork?.cancel()
        if process?.isRunning != true {
            stop()
            let child = Process(), stdin = Pipe(), stdout = Pipe()
            child.executableURL = executable
            child.arguments = arguments
            child.standardInput = stdin
            child.standardOutput = stdout
            child.standardError = FileHandle.nullDevice
            try child.run()
            // Parent must not retain the child's pipe ends, or EOF cannot wake a timeout.
            try stdin.fileHandleForReading.close()
            try stdout.fileHandleForWriting.close()
            process = child
            input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }
        guard let child = process, let input, let output else { throw BerthError.message("无法启动读取会话。") }
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + timeout)
        watchdog.setEventHandler { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        watchdog.resume()
        defer { watchdog.cancel() }
        do {
            try input.write(contentsOf: Data((command + "\n").utf8))
            var response = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while response.count <= 8 * 1024 * 1024 {
                // FileHandle.read(upToCount:) may wait to fill the buffer. A pipe
                // exchange must return as soon as one response line is available.
                let count = Darwin.read(output.fileDescriptor, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw BerthError.message("读取会话已结束或等待超时，未自动重试；原有列表已保留。若认证窗口仍在，请点取消。")
                }
                response.append(contentsOf: buffer.prefix(count))
                if response.last == 10 {
                    lastUse = Date()
                    let work = DispatchWorkItem { [weak self] in self?.closeIfIdle() }
                    idleWork = work
                    DispatchQueue.global().asyncAfter(deadline: .now() + idleTimeout, execute: work)
                    return response
                }
            }
            throw BerthError.message("读取结果超过大小限制，原有列表已保留。")
        } catch {
            stop()
            throw error
        }
    }

    private func closeIfIdle() {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(lastUse) >= idleTimeout { stop() }
    }

    private func stop() {
        idleWork?.cancel(); idleWork = nil
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil
    }
}

public struct SystemReadReply: Codable, Sendable {
    public let output: String?
    public let error: String?
    public let errorCode: Int?
    public init(output: String? = nil, error: String? = nil, errorCode: Int? = nil) {
        self.output = output; self.error = error; self.errorCode = errorCode
    }
}
