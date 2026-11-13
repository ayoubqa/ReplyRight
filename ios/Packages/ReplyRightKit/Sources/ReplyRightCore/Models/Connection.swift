import Foundation

/// Whether ReplyRight can reach its server, and what kind of answers it will get.
///
/// The app shows this wherever it matters, so a reply is never mistaken for
/// live AI when it is a demo sample, and a failure always says which link in
/// the chain is broken.
public enum ConnectionState: Equatable, Sendable {
    /// Nothing has been checked yet.
    case unknown
    case checking
    /// The server answered and has an AI provider. Replies are written by AI.
    case live(model: String?)
    /// The server answered and has an AI provider, but its recent AI calls failed.
    case liveFailing(reason: String?)
    /// The server answered but has no AI key. Every reply is a labelled sample.
    case demo
    /// The server did not answer.
    case unreachable(APIError)

    public init(status: StatusResponse) {
        switch status.mode {
        case .demo:
            self = .demo
        case .live:
            if status.ai?.state == "failing" {
                self = .liveFailing(reason: status.ai?.lastFailureReason)
            } else {
                self = .live(model: status.ai?.primaryModel)
            }
        }
    }

    public var title: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .checking: return "Checking…"
        case .live: return "Live AI"
        case .liveFailing: return "AI isn't answering"
        case .demo: return "Demo mode"
        case .unreachable(let error):
            if case .offline = error { return "You're offline" }
            return "Can't reach ReplyRight"
        }
    }

    /// One or two plain sentences on what this means for the person using the app.
    public var summary: String {
        switch self {
        case .unknown:
            return "ReplyRight hasn't checked its connection yet."
        case .checking:
            return "Checking the connection."
        case .live:
            return "Connected. Replies are written by AI for your conversation."
        case .liveFailing(let reason):
            return "The server is reachable, but its AI isn't answering. \(ServerFailure.explain(reason))"
        case .demo:
            return "Connected, but the server has no AI key. Everything you see is a pre-written sample, not a reply to your conversation."
        case .unreachable(let error):
            return error.userMessage
        }
    }

    /// True when a request is worth sending.
    public var canAnswer: Bool {
        switch self {
        case .unreachable: return false
        default: return true
        }
    }

    public var isDemo: Bool { self == .demo }

    public var isProblem: Bool {
        switch self {
        case .unreachable, .liveFailing: return true
        default: return false
        }
    }
}

/// Plain explanations for the coarse failure reasons the server reports.
/// They are written for whoever runs the server; they never contain user content.
public enum ServerFailure {
    public static func explain(_ reason: String?) -> String {
        switch reason {
        case "credentials":
            return "The AI key on the server was rejected. Check ANTHROPIC_API_KEY."
        case "billing":
            return "The AI account on the server has run out of credit."
        case "model":
            return "The server is set to an AI model that isn't available. Check AI_MODEL."
        case "request":
            return "The AI provider rejected the request. The server log has the details."
        case "overloaded":
            return "The AI provider is busy. This usually clears up by itself."
        case "timeout":
            return "The AI provider took too long to answer."
        case "network":
            return "The server couldn't connect to the AI provider."
        case "rate_limit":
            return "The AI provider is limiting requests. Try again shortly."
        case "not_configured":
            return "The server has no AI key, so it only returns samples."
        default:
            return "The server log has more detail."
        }
    }
}
