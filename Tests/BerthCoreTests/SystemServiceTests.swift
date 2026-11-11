import Foundation
import Testing
import Darwin
@testable import BerthCore

struct SystemServiceTests {
    @Test func daemonParkingRoundTripUsesTheSameProtectedJournal() throws {
        let f = try Fixture()
        f.controller.loaded = true
        let item = try f.write()
        let original = try Data(contentsOf: f.file)
        let manager = SystemServiceManager(source: f.agents, archive: f.archive, controller: f.controller)
        let parked = manager.perform(["park", f.file.lastPathComponent, item.label, item.fingerprint])
        #expect(parked.error == nil)
        let record = try #require(parked.records.first)
        #expect(record.phase == .parked)
        #expect(record.originalOwnerID == getuid())
        #expect(!FileManager.default.fileExists(atPath: f.file.path))
        let restored = manager.perform(["restore", record.id.uuidString])
        #expect(restored.error == nil)
        #expect(restored.records.first?.phase == .restored)
        #expect(try Data(contentsOf: f.file) == original)
        #expect(f.controller.unloadCount == 1)
        #expect(f.controller.loadCount == 1)
    }

    @Test func rejectsTraversalChangedContentAndAppleServicesBeforeStopping() throws {
        let f = try Fixture()
        f.controller.loaded = true
        let item = try f.write()
        let manager = SystemServiceManager(source: f.agents, archive: f.archive, controller: f.controller)
        #expect(manager.perform(["park", "../other.plist", item.label, item.fingerprint]).error != nil)
        #expect(manager.perform(["park", f.file.lastPathComponent, "com.apple.protected", item.fingerprint]).error != nil)
        _ = try f.write(executable: "/usr/bin/false")
        #expect(manager.perform(["park", f.file.lastPathComponent, item.label, item.fingerprint]).error != nil)
        #expect(f.controller.unloadCount == 0)
        #expect(FileManager.default.fileExists(atPath: f.file.path))
    }

    @Test func systemRestoreConflictReturnsRecoveryRecordWithoutOverwriting() throws {
        let f = try Fixture()
        let item = try f.write()
        let manager = SystemServiceManager(source: f.agents, archive: f.archive, controller: f.controller)
        let parked = manager.perform(["park", f.file.lastPathComponent, item.label, item.fingerprint])
        let record = try #require(parked.records.first)
        _ = try f.write(executable: "/usr/bin/false")
        let changed = try Data(contentsOf: f.file)
        let failed = manager.perform(["restore", record.id.uuidString])
        #expect(failed.error != nil)
        #expect(failed.records.first?.phase == .parked)
        #expect(try Data(contentsOf: f.file) == changed)
    }

    @Test func developerCertificateMatchDoesNotSelectAnAppsHelperByTeamAlone() throws {
        let f = try Fixture()
        let source = try f.write()
        let daemon = LaunchItem(fileURL: source.fileURL, label: source.label, executable: source.executable,
            scope: .daemon, fingerprint: source.fingerprint, executableExists: true, parkingRestriction: "read only")
        let signatures = [daemon.label: SigningInfo(developer: "Example Developer", teamID: "EXAMPLETEAM")]
        let developer = BackgroundItem(id: "developer", name: "Example Developer", identifier: "team.EXAMPLETEAM",
            source: .systemRecord, sourceURL: nil, executable: nil, appURL: nil, details: ["Team Identifier": "EXAMPLETEAM"])
        #expect(BackgroundServiceMatch.candidates(for: developer, items: [daemon], signatures: signatures).count == 1)
        let app = BackgroundItem(id: "app", name: "Example.app", identifier: "example.app",
            source: .systemRecord, sourceURL: nil, executable: nil, appURL: URL(fileURLWithPath: "/Applications/Example.app"),
            details: ["Team Identifier": "EXAMPLETEAM"])
        #expect(BackgroundServiceMatch.candidates(for: app, items: [daemon], signatures: signatures).isEmpty)
    }

    @Test func authorizationTransportPreservesShellMetacharactersAsLiteralData() throws {
        let value = "a'b\"c $(printf injected); 中文"
        let script = try AuthorizationCommand.script(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", value], administrator: false)
        let result = try CommandRunner().run("/usr/bin/osascript", arguments: ["-e", script])
        #expect(result.status == 0)
        #expect(result.output.trimmingCharacters(in: .newlines) == value)
        #expect(throws: (any Error).self) { try AuthorizationCommand.script(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["line\nbreak"]) }
    }
}
