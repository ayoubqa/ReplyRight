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
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
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
    case offline
    case timedOut
    case cancelled
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
        case .rateLimited:
            return "You're going a little fast. Take a breath and try again in a moment."
        case .limitReached(let message, _), .upgradeRequired(let message, _), .declined(let message),
             .invalid(let message), .unavailable(let message), .server(let message):
            return message
        case .unexpectedResponse:
            return "Something came back garbled. Please try again."
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

    var isTransient: Bool {
        switch self {
        case .unavailable: return true
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

        public init(
            baseURL: @escaping @Sendable () -> URL,
            clientName: String,
            installID: @escaping @Sendable () -> String? = { nil },
            entitlementToken: @escaping @Sendable () -> String? = { nil },
            maxRetries: Int = 1,
            retryDelay: TimeInterval = 0.8
        ) {
            self.baseURL = baseURL
            self.clientName = clientName
            self.installID = installID
            self.entitlementToken = entitlementToken
            self.maxRetries = maxRetries
            self.retryDelay = retryDelay
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
        request.timeoutInterval = 15
        return try await perform(request)
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
        request.timeoutInterval = 75

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
        return try await perform(request)
    }

    // MARK: Sending

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        var attempt = 0
        while true {
            do {
                return try await performOnce(request)
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

    private func performOnce<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIClient.map(error)
        } catch {
            throw APIError.unavailable(message: "I couldn't reach ReplyRight. Please try again.")
        }

        guard (200..<300).contains(response.statusCode) else {
            throw APIClient.mapFailure(status: response.statusCode, data: data, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
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
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .unavailable(message: "I couldn't reach ReplyRight. Check your connection and try again.")
        default:
            return .unavailable(message: "I couldn't reach ReplyRight. Please try again.")
        }
    }

    static func mapFailure(status: Int, data: Data, retryAfter: String?) -> APIError {
        let detail = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
        let message = detail?.message ?? "Something went wrong on our side. Please try again."
        switch detail?.code {
        case "limit_reached":
            return .limitReached(message: message, usage: detail?.usage)
        case "upgrade_required":
            return .upgradeRequired(message: message, usage: detail?.usage)
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
