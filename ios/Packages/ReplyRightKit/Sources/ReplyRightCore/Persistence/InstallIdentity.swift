import Foundation
#if canImport(Security)
import Security
#endif

/// A minimal wrapper around the keychain for small string values.
public enum Keychain {
    public static let service = "com.replyright.identity"

    #if canImport(Security)
    private static func baseQuery(key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public static func read(_ key: String, accessGroup: String?) -> String? {
        var query = baseQuery(key: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func write(_ value: String, key: String, accessGroup: String?) -> Bool {
        let query = baseQuery(key: key, accessGroup: accessGroup)
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = query
        insert[kSecValueData as String] = data
        // Readable after the first unlock so the keyboard can use it.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(_ key: String, accessGroup: String?) {
        SecItemDelete(baseQuery(key: key, accessGroup: accessGroup) as CFDictionary)
    }
    #else
    public static func read(_ key: String, accessGroup: String?) -> String? { nil }

    @discardableResult
    public static func write(_ value: String, key: String, accessGroup: String?) -> Bool { false }

    public static func delete(_ key: String, accessGroup: String?) {}
    #endif
}

/// The anonymous identifier this install uses for daily usage limits.
///
/// It is a random UUID created on the device. It is not derived from the
/// device, the Apple Account or anything personal. It is kept in the keychain
/// (shared with the extensions when signing allows) so limits survive a
/// reinstall, with a copy in the App Group container as a fallback.
public enum InstallIdentity {
    private static let key = "install-id"

    public static func current(store: SharedStore = .shared) -> String {
        let group = AppConfig.keychainGroup

        if let stored = Keychain.read(key, accessGroup: group), UUID(uuidString: stored) != nil {
            if store.loadInstallID() != stored {
                store.saveInstallID(stored)
            }
            return stored
        }
        if let mirrored = store.loadInstallID() {
            Keychain.write(mirrored, key: key, accessGroup: group)
            return mirrored
        }
        let fresh = UUID().uuidString.lowercased()
        Keychain.write(fresh, key: key, accessGroup: group)
        store.saveInstallID(fresh)
        return fresh
    }
}
