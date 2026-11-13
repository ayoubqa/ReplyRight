import Foundation

/// Which ReplyRight server a build talks to.
///
/// Each environment has its own address, set in `ios/Config/Shared.xcconfig`
/// and carried into every target's Info.plist, so the app, the keyboard and
/// the share sheet always agree.
public enum BackendEnvironment: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The server running on the developer's own Mac.
    case development
    /// A deployed server used for testing before release.
    case staging
    /// The server real users talk to.
    case production

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }

    public var blurb: String {
        switch self {
        case .development: return "The server running on your Mac"
        case .staging: return "A deployed server for testing"
        case .production: return "The server real users talk to"
        }
    }

    /// The Info.plist key that holds this environment's address.
    var infoKey: String { "RRAPIBaseURL\(title)" }
}

/// The server a request will go to, and why that one was picked.
public struct BackendTarget: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// The environment this build was made for.
        case build
        /// An environment picked in the app (development builds only).
        case chosen
        /// An address typed in the app (development builds only).
        case custom
    }

    public var url: URL
    /// Nil when the address was typed by hand.
    public var environment: BackendEnvironment?
    public var source: Source

    public init(url: URL, environment: BackendEnvironment?, source: Source) {
        self.url = url
        self.environment = environment
        self.source = source
    }

    public var label: String {
        environment?.title ?? "Custom address"
    }

    /// The address without a path, for example "http://localhost:3000".
    public var displayAddress: String {
        var text = "\(url.scheme ?? "https")://\(url.host ?? "")"
        if let port = url.port {
            text += ":\(port)"
        }
        return text
    }

    /// True when the address points at this machine or the local network.
    public var isLocal: Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
            return true
        }
        return host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.16.")
    }

    /// True for an address that only works on the machine running the simulator.
    public var isLoopback: Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

/// Build-time configuration, read from the running bundle's Info.plist.
///
/// The values come from `ios/Config/*.xcconfig`, so the app, the keyboard and
/// the share extension always agree. Each target's Info.plist carries the same
/// `RRAppGroup`, `RRKeychainGroup` and `RRAPI…` keys.
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

    // MARK: Backend address

    /// Accepts only complete http or https addresses.
    public static func parseURL(_ text: String?) -> URL? {
        guard let clean = text?.trimmed, !clean.isEmpty,
              let url = URL(string: clean), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty,
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    /// The environment this build was made for (`RR_API_ENVIRONMENT` in the xcconfig files).
    public static var buildEnvironment: BackendEnvironment {
        infoValue("RRAPIEnvironment").flatMap { BackendEnvironment(rawValue: $0.lowercased()) } ?? .development
    }

    /// Whether the app may be pointed at another server at runtime.
    /// On in Debug builds, off in Release builds (`RR_ALLOW_ENVIRONMENT_SWITCH`).
    public static var allowsEnvironmentSwitching: Bool {
        guard let value = infoValue("RRAllowsEnvironmentSwitching")?.uppercased() else { return false }
        return value == "YES" || value == "TRUE" || value == "1"
    }

    /// The address configured for an environment, or nil when none was set.
    public static func baseURL(for environment: BackendEnvironment) -> URL? {
        if let url = parseURL(infoValue(environment.infoKey)) {
            return url
        }
        // Builds made before per-environment addresses existed carry a single address.
        if environment == buildEnvironment, let legacy = parseURL(infoValue("RRAPIBaseURL")) {
            return legacy
        }
        return environment == .development ? URL(string: fallbackAPIBaseURL) : nil
    }

    public static var defaultAPIBaseURL: URL {
        baseURL(for: buildEnvironment) ?? URL(string: fallbackAPIBaseURL)!
    }

    /// Decides which server to talk to.
    ///
    /// Choices made in the app are honoured only when the build allows
    /// switching, so a release build can never be redirected by a leftover
    /// setting.
    public static func backend(
        environment chosen: String?,
        customURL: String?,
        allowSwitching: Bool = AppConfig.allowsEnvironmentSwitching
    ) -> BackendTarget {
        if allowSwitching {
            if let url = parseURL(customURL) {
                return BackendTarget(url: url, environment: nil, source: .custom)
            }
            if let chosen, let environment = BackendEnvironment(rawValue: chosen), let url = baseURL(for: environment) {
                return BackendTarget(url: url, environment: environment, source: environment == buildEnvironment ? .build : .chosen)
            }
        }
        return BackendTarget(url: defaultAPIBaseURL, environment: buildEnvironment, source: .build)
    }

    public static func backend(settings: AppSettings) -> BackendTarget {
        backend(environment: settings.apiEnvironment, customURL: settings.apiBaseURLOverride)
    }

    /// The backend to talk to: a typed address if one is set, valid and allowed, otherwise the build's default.
    public static func apiBaseURL(override: String?) -> URL {
        backend(environment: nil, customURL: override).url
    }

    // MARK: App

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
