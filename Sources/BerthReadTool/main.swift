import Foundation
import BerthCore

// This host remains a normal-user process. It accepts no paths or shell text.
// Reuse the same script so its short-lived macOS authorization can be reused.
let source = try AuthorizationCommand.script(executable: URL(fileURLWithPath: "/usr/bin/sfltool"), arguments: ["dumpbtm"])
guard let script = NSAppleScript(source: source) else { exit(1) }
while let request = readLine() {
    let reply: SystemReadReply = autoreleasepool {
        guard request == "read" else { return SystemReadReply(error: "不支持的读取请求。", errorCode: -50) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return SystemReadReply(error: "系统认证已取消或后台记录未能读取。", errorCode: error[NSAppleScript.errorNumber] as? Int)
        }
        return SystemReadReply(output: result.stringValue ?? "")
    }
    guard let data = try? JSONEncoder().encode(reply) else { exit(1) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
