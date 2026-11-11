import SwiftUI
import AppKit
import ServiceManagement
import BerthCore

enum LibrarySection: String, CaseIterable, Identifiable {
    case systemRecords, archived
    var id: Self { self }
    var title: String { self == .systemRecords ? "后台 App 活动" : "已暂存" }
    var symbol: String { self == .systemRecords ? "list.bullet.rectangle" : "archivebox" }
}

enum LibraryEntry: Identifiable {
    case item(LaunchItem)
    case archive(ArchiveRecord)
    case systemArchive(ArchiveRecord)
    case background(BackgroundItem)
    var id: String {
        switch self {
        case .item(let item): item.id
        case .archive(let record): record.id.uuidString
        case .systemArchive(let record): "system:" + record.id.uuidString
        case .background(let item): item.id
        }
    }
    var label: String {
        switch self {
        case .item(let item): item.label
        case .archive(let record), .systemArchive(let record): record.label
        case .background(let item): item.identifier
        }
    }
    var executable: String? {
        switch self {
        case .item(let item): item.executable
        case .archive(let record), .systemArchive(let record): record.executable
        case .background(let item): item.executable
        }
    }
    var bundleURL: URL? {
        switch self {
        case .item(let item): item.appBundleURL
        case .archive(let record), .systemArchive(let record):
            LaunchItem(fileURL: URL(fileURLWithPath: "/"), label: record.label,
                executable: record.executable, scope: .user, fingerprint: "", executableExists: nil,
                parkingRestriction: nil).appBundleURL
        case .background(let item): item.appURL
        }
    }
    var title: String {
        if case .background(let item) = self { return item.name }
        return bundleURL?.deletingPathExtension().lastPathComponent ?? label
    }
    var scopeTitle: String {
        switch self {
        case .item(let item): item.scope.title
        case .archive: "暂存区"
        case .systemArchive: "系统服务暂存"
        case .background(let item): item.source.title
        }
    }
}

struct LibrarySnapshot: Sendable {
    let scan: ScanResult
    let archives: ArchiveListing
    let jobs: [String: Int?]?
    let systemSnapshot: SystemSnapshot?
    let warnings: [String]
    let systemArchives: [ArchiveRecord]
}

actor LibraryWorker {
    private let controller = LaunchController()
    private let parking = ParkingStore()
    private let cache = SystemSnapshotCache()
    private let systemClient = SystemServiceClient()
    private let systemReader = SystemBackgroundReader()

    func snapshot() -> LibrarySnapshot {
        let scan = ItemScanner().scan()
        let archives = parking.list()
        var warnings = scan.warnings + archives.warnings
        let jobs: [String: Int?]?
        do { jobs = try controller.loadedJobs() }
        catch { jobs = nil; warnings.append(error.localizedDescription) }
        let cached: SystemSnapshot?
        do { cached = try cache.load() }
        catch { cached = nil; warnings.append("系统快照：" + error.localizedDescription) }
        let systemArchives: [ArchiveRecord]
        do { systemArchives = try systemClient.cachedRecords() }
        catch { systemArchives = []; warnings.append("系统暂存记录：" + error.localizedDescription) }
        return LibrarySnapshot(scan: scan, archives: archives, jobs: jobs, systemSnapshot: cached, warnings: warnings,
                               systemArchives: systemArchives)
    }
    func signatures(for items: [LaunchItem]) -> [String: SigningInfo] {
        autoreleasepool {
            var result: [String: SigningInfo] = [:]
            for item in items { result[item.label] = SigningInfo.read(executable: item.executable) }
            return result
        }
    }
    func park(_ item: LaunchItem) throws {
        if item.scope == .daemon {
            let response = try systemClient.perform(["park", item.fileURL.lastPathComponent, item.label, item.fingerprint])
            if let error = response.error { throw BerthError.message(error) }
        } else { try parking.park(item) }
    }
    func restore(_ id: UUID) throws { try parking.restore(id) }
    func restoreSystem(_ id: UUID) throws {
        let result = try systemClient.perform(["restore", id.uuidString])
        if let error = result.error { throw BerthError.message(error) }
    }
    func syncSystemArchives() throws {
        let result = try systemClient.perform(["list"])
        if let error = result.error { throw BerthError.message(error) }
    }
    func readSystemRecords() throws -> (SystemSnapshot, [String]) {
        let result = try systemReader.read()
        let snapshot = SystemSnapshot(items: result.items)
        var warnings = result.warnings
        do { try cache.save(snapshot) }
        catch { warnings.append("系统快照未保存：" + error.localizedDescription) }
        return (snapshot, warnings)
    }
    func endReadSession() { systemReader.endSession() }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var inspectorVisible: Bool {
        didSet { UserDefaults.standard.set(inspectorVisible, forKey: "inspectorVisible") }
    }
    @Published var refreshOnActivation: Bool {
        didSet { UserDefaults.standard.set(refreshOnActivation, forKey: "refreshOnActivation") }
    }
    @Published var showDiagnostics = false
    @Published var showConfirmation = false
    @Published var section: LibrarySection? = .systemRecords
    @Published var selectedID: String?
    @Published var search = ""
    @Published var isBusy = false
    @Published var items: [LaunchItem] = []
    @Published private(set) var activityRows: [BackgroundItem] = []
    @Published var systemReadDate: Date?
    @Published var systemReadInProgress = false
    @Published var showSystemReadConfirmation = false
    @Published var runningAppPaths: Set<String> = []
    @Published var archives: [ArchiveRecord] = []
    @Published var systemArchives: [ArchiveRecord] = []
    @Published var signatures: [String: SigningInfo] = [:]
    @Published var warnings: [String] = []
    @Published var jobs: [String: Int?]?
    @Published var errorMessage: String?
    @Published var statusMessage = "正在读取启动项目…"
    @Published private(set) var isDemo: Bool
    private let worker = LibraryWorker()
    private var systemWarnings: [String] = []
    private func replaceSystemItems(_ items: [BackgroundItem]) {
        // Projection and localized InfoPlist reads belong to snapshot updates,
        // never to SwiftUI's repeated entries/count/body evaluations.
        activityRows = autoreleasepool {
            BackgroundActivityProjection.rows(from: items) { ActivityDisplayName.localized($0) }
        }
    }

    init(isDemo: Bool) {
        self.isDemo = isDemo
        let defaults = UserDefaults.standard
        inspectorVisible = defaults.object(forKey: "inspectorVisible") as? Bool ?? true
        refreshOnActivation = defaults.object(forKey: "refreshOnActivation") as? Bool ?? true
    }

    var activeArchives: [ArchiveRecord] { archives.filter { $0.phase != .restored } }
    private var visibleActivityRows: [BackgroundItem] {
        BackgroundActivityProjection.visibleRows(activityRows, archives: archives + systemArchives,
            presentServiceLabels: Set(items.map(\.label)))
    }
    var entries: [LibraryEntry] {
        let values: [LibraryEntry] = section == .archived
            ? activeArchives.map(LibraryEntry.archive) + systemArchives.filter { $0.phase != .restored }.map(LibraryEntry.systemArchive)
            : visibleActivityRows.map(LibraryEntry.background)
        guard !search.isEmpty else { return values }
        return values.filter { [$0.title, $0.label, $0.executable ?? ""].contains { $0.localizedStandardContains(search) } }
    }
    var selectedEntry: LibraryEntry? { entries.first { $0.id == selectedID } }
    var archiveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Berth/Archives")
    }

    func revealArchives() {
        guard FileManager.default.fileExists(atPath: archiveRoot.path) else {
            NSWorkspace.shared.open(archiveRoot.deletingLastPathComponent())
            return
        }
        NSWorkspace.shared.open(archiveRoot)
    }

    func count(_ section: LibrarySection) -> Int {
        section == .archived ? activeArchives.count + systemArchives.filter { $0.phase != .restored }.count : visibleActivityRows.count
    }

    func state(_ entry: LibraryEntry) -> String {
        switch entry {
        case .archive(let record), .systemArchive(let record): return record.phase.title
        case .item(let item):
            guard item.scope != .daemon, let jobs else { return "配置状态未知" }
            guard let pid = jobs[item.label] else { return "配置未载入" }
            return pid == nil ? "配置已载入" : "配置运行中"
        case .background(let item):
            if let record = archivedService(item) {
                return record.phase == .parked && items.contains(where: { $0.label == record.label }) ? "配置已重新出现" : record.phase.title
            }
            if let app = item.source == .systemRecord ? item.appURL : (item.source == .accessoryApp ? item.appURL : nil),
               runningAppPaths.contains(app.path) { return "App 在运行" }
            return item.source == .systemRecord ? "系统已记录" : "待核对注册"
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if isDemo {
            let examples = [
                ("Atlas Backup.app", "com.example.atlas", "externaldrive", "allowed"),
                ("Canvas Helper.app", "com.example.canvas", "paintpalette", "disallowed"),
                ("Harbor Notes.app", "com.example.harbor", "note.text", "allowed"),
                ("Lumen Updater", "com.example.lumen", "arrow.triangle.2.circlepath", "disallowed"),
                ("Nimbus Sync.app", "com.example.nimbus", "cloud", "allowed"),
                ("Northstar.app", "com.example.northstar", "safari", "allowed")
            ]
            activityRows = examples.map { name, identifier, symbol, permission in
                BackgroundItem(id: "demo:" + identifier, name: name, identifier: identifier,
                    source: .systemRecord, sourceURL: nil, executable: nil, appURL: nil,
                    details: ["Berth Demo Symbol": symbol, "Berth Permission": permission,
                              "Type": "app (0x2)", "Developer Name": "Example Developer"])
            }
            systemReadDate = Date()
            jobs = [:]
            warnings = []
            statusMessage = "示例数据 · 操作已停用"
        } else {
            apply(await worker.snapshot())
            await loadSelectedSignatures()
        }
    }

    func toggleDemo() async {
        guard !isBusy else { return }
        isDemo.toggle()
        selectedID = nil
        search = ""
        section = .systemRecords
        items = []; archives = []; systemArchives = []; signatures = [:]
        activityRows = []; systemReadDate = nil; systemWarnings = []
        await refresh()
    }

    func park(_ item: LaunchItem) async {
        guard !isBusy, !isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await worker.park(item)
            selectedID = nil
            statusMessage = "已暂存，可在暂存区恢复"
        } catch { errorMessage = error.localizedDescription }
        apply(await worker.snapshot(), preserveMessage: true)
    }

    func restore(_ record: ArchiveRecord) async {
        guard !isBusy, !isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await worker.restore(record.id)
            selectedID = nil
            statusMessage = "已恢复原配置"
        } catch { errorMessage = error.localizedDescription }
        apply(await worker.snapshot(), preserveMessage: true)
    }

    func restoreSystem(_ record: ArchiveRecord) async {
        guard !isBusy, !isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await worker.restoreSystem(record.id); selectedID = nil; statusMessage = "已恢复系统服务配置" }
        catch { errorMessage = error.localizedDescription }
        apply(await worker.snapshot(), preserveMessage: true)
    }

    func syncSystemArchives() async {
        guard !isBusy, !isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await worker.syncSystemArchives() }
        catch { errorMessage = error.localizedDescription }
        apply(await worker.snapshot())
    }

    func serviceCandidates(_ item: BackgroundItem) -> [LaunchItem] {
        BackgroundServiceMatch.candidates(for: item, items: items, signatures: signatures)
    }

    func loadSelectedSignatures() async {
        guard case .background(let item) = selectedEntry else {
            signatures = [:]
            return
        }
        let selection = selectedID
        let matches = serviceCandidates(item)
        let result = await worker.signatures(for: matches)
        guard !Task.isCancelled, selectedID == selection else { return }
        signatures = result
    }

    func permission(_ entry: LibraryEntry) -> String {
        guard case .background(let item) = entry else { return "—" }
        switch item.details["Berth Permission"] {
        case "allowed": return "允许"
        case "disallowed": return "已关闭"
        case "partial": return "部分允许"
        default: return "未确认"
        }
    }

    func parkableService(_ item: BackgroundItem) -> LaunchItem? {
        guard archivedService(item) == nil else { return nil }
        let matches = serviceCandidates(item)
        guard matches.count == 1, let match = matches.first, !match.label.hasPrefix("com.apple.") else { return nil }
        if match.scope == .daemon { return match }
        return match.scope == .user && match.parkingRestriction == nil ? match : nil
    }

    func archivedService(_ item: BackgroundItem) -> ArchiveRecord? {
        let labels = BackgroundActivityProjection.serviceLabels(item)
        return (activeArchives + systemArchives.filter { $0.phase != .restored }).first { labels.contains($0.label) }
    }

    func readSystemRecords() async {
        guard !isBusy, !isDemo else { return }
        isBusy = true
        systemReadInProgress = true
        defer { isBusy = false; systemReadInProgress = false }
        do {
            let (snapshot, readWarnings) = try await worker.readSystemRecords()
            replaceSystemItems(snapshot.items)
            systemWarnings = readWarnings
            systemReadDate = snapshot.readAt
            section = .systemRecords
            selectedID = nil
            apply(await worker.snapshot(), preserveMessage: true)
            statusMessage = "已读取系统后台记录"
        } catch { errorMessage = error.localizedDescription }
    }

    func endReadSession() async {
        guard !isBusy else { return }
        await worker.endReadSession()
        statusMessage = "已结束读取会话，下次读取由系统重新确认认证"
    }

    private func apply(_ snapshot: LibrarySnapshot, preserveMessage: Bool = false) {
        items = snapshot.scan.items
        archives = snapshot.archives.records
        systemArchives = snapshot.systemArchives
        jobs = snapshot.jobs
        runningAppPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
        warnings = snapshot.warnings + systemWarnings
        if systemReadDate == nil, let cached = snapshot.systemSnapshot {
            replaceSystemItems(cached.items)
            systemReadDate = cached.readAt
        }
        if !preserveMessage { statusMessage = systemReadDate == nil ? "尚未读取系统后台活动" : "当前显示上次读取的系统快照" }
    }

    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
