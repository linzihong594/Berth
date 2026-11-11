import Foundation
import Testing
@testable import BerthCore

struct ReadSessionTests {
    @Test func repeatedRequestsReuseTheSameHostAndExplicitCloseStartsFresh() throws {
        let session = ReadCommandSession(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c",
            "count=0; while IFS= read -r request; do count=$((count + 1)); printf '%s\\n' \"$count\"; done"])
        #expect(String(decoding: try session.request("read", timeout: 2), as: UTF8.self) == "1\n")
        #expect(String(decoding: try session.request("read", timeout: 2), as: UTF8.self) == "2\n")
        session.close()
        #expect(String(decoding: try session.request("read", timeout: 2), as: UTF8.self) == "1\n")
    }

    @Test func idleSessionReleasesItsHost() throws {
        let session = ReadCommandSession(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c",
            "count=0; while IFS= read -r request; do count=$((count + 1)); printf '%s\\n' \"$count\"; done"], idleTimeout: 0.03)
        #expect(String(decoding: try session.request("read", timeout: 2), as: UTF8.self) == "1\n")
        Thread.sleep(forTimeInterval: 0.12)
        #expect(String(decoding: try session.request("read", timeout: 2), as: UTF8.self) == "1\n")
    }

    @Test func missingReplyTimesOutAndRequestsCannotInjectExtraLines() throws {
        let session = ReadCommandSession(executable: URL(fileURLWithPath: "/usr/bin/tail"), arguments: ["-f", "/dev/null"])
        #expect(throws: (any Error).self) { try session.request("read\nread") }
        let start = Date()
        #expect(throws: (any Error).self) { try session.request("read", timeout: 0.1) }
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
