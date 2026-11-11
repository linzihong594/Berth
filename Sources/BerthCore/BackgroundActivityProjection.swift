import Foundation
import Darwin

/// Project BTM's internal records into the app/developer groups shown in Login Items.
/// Verified against the current macOS 27 list; the raw snapshot remains available for re-evaluation.
public enum BackgroundActivityProjection {
    /// Reconcile a cached system list with completed local operations. A recreated
    /// configuration remains visible, as does a group with another installed service.
    public static func visibleRows(_ rows: [BackgroundItem], archives: [ArchiveRecord],
                                   presentServiceLabels: Set<String>) -> [BackgroundItem] {
        let parked = Set(archives.filter { $0.phase == .parked }.map(\.label))
        guard !parked.isEmpty else { return rows }
        return rows.filter { row in
            let labels = serviceLabels(row)
            return labels.isDisjoint(with: parked) || !labels.isDisjoint(with: presentServiceLabels)
        }
    }

    public static func serviceLabels(_ row: BackgroundItem) -> Set<String> {
        let records = row.details["Berth Group Kind"] == "standalone" ? [row] : row.members ?? [row]
        return Set(records.filter { [4, 8, 16].contains(kind($0)) }.map { item in
            let id = item.identifier
            guard let dot = id.firstIndex(of: "."), Int(id[..<dot]) != nil else { return id }
            return String(id[id.index(after: dot)...])
        })
    }

    public static func rows(from records: [BackgroundItem], currentUID: Int = Int(getuid()),
                            localizedName: (BackgroundItem) -> String? = { _ in nil }) -> [BackgroundItem] {
        var selected: [String: BackgroundItem] = [:]
        func priority(_ item: BackgroundItem) -> Int {
            let uid = item.details["UID"].flatMap(Int.init)
            return uid == currentUID ? 3 : uid == -2 ? 2 : uid == 0 ? 1 : 0
        }
        for record in records {
            if let previous = selected[record.identifier], priority(previous) >= priority(record) { continue }
            selected[record.identifier] = record
        }
        let unique = Array(selected.values)
        var roots = unique.filter { kind($0) == 2 || kind($0) == 0x20 && !isUnknownDeveloper($0.identifier) }
        roots += unique.filter { item in
            guard [4, 8, 16].contains(kind(item)) else { return false }
            guard let parent = item.details["Parent Identifier"], !isUnknownDeveloper(parent) else { return true }
            return selected[parent] == nil
        }
        return roots.map { root in
            let members = unique.filter { candidate in
                var parent = candidate.details["Parent Identifier"]
                var visited: Set<String> = []
                while let identifier = parent, visited.insert(identifier).inserted {
                    if identifier == root.identifier { return true }
                    parent = selected[identifier]?.details["Parent Identifier"]
                }
                return false
            }
            var details = root.details
            details["Berth Group Kind"] = kind(root) == 2 ? "app" : kind(root) == 0x20 ? "developer" : "standalone"
            let permissionRecords = kind(root) == 0x20 ? members.filter { [4, 8, 16].contains(kind($0)) } : [root]
            let permissions = Set(permissionRecords.map(permission).filter { $0 != "unknown" })
            details["Berth Permission"] = permissions.count > 1 ? "partial" : permissions.first ?? "unknown"
            var name = localizedName(root) ?? root.name
            if kind(root) == 2 && !name.hasSuffix(".app") { name += ".app" }
            return BackgroundItem(id: "activity:" + root.identifier, name: name, identifier: root.identifier,
                source: .systemRecord, sourceURL: root.sourceURL, executable: root.executable, appURL: root.appURL,
                details: details, members: members)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func kind(_ item: BackgroundItem) -> Int {
        guard let text = item.details["Type"], let start = text.range(of: "0x"),
              let end = text[start.upperBound...].firstIndex(of: ")"),
              let value = Int(text[start.upperBound..<end], radix: 16) else { return 0 }
        return value & 0xffff
    }

    private static func isUnknownDeveloper(_ name: String) -> Bool { name.caseInsensitiveCompare("Unknown Developer") == .orderedSame }

    private static func permission(_ item: BackgroundItem) -> String {
        let raw = item.details["Disposition"] ?? ""
        let words = raw.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains("disallowed") { return "disallowed" }
        if words.contains("allowed") { return "allowed" }
        return "unknown"
    }
}
