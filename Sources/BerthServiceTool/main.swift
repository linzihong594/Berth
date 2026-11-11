import Foundation
import Darwin
import BerthCore

let response: ServiceToolResponse
if getuid() != 0 || geteuid() != 0 {
    response = ServiceToolResponse(records: [], error: "此操作只能在系统管理员认证后执行。")
} else {
    // All source and archive paths are fixed, and restore trusts only root-owned records.
    response = SystemServiceManager().perform(Array(CommandLine.arguments.dropFirst()))
}
do {
    let data = try JSONEncoder().encode(response)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
} catch { exit(1) }
