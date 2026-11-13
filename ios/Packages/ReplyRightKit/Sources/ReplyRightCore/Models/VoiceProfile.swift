import Foundation

/// "My Voice": how the user actually texts.
///
/// Everything here is entered by the user in the app. Nothing is collected
/// from other apps. The profile is stored on the device and a trimmed copy
/// (`VoicePayload`) travels with each request the user makes.
public struct VoiceProfile: Codable, Equatable, Sendable {
    public enum Personality: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case funny, shy, confident, romantic, reserved
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public enum Humour: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case minimal, light, witty, dry, goofy
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
        public var blurb: String {
            switch self {
            case .minimal: return "Sincere first"
            case .light: return "A smile here and there"
            case .witty: return "Quick and clever"
            case .dry: return "Deadpan"
            case .goofy: return "Silly, unserious"
            }
        }
    }

    public enum EmojiUse: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case none, rare, often
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .none: return "Never"
            case .rare: return "Sometimes"
            case .often: return "Often"
            }
        }
    }

    public enum Length: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case short, medium, long
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .short: return "Short"
            case .medium: return "Medium"
            case .long: return "Longer"
            }
        }
        public var blurb: String {
            switch self {
            case .short: return "One line"
            case .medium: return "A sentence or two"
            case .long: return "A few sentences"
            }
        }
    }

    public enum Vocabulary: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case casual, balanced, polished
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .casual: return "Casual"
            case .balanced: return "Everyday"
            case .polished: return "Polished"
            }
        }
    }

    public enum Directness: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case gentle, balanced, bold
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public enum Romance: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case subtle, balanced, open
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    /// What the user came for. Shapes the home screen; never sent to the server.
    public enum Goal: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case reply, flirt, keepGoing, start, askOut, feelings
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .reply: return "Replying without overthinking"
            case .flirt: return "Flirting naturally"
            case .keepGoing: return "Keeping conversations alive"
            case .start: return "Starting conversations"
            case .askOut: return "Asking them out"
            case .feelings: return "Saying how I feel"
            }
        }
    }

    /// A message the user has really sent, kept as a style example.
    public struct Sample: Codable, Identifiable, Equatable, Hashable, Sendable {
        public enum Source: String, Codable, Sendable {
            /// Typed or pasted by the user in My Voice.
            case added
            /// Kept, with the user's permission, from a reply they edited and copied.
            case learned
        }

        public var id: UUID
        public var text: String
        public var source: Source
        public var addedAt: Date

        public init(id: UUID = UUID(), text: String, source: Source = .added, addedAt: Date = Date()) {
            self.id = id
            self.text = text
            self.source = source
            self.addedAt = addedAt
        }
    }

    public static let maxSamples = 8
    public static let maxSampleLength = 280
    public static let maxNoteLength = 300

    public var defaultTone: Tone
    public var personality: [Personality]
    public var humour: Humour
    public var emoji: EmojiUse
    public var length: Length
    public var vocabulary: Vocabulary
    public var directness: Directness
    public var romance: Romance
    /// "match" or a language id such as "en" or "es".
    public var replyLanguage: String
    public var languages: [String]
    public var writingStyle: String
    public var aboutMe: String
    public var samples: [Sample]
    public var goals: [Goal]

    public init(
        defaultTone: Tone = .playful,
        personality: [Personality] = [],
        humour: Humour = .light,
        emoji: EmojiUse = .rare,
        length: Length = .short,
        vocabulary: Vocabulary = .casual,
        directness: Directness = .balanced,
        romance: Romance = .balanced,
        replyLanguage: String = "match",
        languages: [String] = ["en"],
        writingStyle: String = "",
        aboutMe: String = "",
        samples: [Sample] = [],
        goals: [Goal] = []
    ) {
        self.defaultTone = defaultTone
        self.personality = personality
        self.humour = humour
        self.emoji = emoji
        self.length = length
        self.vocabulary = vocabulary
        self.directness = directness
        self.romance = romance
        self.replyLanguage = replyLanguage
        self.languages = languages
        self.writingStyle = writingStyle
        self.aboutMe = aboutMe
        self.samples = samples
        self.goals = goals
    }

    public static let standard = VoiceProfile()

    // Decoding tolerates missing keys so profiles saved by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = VoiceProfile.standard
        defaultTone = (try? c.decodeIfPresent(Tone.self, forKey: .defaultTone)) ?? fallback.defaultTone
        personality = (try? c.decodeIfPresent([Personality].self, forKey: .personality)) ?? fallback.personality
        humour = (try? c.decodeIfPresent(Humour.self, forKey: .humour)) ?? fallback.humour
        emoji = (try? c.decodeIfPresent(EmojiUse.self, forKey: .emoji)) ?? fallback.emoji
        length = (try? c.decodeIfPresent(Length.self, forKey: .length)) ?? fallback.length
        vocabulary = (try? c.decodeIfPresent(Vocabulary.self, forKey: .vocabulary)) ?? fallback.vocabulary
        directness = (try? c.decodeIfPresent(Directness.self, forKey: .directness)) ?? fallback.directness
        romance = (try? c.decodeIfPresent(Romance.self, forKey: .romance)) ?? fallback.romance
        replyLanguage = (try? c.decodeIfPresent(String.self, forKey: .replyLanguage)) ?? fallback.replyLanguage
        languages = (try? c.decodeIfPresent([String].self, forKey: .languages)) ?? fallback.languages
        writingStyle = (try? c.decodeIfPresent(String.self, forKey: .writingStyle)) ?? fallback.writingStyle
        aboutMe = (try? c.decodeIfPresent(String.self, forKey: .aboutMe)) ?? fallback.aboutMe
        samples = (try? c.decodeIfPresent([Sample].self, forKey: .samples)) ?? fallback.samples
        goals = (try? c.decodeIfPresent([Goal].self, forKey: .goals)) ?? fallback.goals
    }

    /// The copy of the profile that is sent with a request.
    public var payload: VoicePayload {
        VoicePayload(
            defaultTone: defaultTone,
            personality: Array(personality.prefix(3)),
            humour: humour,
            emoji: emoji,
            length: length,
            vocabulary: vocabulary,
            directness: directness,
            romance: romance,
            replyLanguage: ReplyLanguage.isSupported(replyLanguage) ? replyLanguage : "match",
            languages: languages.filter { ReplyLanguage.isSupported($0) && $0 != "match" },
            writingStyle: String(writingStyle.trimmed.prefix(VoiceProfile.maxNoteLength)),
            aboutMe: String(aboutMe.trimmed.prefix(VoiceProfile.maxNoteLength)),
            samples: samples
                .map { String($0.text.trimmed.prefix(VoiceProfile.maxSampleLength)) }
                .filter { !$0.isEmpty }
                .prefix(VoiceProfile.maxSamples)
                .map { $0 }
        )
    }

    /// Adds a sample, newest first, dropping duplicates and the oldest learned samples beyond the cap.
    public mutating func addSample(_ text: String, source: Sample.Source, now: Date = Date()) {
        let clean = String(text.trimmed.prefix(VoiceProfile.maxSampleLength))
        guard !clean.isEmpty else { return }
        samples.removeAll { $0.text.caseInsensitiveCompare(clean) == .orderedSame }
        samples.insert(Sample(text: clean, source: source, addedAt: now), at: 0)
        while samples.count > VoiceProfile.maxSamples {
            if let index = samples.lastIndex(where: { $0.source == .learned }) {
                samples.remove(at: index)
            } else {
                samples.removeLast()
            }
        }
    }
}

/// The wire format of a voice profile. Mirrors `voiceSchema` in the backend.
public struct VoicePayload: Codable, Equatable, Sendable {
    public var defaultTone: Tone
    public var personality: [VoiceProfile.Personality]
    public var humour: VoiceProfile.Humour
    public var emoji: VoiceProfile.EmojiUse
    public var length: VoiceProfile.Length
    public var vocabulary: VoiceProfile.Vocabulary
    public var directness: VoiceProfile.Directness
    public var romance: VoiceProfile.Romance
    public var replyLanguage: String
    public var languages: [String]
    public var writingStyle: String
    public var aboutMe: String
    public var samples: [String]
}

/// Languages replies can be written in.
public struct ReplyLanguage: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let nativeName: String
    /// False for languages the backend can already write but the app has not been tested in yet.
    public let isAvailable: Bool

    public static let all: [ReplyLanguage] = [
        ReplyLanguage(id: "en", name: "English", nativeName: "English", isAvailable: true),
        ReplyLanguage(id: "es", name: "Spanish", nativeName: "Español", isAvailable: true),
        ReplyLanguage(id: "fr", name: "French", nativeName: "Français", isAvailable: false),
    ]

    public static var available: [ReplyLanguage] { all.filter(\.isAvailable) }

    public static func isSupported(_ id: String) -> Bool {
        id == "match" || all.contains { $0.id == id }
    }

    public static func name(for id: String) -> String {
        if id == "match" { return "Match the conversation" }
        return all.first { $0.id == id }?.name ?? id
    }
}

extension String {
    /// Whitespace and newlines removed from both ends.
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
