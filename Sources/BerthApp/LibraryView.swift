import SwiftUI
import AppKit
import BerthCore

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Section("资料库") {
                    ForEach([LibrarySection.systemRecords]) { section in
                        sidebarRow(section)
                    }
                }
                Section("恢复") { sidebarRow(.archived) }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf").foregroundStyle(.secondary)
                    Text("泊").fontWeight(.medium)
                    Text(AppVersion.display).foregroundStyle(.tertiary)
                    Spacer()
                }
                .font(.callout)
                .padding(16)
            }
        } detail: {
            VStack(spacing: 0) {
                systemCoverage
                Divider()
                itemTable
                Divider()
                statusBar
            }
            .navigationTitle(model.section?.title ?? "后台 App 活动")
            .navigationSubtitle(model.systemReadDate == nil && model.section != .archived ? "尚未读取" : "\(model.entries.count) 条记录\(model.isDemo ? " · 示例" : "")")
            .searchable(text: $model.search, prompt: "搜索名称或路径")
            .toolbar {
                ToolbarItemGroup {
                    if model.section == .archived {
                        Button("同步系统暂存区…") { Task { await model.syncSystemArchives() } }
                            .disabled(model.isBusy || model.isDemo)
                    }
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("刷新本地状态（⌘R）；新增后台活动请重新读取系统列表")
                        .disabled(model.isBusy)
                    Button { openSettings() } label: { Image(systemName: "gearshape") }
                        .help("泊设置（⌘,）")
                    Button { model.inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                        .help("显示或隐藏检查器")
                }
            }
        }
        .inspector(isPresented: $model.inspectorVisible) {
            ItemInspector(model: model, entry: model.selectedEntry)
                .inspectorColumnWidth(min: 270, ideal: 300, max: 360)
        }
        .onChange(of: model.section) { _, _ in model.selectedID = nil; model.search = "" }
        .task { await model.refresh() }
        .task(id: model.selectedID) { await model.loadSelectedSignatures() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.refreshOnActivation else { return }
            Task { await model.refresh() }
        }
        .confirmationDialog("读取系统后台记录？", isPresented: $model.showSystemReadConfirmation, titleVisibility: .visible) {
            Button("读取系统列表") { Task { await model.readSystemRecords() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只读获取系统列表，不更改后台开关。macOS 在需要时要求认证；短时间内可复用同一读取会话的认证，是否提供 Touch ID 由系统决定。不保存密码，不自动重试。")
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $model.showDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("读取诊断").font(.title2).fontWeight(.semibold)
                Text("以下项目未能完整读取，列表可能不完整。").foregroundStyle(.secondary)
                ScrollView {
                    Text(model.warnings.joined(separator: "\n\n"))
                        .font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("完成") { model.showDiagnostics = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(24).frame(width: 580, height: 360)
        }
    }

    private func sidebarRow(_ section: LibrarySection) -> some View {
        Label {
            HStack {
                Text(section.title)
                Spacer()
                Text(section == .systemRecords && model.systemReadDate == nil ? "未读取" : "\(model.count(section))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        } icon: { Image(systemName: section.symbol) }
        .tag(section)
    }

    private var itemTable: some View {
        Table(model.entries, selection: $model.selectedID) {
            TableColumn("项目") { entry in
                HStack(spacing: 10) {
                    ItemIcon(entry: entry, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title).lineLimit(1)
                        if entry.title != entry.label {
                            Text(entry.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else if case .item(let item) = entry {
                            Text(item.executable ?? "未指定执行程序").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .padding(.vertical, 7)
            }.width(min: 200, ideal: 300)
            TableColumn("状态") { entry in
                Text(model.state(entry)).foregroundStyle(.secondary).font(.callout)
            }.width(min: 95, ideal: 105, max: 125)
            TableColumn("后台许可") { entry in
                Text(model.permission(entry)).foregroundStyle(.secondary).font(.callout)
            }.width(min: 80, ideal: 95, max: 125)
        }
        .overlay {
            if model.entries.isEmpty && !model.isBusy {
                ContentUnavailableView {
                    Label(emptyTitle,
                          systemImage: model.section == .archived ? "archivebox" : "magnifyingglass")
                } description: {
                    Text(emptyDescription)
                }
            }
        }
    }

    private var emptyTitle: String {
        if !model.search.isEmpty { return "没有匹配的项目" }
        if model.section == .archived { return "还没有暂存项目" }
        if model.section == .systemRecords && model.systemReadDate == nil { return "尚未读取系统后台记录" }
        return "没有发现此类项目"
    }

    private var emptyDescription: String {
        if !model.search.isEmpty { return "试试其他名称、标识符或路径。" }
        if model.section == .archived { return "暂存后的项目会保存在这里，随时可以恢复。" }
        if model.section == .systemRecords && model.systemReadDate == nil { return "点按上方读取系统列表，macOS 会要求管理员认证。" }
        return "检测结果取决于已读取的来源；不代表系统没有其他后台活动。"
    }

    private var systemCoverage: some View {
        HStack(spacing: 12) {
            Image(systemName: model.systemReadDate == nil ? "info.circle" : "list.bullet.rectangle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.systemReadInProgress ? "等待系统认证或读取结果…" : model.systemReadDate == nil ? "系统后台列表尚未读取" : "已读取系统后台记录")
                    .font(.callout)
                    Text(model.systemReadDate.map { "系统快照 " + $0.formatted(date: .abbreviated, time: .shortened) + " · 已排除泊中暂存的项目，新增活动请重新读取" }
                     ?? "这里只展示系统后台活动；不会混入其他启动配置或 App 组件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(model.systemReadDate == nil ? "读取系统列表…" : "重新读取…") { model.showSystemReadConfirmation = true }
                .controlSize(.small).disabled(model.isBusy || model.isDemo)
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy { ProgressView().controlSize(.mini) }
            Text(model.systemReadInProgress ? "等待认证，可在系统窗口中取消；60 秒后超时" : model.isBusy ? "正在处理…" : model.statusMessage).lineLimit(1)
            Spacer()
            if !model.warnings.isEmpty {
                Button { model.showDiagnostics = true } label: {
                    Label("\(model.warnings.count) 条读取提示", systemImage: "exclamationmark.circle")
                }.buttonStyle(.borderless)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

struct ItemIcon: View {
    let entry: LibraryEntry
    let size: CGFloat
    var body: some View {
        Group {
            if case .background(let item) = entry, let symbol = item.details["Berth Demo Symbol"] {
                Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(.teal).padding(size * 0.12)
            } else if let url = entry.bundleURL, FileManager.default.fileExists(atPath: url.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: entry.scopeTitle == "暂存区" ? "archivebox" : "app.dashed")
                    .resizable().scaledToFit().foregroundStyle(.secondary).padding(size * 0.12)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
