import Foundation
import Testing
@testable import BerthCore

struct ActivityProjectionTests {
    private func archive(_ phase: ArchivePhase = .parked) -> ArchiveRecord {
        ArchiveRecord(id: UUID(), label: "example.agent", filename: "example.agent.plist", executable: nil,
            createdAt: Date(), fingerprint: "", wasLoaded: false, originalMode: 0o644, phase: phase)
    }

    @Test func completedParkingDisappearsFromCachedActivityListAndRestoreBringsItBack() {
        let rows = BackgroundActivityProjection.rows(from: [
            record("Example Developer", name: "Example Developer", kind: "developer (0x20)"),
            record("8.example.agent", name: "Agent", kind: "legacy agent (0x10008)", parent: "Example Developer"),
            record("2.example.app", name: "Example", kind: "app (0x2)"),
            record("16.example.daemon", name: "Daemon", kind: "legacy daemon (0x10010)", parent: "2.example.app")
        ])
        let hidden = BackgroundActivityProjection.visibleRows(rows, archives: [archive()], presentServiceLabels: ["example.daemon"])
        #expect(hidden.map(\.name) == ["Example.app"])
        for phase in [ArchivePhase.prepared, .fileRestored, .restored] {
            #expect(BackgroundActivityProjection.visibleRows(rows, archives: [archive(phase)], presentServiceLabels: []).count == 2)
        }
    }

    @Test func recreatedConfigurationAndAnotherInstalledMemberKeepTheGroupVisible() {
        let rows = BackgroundActivityProjection.rows(from: [
            record("Example Developer", name: "Example Developer", kind: "developer (0x20)"),
            record("8.example.agent", name: "Agent", kind: "legacy agent (0x10008)", parent: "Example Developer"),
            record("8.example.other", name: "Other Agent", kind: "legacy agent (0x10008)", parent: "Example Developer")
        ])
        for present in [Set(["example.agent"]), Set(["example.other"])] {
            #expect(BackgroundActivityProjection.visibleRows(rows, archives: [archive()], presentServiceLabels: present).count == 1)
        }
    }

    private func record(_ id: String, name: String, kind: String, uid: Int = 501, parent: String? = nil,
                        disposition: String = "[disabled, allowed, not notified] (0x2)") -> BackgroundItem {
        var details = ["Type": kind, "UID": String(uid), "Disposition": disposition]
        details["Parent Identifier"] = parent
        return BackgroundItem(id: "\(uid):\(id)", name: name, identifier: id, source: .systemRecord,
            sourceURL: nil, executable: nil, appURL: nil, details: details)
    }

    @Test func collapsesUsersAndHelperRecordsToTheVisibleActivityGroups() {
        let records = [
            record("2.example.app", name: "Example", kind: "app (0x2)", uid: -2),
            record("2.example.app", name: "Example", kind: "app (0x2)"),
            record("8192.example.app", name: "Example - background tasks", kind: "background tasks (0x2000)", parent: "2.example.app"),
            record("64.example.plugin", name: "Search Plugin", kind: "spotlight (0x40)", parent: "2.example.app"),
            record("Example Developer", name: "Example Developer", kind: "developer (0x20)"),
            record("8.example.agent", name: "Old Agent", kind: "legacy agent (0x10008)", parent: "Example Developer", disposition: "[enabled, disallowed, notified] (0x9)"),
            record("Unknown Developer", name: "Unknown Developer", kind: "developer (0x20)"),
            record("8.example.open", name: "open", kind: "legacy agent (0x10008)", parent: "Unknown Developer")
        ]
        let rows = BackgroundActivityProjection.rows(from: records, currentUID: 501)
        #expect(rows.count == 3)
        #expect(Set(rows.map(\.name)) == Set(["Example.app", "Example Developer", "open"]))
        #expect(rows.first { $0.name == "Example.app" }?.details["UID"] == "501")
        #expect(rows.first { $0.name == "Example Developer" }?.details["Berth Permission"] == "disallowed")
        #expect(rows.first { $0.name == "Example.app" }?.members?.count == 2)
    }

    @Test func developerRowUsesItsOwnChildAgentInsteadOfAnotherSameSignerDaemon() throws {
        let f = try Fixture()
        let user = try f.write(label: "example.agent")
        let daemon = LaunchItem(fileURL: f.directory.appendingPathComponent("daemon.plist"), label: "example.daemon",
            executable: "/usr/bin/true", scope: .daemon, fingerprint: "", executableExists: true, parkingRestriction: nil)
        let records = [
            record("Example Developer", name: "Example Developer", kind: "developer (0x20)"),
            record("8.example.agent", name: "Agent", kind: "legacy agent (0x10008)", parent: "Example Developer"),
            record("2.example.app", name: "Example", kind: "app (0x2)"),
            record("16.example.daemon", name: "Daemon", kind: "legacy daemon (0x10010)", uid: -2, parent: "2.example.app")
        ]
        let developer = try #require(BackgroundActivityProjection.rows(from: records, currentUID: 501).first { $0.name == "Example Developer" })
        let matches = BackgroundServiceMatch.candidates(for: developer, items: [user, daemon],
            signatures: [daemon.label: SigningInfo(developer: "Example Developer", teamID: "TEAM")])
        #expect(matches.map(\.label) == ["example.agent"])
    }

    @Test func usesTheRequestedLocalizationWithoutDependingOnTheHostAppLanguage() throws {
        let f = try Fixture()
        let app = f.directory.appendingPathComponent("Example.app")
        let contents = app.appendingPathComponent("Contents")
        let language = contents.appendingPathComponent("Resources/zh-Hans.lproj")
        try FileManager.default.createDirectory(at: language, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "example", "CFBundleDevelopmentRegion": "en"], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": "中文名称"], format: .binary, options: 0)
            .write(to: language.appendingPathComponent("InfoPlist.strings"))
        let item = BackgroundItem(id: "app", name: "Example", identifier: "example", source: .systemRecord,
            sourceURL: app, executable: nil, appURL: app)
        #expect(ActivityDisplayName.localized(item, languages: ["zh-Hans-CN"]) == "中文名称")
    }
}
