import Foundation

public struct ApplicationScanner: Sendable {
    public let directories: [URL]
    public init(directories: [URL] = [URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        URL(fileURLWithPath: "/System/Applications")]) {
        self.directories = directories
    }

    public func scan() -> BackgroundInventory {
        var items: [BackgroundItem] = []
        var warnings: [String] = []
        var applications: Set<URL> = []
        let fm = FileManager.default
        // Two folder levels cover Applications and Utilities without walking app resources.
        func collect(_ directory: URL, depth: Int) {
            do {
                for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          values.isSymbolicLink != true, values.isDirectory == true else { continue }
                    if url.pathExtension == "app" { applications.insert(url.standardizedFileURL) }
                    else if depth > 0 { collect(url, depth: depth - 1) }
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
            catch { warnings.append("\(directory.path)：\(error.localizedDescription)") }
        }
        for directory in directories { collect(directory, depth: 1) }

        for app in applications.sorted(by: { $0.path < $1.path }) {
            do {
                let info = try infoDictionary(app)
                let identifier = info["CFBundleIdentifier"] as? String ?? app.lastPathComponent
                let name = appName(app, info: info)
                if flag(info["LSUIElement"]) || flag(info["LSBackgroundOnly"]) {
                    items.append(BackgroundItem(id: "accessory:" + app.path, name: name, identifier: identifier,
                        source: .accessoryApp, sourceURL: app, executable: appExecutable(app, info: info), appURL: app))
                }
                let library = app.appendingPathComponent("Contents/Library")
                for (folder, source) in [("LaunchAgents", BackgroundSource.bundledAgent), ("LaunchDaemons", .bundledDaemon)] {
                    for file in children(library.appendingPathComponent(folder), warnings: &warnings) where file.pathExtension == "plist" {
                        do {
                            let data = try readSmallFile(file)
                            let dict = try plistDictionary(data)
                            let command = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
                            let executable: String?
                            if let command { executable = command }
                            else if let relative = dict["BundleProgram"] as? String, !relative.hasPrefix("/") {
                                let candidate = app.appendingPathComponent(relative).standardizedFileURL
                                executable = candidate.path.hasPrefix(app.path + "/") ? candidate.path : nil
                            } else { executable = nil }
                            items.append(BackgroundItem(id: "bundled:" + file.path, name: name,
                                identifier: dict["Label"] as! String, source: source, sourceURL: file,
                                executable: executable, appURL: app))
                        } catch { warnings.append("\(file.path)：\(error.localizedDescription)") }
                    }
                }
                for helper in children(library.appendingPathComponent("LoginItems"), warnings: &warnings) where helper.pathExtension == "app" {
                    do {
                        let helperInfo = try infoDictionary(helper)
                        items.append(BackgroundItem(id: "login-helper:" + helper.path, name: name,
                            identifier: helperInfo["CFBundleIdentifier"] as? String ?? helper.lastPathComponent,
                            source: .loginHelper, sourceURL: helper, executable: appExecutable(helper, info: helperInfo), appURL: app))
                    } catch { warnings.append("\(helper.path)：\(error.localizedDescription)") }
                }
            } catch { warnings.append("\(app.path)：\(error.localizedDescription)") }
        }
        items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return BackgroundInventory(items: items, warnings: warnings, applicationsChecked: applications.count)
    }

    private func children(_ directory: URL, warnings: inout [String]) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        catch { warnings.append("\(directory.path)：\(error.localizedDescription)"); return [] }
    }

    private func readSmallFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 4 * 1024 * 1024 else {
            throw BerthError.message("配置不是可读取的普通文件，或超过大小限制。")
        }
        return try Data(contentsOf: url)
    }

    private func infoDictionary(_ app: URL) throws -> [String: Any] {
        guard let info = try PropertyListSerialization.propertyList(from: readSmallFile(app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any] else {
            throw BerthError.message("App 信息无法识别。")
        }
        return info
    }

    private func appName(_ app: URL, info: [String: Any]) -> String {
        (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? app.deletingPathExtension().lastPathComponent
    }

    private func appExecutable(_ app: URL, info: [String: Any]) -> String? {
        guard let name = info["CFBundleExecutable"] as? String, !name.contains("/"), !name.isEmpty else { return nil }
        return app.appendingPathComponent("Contents/MacOS").appendingPathComponent(name).path
    }

    private func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return false
    }
}
