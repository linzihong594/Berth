import Foundation
import Testing
@testable import BerthCore

struct BackgroundDetectionTests {
    @Test func acceptsLFCRAndCRLFFromAuthorizationTransport() throws {
        let lines = ["Records for UID 501 :", "#0:", "UUID: transport-fixture", "Name: Example Developer", "Identifier: example.agent"]
        for separator in ["\n", "\r", "\r\n"] {
            let parsed = try SystemBackgroundReader.parse(lines.joined(separator: separator), currentUID: 501)
            #expect(parsed.items.count == 1)
            #expect(parsed.items.first?.name == "Example Developer")
        }
    }

    @Test func parsesActualAppleScriptOutputWithoutAdministratorAuthentication() throws {
        // Exercise the same transport, using a fixed harmless fixture instead of sfltool.
        let script = #"do shell script "/usr/bin/printf 'Records for UID 501 :\\n#0:\\nUUID: transport\\nName: Example\\n'""#
        let result = try CommandRunner().run("/usr/bin/osascript", arguments: ["-e", script])
        #expect(result.status == 0)
        #expect(result.output.contains("\r"))
        #expect(try SystemBackgroundReader.parse(result.output, currentUID: 501).items.count == 1)
    }

    @Test func snapshotCacheIsPrivateAndExcludesDiscoveryCandidates() throws {
        let f = try Fixture()
        let cache = SystemSnapshotCache(fileURL: f.directory.appendingPathComponent("Cache/snapshot.json"))
        #expect(try cache.load() == nil)
        let data = "Records for UID 501 :\n#0:\nUUID: cached\nName: Example\nFuture Field: do not persist\n"
        let parsed = try SystemBackgroundReader.parse(data, currentUID: 501)
        try cache.save(SystemSnapshot(items: parsed.items))
        let saved = try #require(try cache.load())
        #expect(saved.items.count == 1)
        #expect(saved.items[0].details["Future Field"] == nil)
        let mode = try FileManager.default.attributesOfItem(atPath: cache.fileURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let discovery = BackgroundItem(id: "candidate", name: "Candidate", identifier: "candidate", source: .accessoryApp,
                                      sourceURL: nil, executable: nil, appURL: nil)
        #expect(throws: (any Error).self) { try cache.save(SystemSnapshot(items: [discovery])) }
        #expect(try cache.load()?.items.count == 1)
    }

    @Test func distinguishesInstalledAppFromBundledAndResidentItems() throws {
        let f = try Fixture()
        let root = f.directory.appendingPathComponent("Applications")
        let ordinary = try makeApp(root, name: "Ordinary", info: [:])
        let resident = try makeApp(root, name: "Resident", info: ["LSUIElement": "1"])
        let host = try makeApp(root, name: "Host", info: [:])
        _ = try makeApp(host.appendingPathComponent("Contents/Library/LoginItems"), name: "Helper", info: [:])
        let launch = host.appendingPathComponent("Contents/Library/LaunchAgents")
        try FileManager.default.createDirectory(at: launch, withIntermediateDirectories: true)
        let plist: [String: Any] = ["Label": "dev.example.host.agent", "BundleProgram": "Contents/MacOS/agent"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: launch.appendingPathComponent("agent.plist"))
        let scan = ApplicationScanner(directories: [root]).scan()
        #expect(scan.warnings.isEmpty)
        #expect(scan.applicationsChecked == 3)
        #expect(scan.items.count == 3)
        #expect(!scan.items.contains { $0.appURL?.path == ordinary.path })
        #expect(scan.items.contains { $0.source == .accessoryApp && $0.appURL?.path == resident.path })
        #expect(scan.items.contains { $0.source == .loginHelper && $0.appURL?.path == host.path })
        #expect(scan.items.contains { $0.source == .bundledAgent && $0.executable == host.appendingPathComponent("Contents/MacOS/agent").path })
        #expect(scan.items.allSatisfy { $0.details["Disposition"] == nil })
    }

    @Test func doesNotFollowApplicationSymlinksOrAllowBundleProgramEscape() throws {
        let f = try Fixture()
        let root = f.directory.appendingPathComponent("Apps")
        let app = try makeApp(root, name: "Safe", info: [:])
        let agents = app.appendingPathComponent("Contents/Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["Label": "dev.example.escape", "BundleProgram": "../outside"], format: .xml, options: 0)
            .write(to: agents.appendingPathComponent("escape.plist"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: app)
        let scan = ApplicationScanner(directories: [root]).scan()
        #expect(scan.applicationsChecked == 1)
        #expect(scan.items.count == 1)
        #expect(scan.items.first?.executable == nil)
    }

    @Test func readsOneNestedApplicationsFolderWithoutWalkingResources() throws {
        let f = try Fixture()
        let root = f.directory.appendingPathComponent("Apps")
        _ = try makeApp(root.appendingPathComponent("Utilities"), name: "Menu", info: ["LSUIElement": true])
        _ = try makeApp(root.appendingPathComponent("Folder/TooDeep"), name: "Ignored", info: ["LSUIElement": true])
        let scan = ApplicationScanner(directories: [root]).scan()
        #expect(scan.applicationsChecked == 1)
        #expect(scan.items.first?.name == "Menu")
    }

    @Test func parsesBTMWithSpacesAndKeepsDistinctUserRecords() throws {
        let text = """
        ========================
        Records for UID 501 :
        #0:
                  UUID: example-user
                  Name: Cloud Sync
                  Developer Name: Example Developer
                  Type: app (0x2)
                  Disposition: [enabled, allowed, notified] (0xb)
                  Identifier: com.example.cloud
                  URL: file:///Applications/Cloud%20Sync.app/
                  Executable Path: /Applications/Cloud Sync.app/Contents/MacOS/Cloud Sync
                  Future Field: preserved: with colon
        Records for UID 0 :
        #0:
                  UUID: example-root
                  Name: Example Daemon
                  Identifier: 16.com.example.daemon
                  URL: file:///Library/LaunchDaemons/com.example.daemon.plist
        Records for UID 502 :
        #0:
                  UUID: other-user
                  Name: Other User App
                  Identifier: com.example.other
        """
        let scan = try SystemBackgroundReader.parse(text, currentUID: 501)
        #expect(scan.items.count == 2)
        #expect(scan.warnings.isEmpty)
        let app = try #require(scan.items.first { $0.name == "Cloud Sync" })
        #expect(app.appURL?.path == "/Applications/Cloud Sync.app")
        #expect(app.details["Disposition"] == "[enabled, allowed, notified] (0xb)")
        #expect(app.details["Future Field"] == "preserved: with colon")
        #expect(app.details["UID"] == "501")
    }

    @Test func preservesDeveloperOnlyRecordsWithoutInventingAFile() throws {
        let text = """
        Records for UID -2 :
        #0:
            UUID: developer-group
            Name: Example Company
            Identifier: team.EXAMPLE
            URL: (null)
            Executable Path: (null)
        """
        let item = try #require(SystemBackgroundReader.parse(text, currentUID: 501).items.first)
        #expect(item.sourceURL == nil)
        #expect(item.executable == nil)
        #expect(item.appURL == nil)
        #expect(item.name == "Example Company")
    }

    @Test func rejectsUnknownBTMOutputAndReportsMalformedRecords() throws {
        #expect(throws: (any Error).self) { try SystemBackgroundReader.parse("not authorized") }
        let scan = try SystemBackgroundReader.parse("Records for UID 501 :\n#0:\nName: no id\n", currentUID: 501)
        #expect(scan.items.isEmpty)
        #expect(scan.warnings.count == 1)
        #expect(try SystemBackgroundReader.parse("Records for UID 501 :\n", currentUID: 501).items.isEmpty)
    }

    @Test func doesNotTreatRemoteBTMURLAsLocalFile() throws {
        let text = "Records for UID 501 :\n#0:\nUUID: remote\nName: Remote\nURL: file://server/share/App.app\n"
        let item = try #require(SystemBackgroundReader.parse(text, currentUID: 501).items.first)
        #expect(item.sourceURL == nil)
    }

    @Test func authenticationRunnerHasAFiniteDeadline() throws {
        let result = try CommandRunner().run("/bin/sleep", arguments: ["2"], timeout: 0.03)
        #expect(result.timedOut)
        #expect(result.status != 0)
    }

    private func makeApp(_ directory: URL, name: String, info extra: [String: Any]) throws -> URL {
        let app = directory.appendingPathComponent(name + ".app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "dev.example." + name, "CFBundleName": name, "CFBundleExecutable": name]
        info.merge(extra) { _, value in value }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}
