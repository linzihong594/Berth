import Foundation
import Testing
@testable import BerthCore

struct ParkingTests {
@Test func testLoadedAgentRoundTripPreservesBytesPermissionsAndBackup() throws {
    let f = try Fixture()
    f.controller.loaded = true
    let item = try f.write(binary: true)
    let original = try Data(contentsOf: f.file)
    let record = try f.store.park(item)
    #expect(record.phase == .parked)
    #expect(f.controller.unloadCount == 1)
    #expect(!FileManager.default.fileExists(atPath: f.file.path))
    #expect(try Data(contentsOf: f.backupURL(record)) == original)
    let restored = try f.store.restore(record.id)
    #expect(restored.phase == .restored)
    #expect(f.controller.loadCount == 1)
    #expect(try Data(contentsOf: f.file) == original)
    #expect(try Data(contentsOf: f.backupURL(record)) == original)
    let attributes = try FileManager.default.attributesOfItem(atPath: f.file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
    let rootAttributes = try FileManager.default.attributesOfItem(atPath: f.archive.path)
    #expect((rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func testUnloadedAgentStaysUnloadedAfterRestore() throws {
    let f = try Fixture()
    let record = try f.store.park(f.write())
    _ = try f.store.restore(record.id)
    #expect(f.controller.unloadCount == 0)
    #expect(f.controller.loadCount == 0)
    #expect(!f.controller.loaded)
}

@Test func testRefusesChangedConfigurationBeforeStoppingAnything() throws {
    let f = try Fixture()
    f.controller.loaded = true
    let item = try f.write()
    _ = try f.write(executable: "/usr/bin/false")
    #expect(throws: (any Error).self) { try f.store.park(item) }
    #expect(f.controller.unloadCount == 0)
    #expect(f.store.list().records.isEmpty)
}

@Test func testStopFailureLeavesSourceAndRecoverableRecord() throws {
    let f = try Fixture()
    f.controller.loaded = true
    f.controller.failUnload = true
    let item = try f.write()
    #expect(throws: (any Error).self) { try f.store.park(item) }
    #expect(FileManager.default.fileExists(atPath: f.file.path))
    let record = try #require(f.store.list().records.first)
    #expect(record.phase == .prepared)
    #expect(record.lastError != nil)
    f.controller.failUnload = false
    #expect(try f.store.restore(record.id).phase == .restored)
    #expect(f.controller.loadCount == 0)
}

@Test func testChangeDuringUnloadPreservesChangedSourceAndOriginalBackup() throws {
    let f = try Fixture()
    f.controller.loaded = true
    let item = try f.write()
    let original = try Data(contentsOf: f.file)
    f.controller.afterUnload = { _ = try f.write(executable: "/usr/bin/false") }
    #expect(throws: (any Error).self) { try f.store.park(item) }
    let record = try #require(f.store.list().records.first)
    #expect(try Data(contentsOf: f.backupURL(record)) == original)
    let changed = try Data(contentsOf: f.file)
    #expect(changed != original)
    #expect(throws: (any Error).self) { try f.store.restore(record.id) }
    #expect(try Data(contentsOf: f.file) == changed)
}

@Test func testRestoreNeverOverwritesDifferentRecreatedFile() throws {
    let f = try Fixture()
    let record = try f.store.park(f.write())
    _ = try f.write(executable: "/usr/bin/false")
    let recreated = try Data(contentsOf: f.file)
    #expect(throws: (any Error).self) { try f.store.restore(record.id) }
    #expect(try Data(contentsOf: f.file) == recreated)
    #expect(f.controller.loadCount == 0)
    #expect(f.store.list().records.first?.phase == .parked)
}

@Test func testCorruptedBackupIsRejected() throws {
    let f = try Fixture()
    let record = try f.store.park(f.write())
    try Data("corrupted".utf8).write(to: f.backupURL(record))
    #expect(throws: (any Error).self) { try f.store.restore(record.id) }
    #expect(!FileManager.default.fileExists(atPath: f.file.path))
}

@Test func testRestoreCanResumeAfterLoadFailureAcrossStoreInstances() throws {
    let f = try Fixture()
    f.controller.loaded = true
    let record = try f.store.park(f.write())
    f.controller.failLoad = true
    #expect(throws: (any Error).self) { try f.store.restore(record.id) }
    #expect(FileManager.default.fileExists(atPath: f.file.path))
    #expect(f.store.list().records.first?.phase == .fileRestored)
    f.controller.failLoad = false
    #expect(try f.store.restore(record.id).phase == .restored)
    #expect(f.controller.loadCount == 2)
}

@Test func testInterruptedMoveCanRestoreFromWriteAheadBackup() throws {
    let f = try Fixture()
    f.controller.loaded = true
    var record = try f.store.park(f.write())
    record.phase = .prepared
    try JSONEncoder().encode(record).write(to: f.recordURL(record), options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.recordURL(record).path)
    #expect(try f.store.restore(record.id).phase == .restored)
    #expect(FileManager.default.fileExists(atPath: f.file.path))
}

@Test func testSymlinkAtOriginalLocationIsNotFollowed() throws {
    let f = try Fixture()
    let record = try f.store.park(f.write())
    let target = f.directory.appendingPathComponent("untouched")
    try Data("keep".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: f.file, withDestinationURL: target)
    #expect(throws: (any Error).self) { try f.store.restore(record.id) }
    #expect(try String(contentsOf: target, encoding: .utf8) == "keep")
}

@Test func testForgedRecordCannotEscapeAgentDirectory() throws {
    let f = try Fixture()
    let record = try f.store.park(f.write())
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: f.recordURL(record))) as! [String: Any]
    json["filename"] = "../escape.plist"
    try JSONSerialization.data(withJSONObject: json).write(to: f.recordURL(record))
    #expect(throws: (any Error).self) { try f.store.restore(record.id) }
    #expect(!f.store.list().warnings.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: f.directory.appendingPathComponent("escape.plist").path))
}

@Test func testGroupWritableSourceIsViewOnly() throws {
    let f = try Fixture()
    _ = try f.write()
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: f.file.path)
    let item = try ItemScanner().readItem(at: f.file, scope: .user)
    #expect(item.parkingRestriction != nil)
    #expect(throws: (any Error).self) { try f.store.park(item) }
}

@Test func testSameLabelFromDifferentSourceIsNotStopped() throws {
    let f = try Fixture()
    f.controller.loaded = true
    f.controller.mismatchedSource = true
    let item = try f.write()
    #expect(throws: (any Error).self) { try f.store.park(item) }
    #expect(f.controller.unloadCount == 0)
    #expect(FileManager.default.fileExists(atPath: f.file.path))
}

@Test func testSourceParserRejectsUnknownOrAmbiguousOutput() {
    #expect(LaunchController.sourcePath("service = {\n\tpath = /Users/example/agent.plist\n}") == "/Users/example/agent.plist")
    #expect(LaunchController.sourcePath("unrecognised format") == nil)
    #expect(LaunchController.sourcePath("path = /first\npath = /second") == nil)
}
}
