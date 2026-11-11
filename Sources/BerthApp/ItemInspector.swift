import SwiftUI
import AppKit
import BerthCore

struct ItemInspector: View {
    @ObservedObject var model: LibraryModel
    let entry: LibraryEntry?

    var body: some View {
        if let entry {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            ItemIcon(entry: entry, size: 48)
                            Text(entry.title).font(.title3).fontWeight(.semibold).textSelection(.enabled)
                            Label(model.state(entry), systemImage: "circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        field("标识符", entry.label)
                        field("执行程序", entry.executable ?? "未能确定")
                        switch entry {
                        case .item(let item):
                            field("配置位置", item.fileURL.path)
                            field("影响范围", item.scope.title)
                            Text("这里只表示这份启动配置的载入情况。App 可能通过其他方式运行，后台许可请对照系统记录与系统设置。")
                                .font(.caption).foregroundStyle(.secondary)
                            if item.executableExists == false {
                                Label("未找到执行程序。请确认应用是否已卸载，或磁盘是否已连接。", systemImage: "questionmark.circle")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Button("在访达中显示", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                            }.controlSize(.small)
                        case .archive(let record), .systemArchive(let record):
                            field("暂存时间", record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            field("恢复方式", record.wasLoaded ? "还原配置并重新载入" : "还原配置，保持未载入")
                            if let lastError = record.lastError { field("上次操作提示", lastError) }
                            if case .archive = entry {
                                Button("查看备份", systemImage: "folder") {
                                    NSWorkspace.shared.open(model.archiveRoot.appendingPathComponent(record.id.uuidString))
                                }.controlSize(.small)
                            } else { field("备份保护", "系统备份由管理员拥有，恢复时会再次核对原始记录。") }
                        case .background(let item):
                            field("发现方式", item.source.title)
                            if let url = item.sourceURL { field("记录位置", url.path) }
                            if let app = item.appURL { field("所属 App", app.path) }
                            ForEach(model.serviceCandidates(item)) { service in
                                field("对应后台服务", service.label)
                                field("服务配置", service.fileURL.path)
                                if let signature = model.signatures[service.label] {
                                    field("代码签名显示名", signature.developer + " (" + signature.teamID + ")")
                                }
                            }
                            ForEach(["Developer Name", "Team Identifier", "Type", "Disposition", "UID"], id: \.self) { key in
                                if let value = item.details[key], value != "(null)" { field(detailTitle(key), value) }
                            }
                            Text(item.source == .systemRecord ? "系统记录与 App 实时运行、后台许可是不同信息。开关请以系统设置为准。" : "这是 App 包含的助手或常驻声明，尚未确认它已注册为登录项。不会修改 App 包内文件。")
                                .font(.caption).foregroundStyle(.secondary)
                            if let url = item.sourceURL {
                                Button("在访达中显示", systemImage: "folder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }.controlSize(.small)
                            }
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                actions(entry).padding(20)
            }
            .confirmationDialog(confirmationTitle(entry), isPresented: $model.showConfirmation, titleVisibility: .visible) {
                switch entry {
                case .item(let item):
                    Button("暂存项目") { Task { await model.park(item) } }
                case .archive(let record):
                    Button("恢复项目") { Task { await model.restore(record) } }
                case .systemArchive(let record):
                    Button("恢复系统服务") { Task { await model.restoreSystem(record) } }
                case .background(let record):
                    if let service = model.parkableService(record) {
                        Button("暂存并停用服务") { Task { await model.park(service) } }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                switch entry {
                case .item:
                    Text("将停止此启动代理，并把配置移到暂存区；原应用会保留。系统设置中的记录可能稍后更新，应用也可能重新创建配置。")
                case .archive(let record), .systemArchive(let record):
                    Text(record.wasLoaded ? "将还原原始配置并重新载入。遇到不同内容的同名文件时会停止恢复。" : "将还原原始配置，并保持原来的未载入状态。")
                case .background(let record):
                    if let service = model.parkableService(record) {
                        Text("将停止服务 \(service.label)，备份并移出启动配置。相关 App 的后台或 TUN 功能可能暂停，可在暂存区恢复。系统设置可能稍后清理旧记录，不能保证立即消失。")
                    }
                }
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "sidebar.right").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text("选择一个项目").font(.headline).foregroundStyle(.secondary)
                Text("查看来源、配置位置\n以及可用操作")
                    .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func confirmationTitle(_ entry: LibraryEntry) -> String {
        switch entry {
        case .item: "暂存“\(entry.title)”？"
        case .archive, .systemArchive: "恢复“\(entry.title)”？"
        case .background: "暂存并停用“\(entry.title)”的后台服务？"
        }
    }

    private func actions(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch entry {
            case .item(let item):
                if let restriction = item.parkingRestriction {
                    Text(restriction).font(.callout).foregroundStyle(.secondary)
                    Button("在系统设置中查看", action: model.openLoginSettings)
                } else {
                    Button { model.showConfirmation = true } label: { Label("暂存项目…", systemImage: "archivebox") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || model.isDemo)
                    Text(model.isDemo ? "示例模式不执行操作。" : "先备份，暂存后可恢复。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .archive, .systemArchive:
                Button { model.showConfirmation = true } label: { Label("恢复项目…", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy || model.isDemo)
                Text("还原原始配置，保留恢复记录。").font(.caption).foregroundStyle(.secondary)
            case .background(let record):
                if model.archivedService(record) != nil {
                    Button("在暂存区恢复", systemImage: "archivebox") { model.section = .archived; model.selectedID = nil }
                } else if model.parkableService(record) != nil {
                    Button { model.showConfirmation = true } label: { Label("暂存并停用服务…", systemImage: "archivebox") }
                        .buttonStyle(.borderedProminent).disabled(model.isBusy || model.isDemo)
                    Text("影响对应后台服务；备份后可恢复。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(model.serviceCandidates(record).count > 1 ? "对应多个服务，需要进一步核对。" : "尚无可安全暂存的服务配置。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("在系统设置中查看", action: model.openLoginSettings)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailTitle(_ key: String) -> String {
        switch key {
        case "Developer Name": "开发者"
        case "Team Identifier": "开发团队 ID"
        case "Type": "系统记录类型"
        case "Disposition": "系统原始标记"
        case "UID": "记录所属用户 ID"
        default: key
        }
    }
}
