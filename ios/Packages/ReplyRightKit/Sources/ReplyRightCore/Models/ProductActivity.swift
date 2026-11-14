import Foundation

/// How much ReplyRight is actually helping, counted on this iPhone only.
///
/// The product's primary measure is a **successful week**: at least one
/// ReplyRight suggestion generated and then used (copied from the app or the
/// share sheet, or inserted by the keyboard). Keyboard insertions are counted
/// separately as well, to follow keyboard adoption.
///
/// These are plain numbers per day. No text, no names, nothing about the
/// conversation. They stay on the device: nothing here is sent anywhere.
/// Counting successful users across all installs needs a reporting channel
/// that has not been built.
public struct ProductActivity: Codable, Equatable, Sendable {
    /// Where a suggestion was used.
    public enum Source: String, Codable, Sendable {
        case app
        case keyboard
        case share
    }

    public enum Event: Equatable, Sendable {
        /// A set of AI suggestions arrived (live AI only, never demo samples).
        case suggestionsShown(Source)
        /// The user copied or inserted a suggestion.
        case suggestionUsed(Source)
    }

    public struct Day: Codable, Equatable, Sendable {
        public var suggestionsShown: Int
        public var suggestionsUsed: Int
        public var keyboardSuggestionsShown: Int
        public var keyboardInsertions: Int

        public init(suggestionsShown: Int = 0, suggestionsUsed: Int = 0, keyboardSuggestionsShown: Int = 0, keyboardInsertions: Int = 0) {
            self.suggestionsShown = suggestionsShown
            self.suggestionsUsed = suggestionsUsed
            self.keyboardSuggestionsShown = keyboardSuggestionsShown
            self.keyboardInsertions = keyboardInsertions
        }
    }

    public struct Summary: Equatable, Sendable {
        public var suggestionsShown = 0
        public var suggestionsUsed = 0
        public var keyboardSuggestionsShown = 0
        public var keyboardInsertions = 0

        public init() {}

        /// A week in which the user generated and used at least one suggestion.
        public var isSuccessful: Bool { suggestionsShown > 0 && suggestionsUsed > 0 }
    }

    /// Counts per UTC day, keyed "2026-11-14". Older than 12 weeks is dropped.
    public var days: [String: Day]

    public init(days: [String: Day] = [:]) {
        self.days = days
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? c.decodeIfPresent([String: Day].self, forKey: .days)) ?? [:]
    }

    static func key(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public mutating func record(_ event: Event, at date: Date = Date()) {
        let key = Self.key(for: date)
        var day = days[key] ?? Day()
        switch event {
        case .suggestionsShown(let source):
            day.suggestionsShown += 1
            if source == .keyboard { day.keyboardSuggestionsShown += 1 }
        case .suggestionUsed(let source):
            day.suggestionsUsed += 1
            if source == .keyboard { day.keyboardInsertions += 1 }
        }
        days[key] = day
        prune(before: date.addingTimeInterval(-84 * 24 * 60 * 60))
    }

    private mutating func prune(before cutoff: Date) {
        let oldest = Self.key(for: cutoff)
        days = days.filter { $0.key >= oldest }
    }

    /// Totals for the seven days ending on `date` (inclusive).
    public func lastSevenDays(endingAt date: Date = Date()) -> Summary {
        var summary = Summary()
        for offset in 0..<7 {
            let key = Self.key(for: date.addingTimeInterval(-Double(offset) * 24 * 60 * 60))
            guard let day = days[key] else { continue }
            summary.suggestionsShown += day.suggestionsShown
            summary.suggestionsUsed += day.suggestionsUsed
            summary.keyboardSuggestionsShown += day.keyboardSuggestionsShown
            summary.keyboardInsertions += day.keyboardInsertions
        }
        return summary
    }

    /// True once the user has ever used a suggestion, within the kept history.
    public var hasUsedSuggestion: Bool {
        days.values.contains { $0.suggestionsUsed > 0 }
    }

    /// Keyboard insertions within the kept history.
    public var totalKeyboardInsertions: Int {
        days.values.reduce(0) { $0 + $1.keyboardInsertions }
    }
}
