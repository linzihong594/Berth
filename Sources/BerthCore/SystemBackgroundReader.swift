import Foundation
import Darwin

public struct SystemBackgroundReader: Sendable {
    private let session: ReadCommandSession
    public init() {
        let tool = (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL)
            .appendingPathComponent("BerthReadTool")
        session = ReadCommandSession(executable: tool)
    }

    public func endSession() { session.close() }

    /// Only call in direct response to the user pressing Read System List.
    /// Authenticate once before starting sfltool, so it does not queue its own prompt.
    public func read() throws -> BackgroundInventory {
        let data = try session.request("read")
        let reply = try JSONDecoder().decode(SystemReadReply.self, from: data)
        if reply.errorCode == -128 { throw BerthError.message("已取消系统认证，原有列表已保留。") }
        guard let output = reply.output, reply.error == nil else {
            throw BerthError.message("系统后台记录未能读取，或认证已取消。现有列表会保留。")
        }
        return try Self.parse(output)
    }

    public static func parse(_ text: String, currentUID: Int = Int(getuid())) throws -> BackgroundInventory {
        var uid: Int?
        var fields: [String: String] = [:]
        var recordNumber: Int?
        var sawUID = false
        var warnings: [String] = []
        var items: [BackgroundItem] = []
        var seen: Set<String> = []

        func flush() {
            defer { fields = [:]; recordNumber = nil }
            guard recordNumber != nil, let uid, [currentUID, 0, -2].contains(uid) else { return }
            let identifier = nonnull(fields["Identifier"])
            let uuid = nonnull(fields["UUID"])
            guard let key = uuid ?? identifier else {
                warnings.append("一条系统后台记录缺少标识符，未显示。")
                return
            }
            let id = "btm:\(uid):\(key)"
            guard seen.insert(id).inserted else { return }
            let sourceURL = localURL(nonnull(fields["URL"]))
            let executable = nonnull(fields["Executable Path"])
            let app = enclosingApp(sourceURL) ?? enclosingApp(executable.map { URL(fileURLWithPath: $0) })
            let name = nonnull(fields["Name"]) ?? nonnull(fields["Developer Name"]) ?? identifier ?? key
            var details = fields
            details["UID"] = String(uid)
            items.append(BackgroundItem(id: id, name: name, identifier: identifier ?? key,
                source: .systemRecord, sourceURL: sourceURL, executable: executable, appURL: app, details: details))
        }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Records for UID ") {
                flush()
                let rest = line.dropFirst("Records for UID ".count)
                uid = rest.split(whereSeparator: { $0 == " " || $0 == ":" }).first.flatMap { Int($0) }
                sawUID = sawUID || uid != nil
                continue
            }
            if line.hasPrefix("#"), line.hasSuffix(":"), let number = Int(line.dropFirst().dropLast()) {
                flush(); recordNumber = number; continue
            }
            guard recordNumber != nil, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            fields[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        flush()
        guard sawUID else {
            throw BerthError.message("未取得可识别的系统后台记录；可能未完成认证，或当前 macOS 的输出格式有变化。现有列表会保留。")
        }
        return BackgroundInventory(items: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                                   warnings: warnings, applicationsChecked: 0)
    }

    private static func nonnull(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !["(null)", "null"].contains(value) else { return nil }
        return value
    }

    private static func localURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        guard let url = URL(string: value), url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        return url
    }

    private static func enclosingApp(_ url: URL?) -> URL? {
        guard var url else { return nil }
        while url.path != "/" && !url.path.isEmpty {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
