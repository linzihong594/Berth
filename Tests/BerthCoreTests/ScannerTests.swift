import Foundation
import Testing
@testable import BerthCore

struct ScannerTests {
@Test func testReadsBinaryPlistAndProgramTakesPrecedence() throws {
    let f = try Fixture()
    let item = try f.write(binary: true, extra: ["Program": "/usr/bin/false"])
    #expect(item.executable == "/usr/bin/false")
    #expect(item.label == "dev.example.agent")
    #expect(item.executableExists == true)
    #expect(item.parkingRestriction == nil)
}

@Test func testRelativeProgramIsUnknownRatherThanMissing() throws {
    let f = try Fixture()
    #expect(try f.write(executable: "true").executableExists == nil)
}

@Test func testMissingAbsoluteProgramIsReported() throws {
    let f = try Fixture()
    #expect(try f.write(executable: "/does-not-exist-berth-test/agent").executableExists == false)
}

@Test func testMalformedAndSymlinkConfigurationsAreVisibleWarnings() throws {
    let f = try Fixture()
    _ = try f.write()
    try Data("invalid".utf8).write(to: f.agents.appendingPathComponent("broken.plist"))
    try FileManager.default.createSymbolicLink(at: f.agents.appendingPathComponent("linked.plist"), withDestinationURL: f.file)
    let scan = ItemScanner(locations: [ScanLocation(url: f.agents, scope: .user)]).scan()
    #expect(scan.items.count == 1)
    #expect(scan.warnings.count == 2)
}

@Test func testMissingDirectoryIsEmptyAndReadOnlyScanCreatesNothing() throws {
    let f = try Fixture()
    let absent = f.directory.appendingPathComponent("absent")
    let scan = ItemScanner(locations: [ScanLocation(url: absent, scope: .user)]).scan()
    #expect(scan.items.isEmpty)
    #expect(scan.warnings.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: absent.path))
    #expect(f.store.list().records.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: f.archive.path))
}

@Test func testParserDistinguishesRunningLoadedAndMissing() throws {
    let jobs = try LaunchController.parseJobs("PID\tStatus\tLabel\n123\t0\tdev.running\n-\t0\tdev.waiting\n")
    #expect(jobs.keys.contains("dev.waiting"))
    #expect(jobs["dev.running"]! == 123)
    #expect(jobs["dev.waiting"]! == nil)
    #expect(!jobs.keys.contains("dev.absent"))
    #expect(throws: (any Error).self) { try LaunchController.parseJobs("unexpected format") }
}

@Test func testSystemScopesAreReadOnly() throws {
    let f = try Fixture()
    _ = try f.write()
    let item = try ItemScanner().readItem(at: f.file, scope: .shared)
    #expect(item.parkingRestriction != nil)
    #expect(throws: (any Error).self) { try f.store.park(item) }
    #expect(FileManager.default.fileExists(atPath: f.file.path))
}
}
