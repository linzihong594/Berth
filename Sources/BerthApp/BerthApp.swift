import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BerthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = LibraryModel(isDemo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        Window("泊", id: "main") {
            LibraryView(model: model)
                .frame(minWidth: 930, minHeight: 580)
        }
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("刷新项目") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
                Button("在系统设置中查看登录项") { model.openLoginSettings() }
            }
            CommandGroup(replacing: .help) {
                Button(model.isDemo ? "退出示例模式" : "查看示例数据") {
                    Task { await model.toggleDemo() }
                }.disabled(model.isBusy)
            }
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
