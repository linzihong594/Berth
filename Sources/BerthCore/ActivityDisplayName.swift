import Foundation

public enum ActivityDisplayName {
    public static func localized(_ item: BackgroundItem, languages: [String] = Locale.preferredLanguages) -> String? {
        guard let url = item.appURL, let bundle = Bundle(url: url),
              let language = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: languages).first,
              let requested = languages.first,
              Locale(identifier: language).language.languageCode == Locale(identifier: requested).language.languageCode,
              let file = bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: language),
              let data = try? Data(contentsOf: file),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
    }
}
