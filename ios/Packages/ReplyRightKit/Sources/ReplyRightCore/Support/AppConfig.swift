import Foundation

/// Build-time configuration, read from the running bundle's Info.plist.
///
/// The values come from `ios/Config/*.xcconfig`, so the app, the keyboard and
/// the share extension always agree. Each target's Info.plist carries the same
/// `RRAppGroup`, `RRKeychainGroup` and `RRAPIBaseURL` keys.
public enum AppConfig {
    /// Language for explanations shown in the interface.
    public static let appLocale = "en"

    public static let fallbackAppGroup = "group.com.replyright.shared"
    public static let fallbackAPIBaseURL = "http://localhost:3000"

    // StoreKit product identifiers. These must match App Store Connect and
    // `ios/ReplyRight.storekit`. Prices are never hardcoded; they come from StoreKit.
    public static let monthlyProductID = "com.replyright.pro.monthly"
    public static let annualProductID = "com.replyright.pro.annual"
    public static let proProductIDs: [String] = [monthlyProductID, annualProductID]

    /// Reads a string from Info.plist, ignoring values left as unexpanded build settings.
    public static func infoValue(_ key: String, bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let clean = value.trimmed
        if clean.isEmpty || clean.contains("$(") { return nil }
        return clean
    }

    public static var appGroupIdentifier: String {
        infoValue("RRAppGroup") ?? fallbackAppGroup
    }

    /// Keychain access group shared by the app and its extensions, when signing provides one.
    public static var keychainGroup: String? {
        guard let value = infoValue("RRKeychainGroup") else { return nil }
        // Without a development team the prefix is empty and the group is not usable.
        return value.split(separator: ".").count >= 3 && !value.hasPrefix("com.") ? value : nil
    }

    public static var defaultAPIBaseURL: URL {
        if let value = infoValue("RRAPIBaseURL"), let url = URL(string: value), url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: fallbackAPIBaseURL)!
    }

    /// The backend to talk to: a development override if one is set and valid, otherwise the build's default.
    public static func apiBaseURL(override: String?) -> URL {
        if let override = override?.trimmed, !override.isEmpty,
           let url = URL(string: override), let scheme = url.scheme, url.host != nil,
           scheme == "https" || scheme == "http" {
            return url
        }
        return defaultAPIBaseURL
    }

    public static var appVersion: String {
        infoValue("CFBundleShortVersionString") ?? "1.0.0"
    }

    public static var buildNumber: String {
        infoValue("CFBundleVersion") ?? "1"
    }

    /// Identifies which part of the product made a request, for diagnostics. Carries no user data.
    public static func clientName(_ component: String) -> String {
        "ios-\(component)/\(appVersion)"
    }

    public static func privacyURL(base: URL) -> URL { base.appendingPathComponent("privacy") }
    public static func termsURL(base: URL) -> URL { base.appendingPathComponent("terms") }
    public static func supportURL(base: URL) -> URL { base.appendingPathComponent("support") }
}
