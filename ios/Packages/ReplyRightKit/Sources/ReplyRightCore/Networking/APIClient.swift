import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request. Abstracted so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The production transport: an ephemeral URLSession with no cookies and no disk cache,
/// so nothing about a conversation is written to disk by the networking layer.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Everything that can go wrong talking to the backend, in terms the UI can act on.
public enum APIError: Error, Equatable, Sendable {
    /// Why the server could not be reached at all.
    public enum Unreachable: String, Equatable, Sendable {
        /// Nothing is listening at that address.
        case refused
        /// The address does not exist.
        case hostNotFound
        /// iOS blocked a plain http connection to a server that is not on the local network.
        case blockedInsecure
        /// The secure connection could not be set up (certificate or TLS problem).
        case secureConnectionFailed
        case connectionLost
        case other
    }

    /// This device has no internet connection.
    case offline
    case timedOut
    case cancelled
    /// The device is online but the ReplyRight server did not answer.
    case serverUnreachable(Unreachable)
    case rateLimited(retryAfter: Int?)
    /// The daily allowance for this plan is used up.
    case limitReached(message: String, usage: Usage?)
    /// The request needs ReplyRight Pro.
    case upgradeRequired(message: String, usage: Usage?)
    /// The assistant declined to help with this content.
    case declined(message: String)
    case invalid(message: String)
    /// The service is temporarily unavailable. Safe to retry.
    case unavailable(message: String)
    case server(message: String)
    /// Something answered, but not in a form ReplyRight understands.
    case unexpectedResponse

    /// A message written for the person using the app.
    public var userMessage: String {
        switch self {
        case .offline:
            return "You seem to be offline. Check your connection and try again."
        case .timedOut:
            return "That took longer than it should. Give it another go."
        case .cancelled:
            return "Cancelled."
        case .serverUnreachable(let why):
            switch why {
            case .connectionLost:
                return "The connection dropped halfway. Try again."
            default:
                return "I can't reach ReplyRight right now. Nothing was sent. Try again in a moment."
            }
        case .rateLimited:
            return "You're going a little fast. Take a breath and try again in a moment."
        case .limitReached(let message, _), .upgradeRequired(let message, _), .declined(let message),
             .invalid(let message), .unavailable(let message), .server(let message):
            return message
        case .unexpectedResponse:
            return "Something came back garbled. Please try again."
        }
    }

    /// A short heading for the message above.
    public var title: String {
        switch self {
        case .offline: return "You're offline"
        case .timedOut: return "That took too long"
        case .cancelled: return "Cancelled"
        case .serverUnreachable: return "Can't reach ReplyRight"
        case .rateLimited: return "One moment"
        case .limitReached: return "That's today's limit"
        case .upgradeRequired: return "That one is part of Pro"
        case .declined: return "I can't help with this one"
        case .invalid: return "That needs a small change"
        case .unavailable, .server, .unexpectedResponse: return "That didn't go through"
        }
    }

    /// True when the paywall is the right next step.
    public var suggestsUpgrade: Bool {
        switch self {
        case .limitReached, .upgradeRequired: return true
        default: return false
        }
    }

    public var usage: Usage? {
        switch self {
        case .limitReached(_, let usage), .upgradeRequired(_, let usage): return usage
        default: return nil
        }
    }

    /// True when sending the same request again could work.
    public var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .serverUnreachable, .rateLimited, .unavailable, .server, .unexpectedResponse:
            return true
        case .cancelled, .limitReached, .upgradeRequired, .declined, .invalid:
            return false
        }
    }

    /// True when the problem is the connection to the server rather than this request.
    public var isConnectionProblem: Bool {
        switch self {
        case .offline, .serverUnreachable, .timedOut: return true
        default: return false
        }
    }

    /// A short code for the diagnostics log. Contains nothing from the request.
    public var diagnosticCode: String {
        switch self {
        case .offline: return "offline"
        case .timedOut: return "timeout"
        case .cancelled: return "cancelled"
        case .serverUnreachable(let why): return "unreachable.\(why.rawValue)"
        case .rateLimited: return "rate_limited"
        case .limitReached: return "limit_reached"
        case .upgradeRequired: return "upgrade_required"
        case .declined: return "ai_declined"
        case .invalid: return "invalid_request"
        case .unavailable: return "unavailable"
        case .server: return "server_error"
        case .unexpectedResponse: return "unexpected_response"
        }
    }

    /// What to check when the server cannot be reached, written for whoever is
    /// setting the app up. Shown in the connection screen, never in place of `userMessage`.
    public func setupHint(for target: BackendTarget) -> String? {
        switch self {
        case .serverUnreachable(let why):
            switch why {
            case .refused:
                if target.isLoopback {
                    return "Nothing is answering at \(target.displayAddress). Start the server on your Mac: open Terminal, run “cd backend” then “npm run dev”, and check which port it reports. On a real iPhone, localhost means the phone itself, so use your Mac's network address instead."
                }
                return "Nothing is answering at \(target.displayAddress). Check that the server is running and that the port is right."
            case .hostNotFound:
                return "The address \(target.displayAddress) doesn't exist. Check the spelling, and that this device is on the same network if it is a local address."
            case .blockedInsecure:
                return "iOS only allows plain http for servers on your own network. Use an https address for \(target.displayAddress)."
            case .secureConnectionFailed:
                return "The secure connection to \(target.displayAddress) failed. Check the server's certificate."
            case .connectionLost, .other:
                return "The connection to \(target.displayAddress) failed. Check that the server is running and reachable from this device."
            }
        case .timedOut:
            return "\(target.displayAddress) did not answer in time. If the server is running, it may be busy or unreachable from this device."
        case .unexpectedResponse:
            return "Something answered at \(target.displayAddress), but it doesn't look like the ReplyRight server. Check the address and the port."
        case .offline:
            return "This device has no internet connection."
        default:
            return nil
        }
    }

    var isTransient: Bool {
        switch self {
        case .unavailable, .serverUnreachable(.connectionLost): return true
        default: return false
        }
    }
}

/// Client for ReplyRight API v1. Shared by the app, the keyboard and the share sheet.
///
/// It holds no AI credentials. Requests carry an anonymous install id (for daily
/// limits) and, for subscribers, the signed App Store transaction that the
/// server verifies independently.
public final class APIClient: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var baseURL: @Sendable () -> URL
        /// For example "ios-app/1.0.0" or "ios-keyboard/1.0.0".
        public var clientName: String
        public var installID: @Sendable () -> String?
        public var entitlementToken: @Sendable () -> String?
        /// Extra attempts after a transient failure.
        public var maxRetries: Int
        public var retryDelay: TimeInterval
        /// Where content-free request records go. Nil turns recording off.
        public var diagnostics: DiagnosticsLog?

        public init(
            baseURL: @escaping @Sendable () -> URL,
            clientName: String,
            installID: @escaping @Sendable () -> String? = { nil },
            entitlementToken: @escaping @Sendable () -> String? = { nil },
            maxRetries: Int = 1,
            retryDelay: TimeInterval = 0.8,
            diagnostics: DiagnosticsLog? = .shared
        ) {
            self.baseURL = baseURL
            self.clientName = clientName
            self.installID = installID
            self.entitlementToken = entitlementToken
            self.maxRetries = maxRetries
            self.retryDelay = retryDelay
            self.diagnostics = diagnostics
        }
    }

    private let configuration: Configuration
    private let transport: HTTPTransport

    public init(configuration: Configuration, transport: HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    // MARK: Endpoints

    public func status() async throws -> StatusResponse {
        var request = baseRequest(path: "status")
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        return try await perform(request, endpoint: "status", images: 0)
    }

    /// Asks the server to make one small, fixed AI call and report whether it worked.
    /// Nothing from the user is sent. Open on development servers only.
    public func probe() async throws -> ProbeResult {
        var request = baseRequest(path: "diagnostics/probe")
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        return try await perform(request, endpoint: "probe", images: 0)
    }

    /// Reads a conversation from pasted text and/or screenshots (JPEG data).
    public func analyze(_ body: AnalyzeRequest, images: [Data] = []) async throws -> Envelope<Analysis> {
        try await post("analyze", body: body, images: images)
    }

    public func replies(_ body: RepliesRequest, images: [Data] = []) async throws -> Envelope<RepliesResult> {
        try await post("replies", body: body, images: images)
    }

    public func refine(_ body: RefineRequest) async throws -> Envelope<RefineResult> {
        try await post("refine", body: body, images: [])
    }

    public func coach(_ body: CoachRequest) async throws -> Envelope<CoachResult> {
        try await post("coach", body: body, images: [])
    }

    // MARK: Request building

    private func baseRequest(path: String) -> URLRequest {
        let url = configuration.baseURL().appendingPathComponent("api/v1/\(path)")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.clientName, forHTTPHeaderField: "X-RR-Client")
        if let install = configuration.installID(), !install.isEmpty {
            request.setValue(install, forHTTPHeaderField: "X-RR-Install")
        }
        if let token = configuration.entitlementToken(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-RR-Entitlement")
        }
        return request
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        images: [Data]
    ) async throws -> Response {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw APIError.invalid(message: "We couldn't prepare that request.")
        }

        var request = baseRequest(path: path)
        request.httpMethod = "POST"
        request.timeoutInterval = 90

        let attachments = Array(images.prefix(RequestLimits.maxImages))
        if attachments.isEmpty {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
        } else {
            var multipart = MultipartBody()
            multipart.addField(name: "payload", value: payload)
            for (index, image) in attachments.enumerated() {
                multipart.addFile(name: "images", filename: "screenshot-\(index + 1).jpg", mimeType: "image/jpeg", data: image)
            }
            request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = multipart.finalized()
        }
        return try await perform(request, endpoint: path, images: attachments.count)
    }

    // MARK: Sending

    /// Thrown inside the client when the server says an automatic repeat could
    /// pay for a second AI call. The caller receives the wrapped error unchanged.
    private struct ServerSaysDoNotRetry: Error {
        let error: APIError
    }

    private func perform<Response: Decodable>(_ request: URLRequest, endpoint: String, images: Int) async throws -> Response {
        var attempt = 0
        while true {
            do {
                return try await performOnce(request, endpoint: endpoint, images: images)
            } catch let stop as ServerSaysDoNotRetry {
                throw stop.error
            } catch let error as APIError {
                guard error.isTransient, attempt < configuration.maxRetries else { throw error }
                attempt += 1
                let delay = configuration.retryDelay * Double(attempt)
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    throw APIError.cancelled
                }
            }
        }
    }

    private func performOnce<Response: Decodable>(_ request: URLRequest, endpoint: String, images: Int) async throws -> Response {
        let started = Date()
        var record = RequestRecord(
            date: started,
            endpoint: endpoint,
            host: request.url?.host ?? "",
            status: nil,
            durationMs: 0,
            outcome: "ok",
            imageCount: images,
            bytesSent: request.httpBody?.count ?? 0
        )
        // Records how the request ended. Only codes and timings, never content.
        func finish(_ error: APIError?) {
            record.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            if let error {
                // A request the user cancelled is not worth a line in the log.
                if error == APIError.cancelled { return }
                // The server's own code is more precise than the client's when there is one.
                if record.outcome == "ok" { record.outcome = error.diagnosticCode }
            }
            configuration.diagnostics?.add(record)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError {
            let mapped = APIClient.map(error)
            finish(mapped)
            throw mapped
        } catch {
            let mapped = APIError.serverUnreachable(.other)
            finish(mapped)
            throw mapped
        }

        record.status = response.statusCode
        record.requestID = response.value(forHTTPHeaderField: "X-RR-Request")

        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
            let failure = APIClient.mapFailure(
                status: response.statusCode,
                detail: detail,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
            )
            if let detail {
                record.outcome = detail.code
                record.reason = detail.reason
            } else {
                record.outcome = "http_\(response.statusCode)"
            }
            finish(failure)
            // The server sends this after a failure that may already have been
            // billed (unusable output, a timeout, its spend limit). It has made
            // its own safe retries, so the app does not repeat the request by
            // itself. The person can still tap Try again.
            if response.value(forHTTPHeaderField: "X-RR-Retry")?.lowercased() == "no" {
                throw ServerSaysDoNotRetry(error: failure)
            }
            throw failure
        }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            record.mode = (try? JSONDecoder().decode(ModeProbe.self, from: data))?.mode
            finish(nil)
            return decoded
        } catch {
            finish(APIError.unexpectedResponse)
            throw APIError.unexpectedResponse
        }
    }

    static func map(_ error: URLError) -> APIError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .cannotConnectToHost:
            return .serverUnreachable(.refused)
        case .cannotFindHost, .dnsLookupFailed:
            return .serverUnreachable(.hostNotFound)
        case .appTransportSecurityRequiresSecureConnection:
            return .serverUnreachable(.blockedInsecure)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return .serverUnreachable(.secureConnectionFailed)
        case .networkConnectionLost:
            return .serverUnreachable(.connectionLost)
        default:
            return .serverUnreachable(.other)
        }
    }

    static func mapFailure(status: Int, detail: APIErrorBody.Detail?, retryAfter: String?) -> APIError {
        guard let detail else {
            // An error without ReplyRight's own error body came from something else:
            // a proxy, a host's error page, or a different server on that port.
            switch status {
            case 429: return .rateLimited(retryAfter: retryAfter.flatMap { Int($0) })
            case 502, 503, 504: return .unavailable(message: "ReplyRight is having a moment. Please try again.")
            case 404, 405: return .unexpectedResponse
            case 413: return .invalid(message: "Those screenshots are too large to send. Try fewer, or crop them.")
            default: return .server(message: "Something went wrong on our side. Please try again.")
            }
        }
        let message = detail.message
        switch detail.code {
        case "limit_reached":
            return .limitReached(message: message, usage: detail.usage)
        case "upgrade_required":
            return .upgradeRequired(message: message, usage: detail.usage)
        case "rate_limited":
            return .rateLimited(retryAfter: retryAfter.flatMap { Int($0) })
        case "ai_declined":
            return .declined(message: message)
        case "invalid_request", "unsupported_media", "payload_too_large":
            return .invalid(message: message)
        case "ai_unavailable":
            return .unavailable(message: message)
        default:
            break
        }
        switch status {
        case 429: return .rateLimited(retryAfter: retryAfter.flatMap { Int($0) })
        case 502, 503, 504: return .unavailable(message: message)
        default: return .server(message: message)
        }
    }
}

/// Reads only the "mode" field of a response, for the diagnostics log.
private struct ModeProbe: Decodable {
    var mode: String?
}

/// Builds a multipart/form-data body.
struct MultipartBody {
    let boundary = "rr-boundary-\(UUID().uuidString)"
    private var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: Data) {
        append("--\(boundary)\r\n")
        // No Content-Type or filename: the server reads this part as a plain string field.
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append(value)
        append("\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    func finalized() -> Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
