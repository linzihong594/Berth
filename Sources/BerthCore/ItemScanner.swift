import Foundation
import Darwin

public struct ItemScanner: Sendable {
    public let locations: [ScanLocation]
    public init(locations: [ScanLocation] = ScanLocation.standard) { self.locations = locations }

    public func scan() -> ScanResult {
        var items: [LaunchItem] = []
        var warnings: [String] = []
        for location in locations {
            do {
                let files: [URL]
                do {
                    files = try FileManager.default.contentsOfDirectory(at: location.url,
                        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
                for url in files where url.pathExtension == "plist" {
                    do { items.append(try readItem(at: url, scope: location.scope)) }
                    catch { warnings.append("\(url.path)：\(error.localizedDescription)") }
                }
            } catch { warnings.append("\(location.url.path)：\(error.localizedDescription)") }
        }
        items.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return ScanResult(items: items, warnings: warnings)
    }

    public func readItem(at url: URL, scope: ItemScope) throws -> LaunchItem {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw BerthError.message("不是普通配置文件；未读取符号链接。")
        }
        guard (values.fileSize ?? 0) <= 4 * 1024 * 1024 else {
            throw BerthError.message("配置超过 4 MB，未读取。")
        }
        let data = try Data(contentsOf: url)
        let dictionary = try plistDictionary(data)
        let label = dictionary["Label"] as! String
        let arguments = dictionary["ProgramArguments"] as? [String]
        let executable = dictionary["Program"] as? String ?? arguments?.first
        var exists: Bool?
        if let executable, executable.hasPrefix("/") {
            do { _ = try FileManager.default.attributesOfItem(atPath: executable); exists = true }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { exists = false }
            catch { exists = nil }
        }
        var restriction: String?
        if scope != .user { restriction = "此版本仅支持暂存当前用户的项目。" }
        else if label.hasPrefix("com.apple.") { restriction = "Apple 系统项目仅供查看。" }
        else {
            do { try FileSafety.checkRegularOwnedFile(url) }
            catch { restriction = error.localizedDescription }
        }
        return LaunchItem(fileURL: url, label: label, executable: executable, scope: scope,
                          fingerprint: fingerprint(data), executableExists: exists, parkingRestriction: restriction)
    }
}

enum FileSafety {
    static func checkRegularOwnedFile(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw BerthError.message("无法读取文件属性。") }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw BerthError.message("仅支持普通文件，不能操作符号链接。") }
        guard info.st_uid == getuid() else { throw BerthError.message("文件不属于当前用户。") }
        guard info.st_nlink == 1 else { throw BerthError.message("存在硬链接，暂不支持操作。") }
        guard info.st_mode & 0o022 == 0 else { throw BerthError.message("文件允许其他用户写入，请先核对权限。") }
        guard info.st_mode & 0o7000 == 0 else { throw BerthError.message("文件具有特殊权限，暂不支持操作。") }
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
