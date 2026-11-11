import Foundation

extension APIClient {
    /// The client every target uses, wired to the shared store.
    ///
    /// - Parameter component: "app", "keyboard" or "share". Sent as a diagnostic header only.
    public static func standard(component: String, store: SharedStore = .shared) -> APIClient {
        APIClient(
            configuration: Configuration(
                baseURL: { AppConfig.apiBaseURL(override: store.loadSettings().apiBaseURLOverride) },
                clientName: AppConfig.clientName(component),
                installID: { InstallIdentity.current(store: store) },
                // The signed transaction is forwarded as-is. The server decides what it is worth.
                entitlementToken: { store.loadEntitlement()?.jws }
            )
        )
    }
}

extension SharedStore {
    /// Remembers what the server last reported about usage and mode, for display in every target.
    public func record(usage: Usage, mode: GenerationMode?) {
        var snapshot = loadService()
        snapshot.usage = usage
        if let mode {
            snapshot.mode = mode
        }
        snapshot.updatedAt = Date()
        saveService(snapshot)
    }

    /// The tier the server last confirmed. Used only to decide what to show; the server enforces limits.
    public func lastKnownTier() -> Tier {
        loadService().usage?.tier ?? .free
    }
}
