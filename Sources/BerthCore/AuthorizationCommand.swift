import Foundation

public enum AuthorizationCommand {
    public static func script(executable: URL, arguments: [String], administrator: Bool = true) throws -> String {
        let values = [executable.path] + arguments
        guard values.allSatisfy({ !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw BerthError.message("命令参数包含控制字符，未请求认证。")
        }
        let command = values.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\"" + (administrator ? " with administrator privileges" : "") + " without altering line endings"
    }
}
