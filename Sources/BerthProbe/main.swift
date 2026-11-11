import Foundation
import BerthCore

let start = Date()
let scan = ItemScanner().scan()
let archive = ParkingStore().list()
let jobs: [String: Int?]?
var diagnostics = scan.warnings + archive.warnings
do { jobs = try LaunchController().loadedJobs() }
catch { jobs = nil; diagnostics.append(error.localizedDescription) }
var validatedSources = 0
for item in scan.items where item.scope == .user && jobs?.keys.contains(item.label) == true {
    do {
        try LaunchController().validateLoadedSource(label: item.label, fileURL: item.fileURL)
        validatedSources += 1
    } catch { diagnostics.append("载入来源核对：\(error.localizedDescription)") }
}
var output: [String: Any] = [
    "mode": "read-only",
    "items": scan.items.count,
    "systemRecordsRead": false,
    "userAgents": scan.items.filter { $0.scope == .user }.count,
    "sharedAgents": scan.items.filter { $0.scope == .shared }.count,
    "daemons": scan.items.filter { $0.scope == .daemon }.count,
    "loadedInUserDomain": scan.items.filter { $0.scope != .daemon && jobs?.keys.contains($0.label) == true }.count,
    "validatedLoadedUserSources": validatedSources,
    "parked": archive.records.filter { $0.phase != .restored }.count,
    "elapsedMilliseconds": Int(Date().timeIntervalSince(start) * 1000),
    "diagnostics": diagnostics
]
if CommandLine.arguments.contains("--attributions") {
    output["serviceAttributions"] = scan.items.filter { $0.scope == .daemon }.compactMap { item -> [String: String]? in
        guard let signature = SigningInfo.read(executable: item.executable) else { return nil }
        return ["label": item.label, "developer": signature.developer, "teamID": signature.teamID]
    }
}
if CommandLine.arguments.contains("--system-snapshot"), let snapshot = try SystemSnapshotCache().load() {
    let rows = BackgroundActivityProjection.rows(from: snapshot.items) { ActivityDisplayName.localized($0) }
    output["systemActivityCount"] = rows.count
    output["systemActivityNames"] = rows.map(\.name)
    let signatures = Dictionary(uniqueKeysWithValues: scan.items.compactMap { item in
        SigningInfo.read(executable: item.executable).map { (item.label, $0) }
    })
    output["activityServiceMatches"] = rows.map { row in
        ["name": row.name, "labels": BackgroundServiceMatch.candidates(for: row, items: scan.items, signatures: signatures).map(\.label).joined(separator: ", ")]
    }
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
