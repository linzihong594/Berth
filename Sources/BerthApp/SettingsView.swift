import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                Toggle("返回泊时刷新本地状态", isOn: $model.refreshOnActivation)
                Toggle("显示项目检查器", isOn: $model.inspectorVisible)
            } header: {
                Text("通用")
            } footer: {
                Text("本地刷新会更新 App 运行状态和暂存记录，不会弹出管理员认证。")
            }

            Section {
                LabeledContent("读取方式", value: "手动读取，短时复用认证")
                LabeledContent("上次读取") {
                    Text(model.systemReadDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚未读取")
                        .foregroundStyle(.secondary)
                }
                Button("前往后台活动列表") {
                    model.section = .systemRecords
                    model.search = ""
                    openWindow(id: "main")
                }
                Button("在系统设置中查看登录项") { model.openLoginSettings() }
                Button("结束读取会话") { Task { await model.endReadSession() } }
                    .disabled(model.isBusy || model.isDemo)
            } header: {
                Text("系统后台活动")
            } footer: {
                Text("新活动需在主窗口重新读取。短时间内复用同一读取会话的系统认证；是否提供 Touch ID、何时再次认证由 macOS 决定。退出泊、结束会话或空闲 5 分钟后释放读取进程。不保存密码。")
            }

            Section {
                Button("前往暂存与恢复") {
                    model.section = .archived
                    model.search = ""
                    openWindow(id: "main")
                }
                Button("在访达中查看用户备份") { model.revealArchives() }
            } header: {
                Text("暂存与恢复")
            } footer: {
                Text("备份保存在本机，恢复后仍会保留。仍有暂存项目时，请保留备份文件夹。")
            }

            Section {
                LabeledContent("泊 · Berth", value: AppVersion.display)
                Text("轻量管理后台活动，按需暂存与恢复。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 590)
        .navigationTitle("泊设置")
    }
}
