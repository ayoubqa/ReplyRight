import Foundation

/// One request to the ReplyRight server, described without any of its content.
///
/// A record holds where the request went, how long it took and how it ended.
/// It never holds a conversation, a draft, a screenshot, a header value or a
/// key, so the log is safe to show on screen and to copy into a bug report.
public struct RequestRecord: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    /// "status", "analyze", "replies", "refine", "coach" or "probe".
    public var endpoint: String
    public var host: String
    public var status: Int?
    public var durationMs: Int
    /// "ok", or a short code for what went wrong, such as "unreachable.refused" or "ai_unavailable".
    public var outcome: String
    /// The server's coarse reason for an AI failure, such as "credentials".
    public var reason: String?
    /// The id the server gave this request. It appears in the server log too.
    public var requestID: String?
    public var imageCount: Int
    public var bytesSent: Int
    /// "live" or "demo", when the server said.
    public var mode: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        endpoint: String,
        host: String,
        status: Int?,
        durationMs: Int,
        outcome: String,
        reason: String? = nil,
        requestID: String? = nil,
        imageCount: Int = 0,
        bytesSent: Int = 0,
        mode: String? = nil
    ) {
        self.id = id
        self.date = date
        self.endpoint = endpoint
        self.host = host
        self.status = status
        self.durationMs = durationMs
        self.outcome = outcome
        self.reason = reason
        self.requestID = requestID
        self.imageCount = imageCount
        self.bytesSent = bytesSent
        self.mode = mode
    }

    public var succeeded: Bool { outcome == "ok" }

    /// One line for a plain-text report.
    public var line: String {
        let statusText = status.map { "HTTP \($0)" } ?? "no answer"
        var parts: [String] = [RequestRecord.stamp.string(from: date), endpoint, statusText, "\(durationMs) ms", outcome]
        if let reason { parts.append("reason \(reason)") }
        if let mode { parts.append(mode) }
        if imageCount > 0 { parts.append("\(imageCount) image\(imageCount == 1 ? "" : "s")") }
        if let requestID { parts.append("id \(requestID)") }
        return parts.joined(separator: ", ")
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// The most recent requests made by this process, newest first.
///
/// Kept in memory only. It is gone when the app closes, and the keyboard and
/// the share sheet each have their own.
public final class DiagnosticsLog: @unchecked Sendable {
    public static let shared = DiagnosticsLog()
    public static let capacity = 40

    private let lock = NSLock()
    private var items: [RequestRecord] = []

    public init() {}

    public func add(_ record: RequestRecord) {
        lock.lock()
        defer { lock.unlock() }
        items.insert(record, at: 0)
        if items.count > DiagnosticsLog.capacity {
            items.removeLast(items.count - DiagnosticsLog.capacity)
        }
    }

    public var records: [RequestRecord] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    public var lastFailure: RequestRecord? {
        records.first { !$0.succeeded }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
    }

    /// A plain-text summary for a bug report. Contains no conversation content and no secrets.
    public func report(target: BackendTarget, state: ConnectionState) -> String {
        var lines = [
            "ReplyRight connection report",
            "App \(AppConfig.appVersion) (\(AppConfig.buildNumber)), built for \(AppConfig.buildEnvironment.rawValue)",
            "Server: \(target.label), \(target.displayAddress)",
            "State: \(state.title). \(state.summary)",
            "",
        ]
        let recent = records
        if recent.isEmpty {
            lines.append("No requests yet.")
        } else {
            lines.append("Recent requests, newest first:")
            lines.append(contentsOf: recent.map(\.line))
        }
        lines.append("")
        lines.append("This report contains no messages, screenshots or keys.")
        return lines.joined(separator: "\n")
    }
}
