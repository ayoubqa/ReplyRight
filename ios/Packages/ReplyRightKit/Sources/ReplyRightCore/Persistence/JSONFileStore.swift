import Foundation

/// Where ReplyRight keeps its files.
public enum AppGroup {
    public static var identifier: String { AppConfig.appGroupIdentifier }

    /// The container shared by the app and its extensions, or nil when the App
    /// Group is not available (missing entitlement, unit tests, other platforms).
    public static var sharedContainerURL: URL? {
        #if canImport(Darwin)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }

    public static var isAvailable: Bool { sharedContainerURL != nil }

    /// The shared container when there is one, otherwise a private directory so the app still works.
    public static func storageDirectory() -> URL {
        if let shared = sharedContainerURL {
            return shared.appendingPathComponent("ReplyRight", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ReplyRight", isDirectory: true)
    }
}

/// Small Codable values stored as JSON files in one directory.
///
/// Used instead of a database because the data is small, has to be readable
/// from three processes (app, keyboard, share sheet), and should be trivial to
/// inspect and erase.
public final class JSONFileStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    public func read<Value: Decodable>(_ type: Value.Type, name: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Returns false when the value could not be written, for example from a
    /// keyboard running without Full Access, where the shared container is read-only.
    @discardableResult
    public func write<Value: Encodable>(_ value: Value, name: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return writeData(data, name: name)
    }

    public func readData(name: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return try? Data(contentsOf: fileURL(name))
    }

    @discardableResult
    public func writeData(_ data: Data, name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            let url = fileURL(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
            return true
        } catch {
            return false
        }
    }

    public func delete(name: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(name))
    }

    public func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(name).path)
    }

    /// Removes every file in the directory except the names listed.
    public func deleteAll(except keep: Set<String> = []) {
        lock.lock()
        defer { lock.unlock() }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in contents where !keep.contains(name) {
            try? FileManager.default.removeItem(at: fileURL(name))
        }
    }
}
