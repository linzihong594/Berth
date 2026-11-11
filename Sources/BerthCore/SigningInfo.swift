import Foundation
import Security

public struct SigningInfo: Sendable, Equatable {
    public let developer: String
    public let teamID: String
    public init(developer: String, teamID: String) { self.developer = developer; self.teamID = teamID }

    public static func read(executable: String?) -> SigningInfo? {
        guard let executable, executable.hasPrefix("/") else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: executable) as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let first = certificates.first, let subject = SecCertificateCopySubjectSummary(first) as String? else { return nil }
        let prefix = "Developer ID Application: "
        let developer = subject.hasPrefix(prefix) ? String(subject.dropFirst(prefix.count)) : subject
        let suffix = " (\(team))"
        return SigningInfo(developer: developer.hasSuffix(suffix) ? String(developer.dropLast(suffix.count)) : developer, teamID: team)
    }
}

public enum BackgroundServiceMatch {
    public static func candidates(for record: BackgroundItem, items: [LaunchItem], signatures: [String: SigningInfo]) -> [LaunchItem] {
        if let members = record.members {
            // A visible developer group can contain a user agent even when the same
            // signer owns a separate root service. Parent/child evidence takes precedence.
            let identifiers = Set(members.map { normalizedLabel($0.identifier) })
            let paths = Set(members.compactMap { $0.sourceURL?.path })
            if record.details["Berth Group Kind"] == "standalone" {
                return items.filter { $0.label == normalizedLabel(record.identifier) || $0.fileURL.path == record.sourceURL?.path }
            }
            return items.filter { identifiers.contains($0.label) || paths.contains($0.fileURL.path) }
        }
        if let path = record.sourceURL?.path {
            let exact = items.filter { $0.fileURL.path == path }
            if !exact.isEmpty { return exact }
        }
        var label = record.identifier
        if let first = label.firstIndex(of: "."), Int(label[..<first]) != nil { label = String(label[label.index(after: first)...]) }
        let exact = items.filter { $0.label == label }
        if !exact.isEmpty { return exact }
        guard record.appURL == nil else { return [] }
        // Developer rows can represent helpers rather than the main app.
        // Require matching signature evidence; never infer a service from a similar name.
        return items.filter { item in
            guard item.scope == .daemon, let signature = signatures[item.label] else { return false }
            if let team = record.details["Team Identifier"], team != "(null)" { return signature.teamID == team }
            return signature.developer.caseInsensitiveCompare(record.name) == .orderedSame
        }
    }

    private static func normalizedLabel(_ identifier: String) -> String {
        guard let dot = identifier.firstIndex(of: "."), Int(identifier[..<dot]) != nil else { return identifier }
        return String(identifier[identifier.index(after: dot)...])
    }
}
