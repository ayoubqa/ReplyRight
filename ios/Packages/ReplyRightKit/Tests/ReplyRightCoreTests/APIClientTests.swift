import XCTest
@testable import ReplyRightCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers requests from a queue and records what was sent. No network involved.
private final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: String, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private let lock = NSLock()
    private var queue: [Reply]
    private var recorded: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.queue = replies
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = try next(recording: request)
        switch reply {
        case .response(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        }
    }

    private func next(recording request: URLRequest) throws -> Reply {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !queue.isEmpty else { throw URLError(.badServerResponse) }
        return queue.removeFirst()
    }
}

final class APIClientTests: XCTestCase {
    private let usage = #"{"tier":"free","generations":{"used":10,"limit":10,"remaining":0},"coach":{"used":0,"limit":3,"remaining":3},"resetsAt":"2026-11-11T00:00:00.000Z"}"#

    private var repliesBody: String {
        #"{"mode":"live","provider":"anthropic","model":"claude-opus-5-5","usage":\#(usage),"result":{"note":"Here you go.","replies":[{"style":"Most natural","text":"haha fair","why":"Easy."}],"headsUp":null}}"#
    }

    private func makeClient(_ transport: MockTransport, maxRetries: Int = 1, log: DiagnosticsLog? = nil) -> APIClient {
        APIClient(
            configuration: APIClient.Configuration(
                baseURL: { URL(string: "https://api.example.test")! },
                clientName: "ios-test/1.0.0",
                installID: { "3f2504e0-4f89-41d3-9a0c-0305e82c3301" },
                entitlementToken: { "signed.transaction.token" },
                maxRetries: maxRetries,
                retryDelay: 0,
                // Tests never write to the app's shared log.
                diagnostics: log
            ),
            transport: transport
        )
    }

    private func errorBody(_ code: String, message: String = "Something happened.", withUsage: Bool = false) -> String {
        withUsage
            ? #"{"error":{"code":"\#(code)","message":"\#(message)","usage":\#(usage)}}"#
            : #"{"error":{"code":"\#(code)","message":"\#(message)"}}"#
    }

    private func assertThrows(_ expected: APIError, _ work: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await work()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as APIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
        }
    }

    // MARK: Requests

    func testJSONRequestCarriesIdentityHeadersAndBody() async throws {
        let transport = MockTransport([.response(status: 200, body: repliesBody)])
        let envelope = try await makeClient(transport).replies(RepliesRequest(conversation: "Them: hey", intent: .flirt))

        XCTAssertEqual(envelope.mode, .live)
        XCTAssertEqual(envelope.result.replies.first?.text, "haha fair")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/api/v1/replies")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-RR-Client"), "ios-test/1.0.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-RR-Install"), "3f2504e0-4f89-41d3-9a0c-0305e82c3301")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-RR-Entitlement"), "signed.transaction.token")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["conversation"] as? String, "Them: hey")
        XCTAssertEqual(object["intent"] as? String, "flirt")
    }

    func testScreenshotsAreSentAsMultipartWithThePayloadField() async throws {
        let analysis = #"{"mode":"live","provider":"anthropic","model":null,"usage":\#(usage),"result":{"canReply":true,"read":"Looks friendly.","transcript":[],"suggestedIntents":[]}}"#
        let transport = MockTransport([.response(status: 200, body: analysis)])
        let images = [Data([0xFF, 0xD8, 0xFF, 0x01]), Data([0xFF, 0xD8, 0xFF, 0x02])]
        _ = try await makeClient(transport).analyze(AnalyzeRequest(conversation: "context"), images: images)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/analyze")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = contentType.replacingOccurrences(of: "multipart/form-data; boundary=", with: "")

        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"payload\"\r\n\r\n{"))
        XCTAssertTrue(body.contains("\"conversation\":\"context\""))
        XCTAssertTrue(body.contains("name=\"images\"; filename=\"screenshot-1.jpg\""))
        XCTAssertTrue(body.contains("name=\"images\"; filename=\"screenshot-2.jpg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
    }

    func testNoMoreThanFourScreenshotsAreAttached() async throws {
        let analysis = #"{"mode":"demo","provider":"demo","model":null,"usage":\#(usage),"result":{"canReply":true,"read":"ok"}}"#
        let transport = MockTransport([.response(status: 200, body: analysis)])
        let images = (0..<6).map { Data([0xFF, 0xD8, UInt8($0)]) }
        _ = try await makeClient(transport).analyze(AnalyzeRequest(conversation: ""), images: images)

        let body = String(decoding: try XCTUnwrap(transport.requests.first?.httpBody), as: UTF8.self)
        XCTAssertEqual(body.components(separatedBy: "name=\"images\"").count - 1, RequestLimits.maxImages)
    }

    func testStatusIsAGetRequest() async throws {
        let status = #"{"apiVersion":1,"mode":"demo","provider":"demo","supportsImages":false,"plans":{"free":{"dailyGenerations":10,"dailyCoachMessages":3,"intents":["natural"],"voiceSamples":false},"pro":{"dailyGenerations":400,"dailyCoachMessages":200,"intents":["natural"],"voiceSamples":true}},"usage":\#(usage)}"#
        let transport = MockTransport([.response(status: 200, body: status)])
        let response = try await makeClient(transport).status()
        XCTAssertEqual(response.mode, .demo)
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/v1/status")
        XCTAssertNil(transport.requests.first?.httpBody)
    }

    // MARK: Error mapping

    func testPlanErrorsCarryUsage() async throws {
        let expectedUsage = try JSONDecoder().decode(Usage.self, from: Data(usage.utf8))

        let limit = MockTransport([.response(status: 402, body: errorBody("limit_reached", message: "That's today's free replies.", withUsage: true))])
        await assertThrows(.limitReached(message: "That's today's free replies.", usage: expectedUsage)) {
            _ = try await self.makeClient(limit).replies(RepliesRequest(conversation: "hi"))
        }

        let upgrade = MockTransport([.response(status: 402, body: errorBody("upgrade_required", message: "Part of Pro."))])
        await assertThrows(.upgradeRequired(message: "Part of Pro.", usage: nil)) {
            _ = try await self.makeClient(upgrade).replies(RepliesRequest(conversation: "hi", intent: .askOut))
        }

        XCTAssertTrue(APIError.limitReached(message: "", usage: nil).suggestsUpgrade)
        XCTAssertTrue(APIError.upgradeRequired(message: "", usage: nil).suggestsUpgrade)
        XCTAssertFalse(APIError.offline.suggestsUpgrade)
    }

    func testServerErrorCodesMapToTypedErrors() async {
        let cases: [(status: Int, code: String, headers: [String: String], expected: APIError)] = [
            (429, "rate_limited", ["Retry-After": "12"], .rateLimited(retryAfter: 12)),
            (422, "ai_declined", [:], .declined(message: "Something happened.")),
            (400, "invalid_request", [:], .invalid(message: "Something happened.")),
            (400, "unsupported_media", [:], .invalid(message: "Something happened.")),
            (413, "payload_too_large", [:], .invalid(message: "Something happened.")),
            (502, "ai_bad_output", [:], .unavailable(message: "Something happened.")),
            (500, "internal", [:], .server(message: "Something happened.")),
        ]
        for item in cases {
            let transport = MockTransport([.response(status: item.status, body: errorBody(item.code), headers: item.headers)])
            await assertThrows(item.expected) {
                _ = try await self.makeClient(transport, maxRetries: 0).refine(RefineRequest(text: "hey", action: .shorter))
            }
        }
    }

    func testUnreadableErrorBodiesStillProduceAFriendlyError() async {
        let transport = MockTransport([.response(status: 500, body: "<html>Bad gateway</html>")])
        await assertThrows(.server(message: "Something went wrong on our side. Please try again.")) {
            _ = try await self.makeClient(transport).coach(CoachRequest(messages: [CoachTurn(role: .user, text: "hi")]))
        }
    }

    func testGarbledSuccessBodyIsReported() async {
        let transport = MockTransport([.response(status: 200, body: "not json")])
        await assertThrows(.unexpectedResponse) {
            _ = try await self.makeClient(transport).replies(RepliesRequest(conversation: "hi"))
        }
    }

    func testConnectionProblemsMapToFriendlyErrors() async {
        let offline = MockTransport([.failure(.notConnectedToInternet)])
        await assertThrows(.offline) {
            _ = try await self.makeClient(offline).status()
        }
        let slow = MockTransport([.failure(.timedOut)])
        await assertThrows(.timedOut) {
            _ = try await self.makeClient(slow).status()
        }
        let cancelled = MockTransport([.failure(.cancelled)])
        await assertThrows(.cancelled) {
            _ = try await self.makeClient(cancelled).status()
        }
    }

    func testAServerThatCannotBeReachedIsToldApartFromBeingOffline() async {
        let cases: [(URLError.Code, APIError.Unreachable)] = [
            (.cannotConnectToHost, .refused),
            (.cannotFindHost, .hostNotFound),
            (.dnsLookupFailed, .hostNotFound),
            (.appTransportSecurityRequiresSecureConnection, .blockedInsecure),
            (.secureConnectionFailed, .secureConnectionFailed),
            (.serverCertificateUntrusted, .secureConnectionFailed),
            (.badURL, .other),
        ]
        for (code, expected) in cases {
            let transport = MockTransport([.failure(code)])
            await assertThrows(.serverUnreachable(expected)) {
                _ = try await self.makeClient(transport, maxRetries: 0).status()
            }
        }
        XCTAssertTrue(APIError.serverUnreachable(.refused).isConnectionProblem)
        XCTAssertTrue(APIError.serverUnreachable(.refused).isRetryable)
        XCTAssertFalse(APIError.declined(message: "no").isRetryable)
        XCTAssertFalse(APIError.limitReached(message: "m", usage: nil).isConnectionProblem)
    }

    func testSomethingElseAnsweringIsNotMistakenForReplyRight() async {
        let notFound = MockTransport([.response(status: 404, body: "<html>Cannot GET /api/v1/status</html>")])
        await assertThrows(.unexpectedResponse) {
            _ = try await self.makeClient(notFound).status()
        }
        let tooLarge = MockTransport([.response(status: 413, body: "Request Entity Too Large")])
        do {
            _ = try await makeClient(tooLarge).analyze(AnalyzeRequest(conversation: "hi"))
            XCTFail("Expected an error")
        } catch let error as APIError {
            guard case .invalid = error else { return XCTFail("Expected .invalid, got \(error)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSetupHintsSayWhatToCheck() {
        let local = BackendTarget(url: URL(string: "http://localhost:3000")!, environment: .development, source: .build)
        let remote = BackendTarget(url: URL(string: "https://api.example.com")!, environment: .production, source: .build)
        let lan = BackendTarget(url: URL(string: "http://192.168.1.20:3000")!, environment: nil, source: .custom)

        XCTAssertTrue(local.isLoopback)
        XCTAssertTrue(local.isLocal)
        XCTAssertFalse(lan.isLoopback)
        XCTAssertTrue(lan.isLocal)
        XCTAssertFalse(remote.isLocal)
        XCTAssertEqual(local.displayAddress, "http://localhost:3000")
        XCTAssertEqual(remote.displayAddress, "https://api.example.com")
        XCTAssertEqual(lan.label, "Custom address")

        let refused = APIError.serverUnreachable(.refused)
        XCTAssertTrue(refused.setupHint(for: local)?.contains("npm run dev") == true)
        XCTAssertTrue(refused.setupHint(for: local)?.contains("real iPhone") == true)
        XCTAssertFalse(refused.setupHint(for: remote)?.contains("npm run dev") == true)
        XCTAssertTrue(APIError.serverUnreachable(.blockedInsecure).setupHint(for: remote)?.contains("https") == true)
        XCTAssertNil(APIError.limitReached(message: "m", usage: nil).setupHint(for: local))
        XCTAssertFalse(refused.userMessage.contains("npm"), "What the user reads never contains setup instructions")
    }

    // MARK: Diagnostics

    func testRequestsAreLoggedWithoutAnyOfTheirContent() async throws {
        let log = DiagnosticsLog()
        let transport = MockTransport([
            .response(status: 200, body: repliesBody, headers: ["X-RR-Request": "req-123"]),
            .response(
                status: 503,
                body: #"{"error":{"code":"ai_unavailable","message":"Not set up.","reason":"credentials"}}"#,
                headers: ["X-RR-Request": "req-456"]
            ),
            .failure(.cannotConnectToHost),
        ])
        let client = makeClient(transport, maxRetries: 0, log: log)
        let secret = "SECRET-CONVERSATION-TEXT"

        _ = try await client.replies(RepliesRequest(conversation: secret), images: [Data([0xFF, 0xD8, 0xFF])])
        _ = try? await client.refine(RefineRequest(text: secret, action: .shorter))
        _ = try? await client.status()

        let records = log.records
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map(\.endpoint), ["status", "refine", "replies"], "Newest first")

        let replies = records[2]
        XCTAssertTrue(replies.succeeded)
        XCTAssertEqual(replies.status, 200)
        XCTAssertEqual(replies.mode, "live")
        XCTAssertEqual(replies.requestID, "req-123")
        XCTAssertEqual(replies.imageCount, 1)
        XCTAssertEqual(replies.host, "api.example.test")
        XCTAssertGreaterThan(replies.bytesSent, 0)

        let refine = records[1]
        XCTAssertFalse(refine.succeeded)
        XCTAssertEqual(refine.outcome, "ai_unavailable")
        XCTAssertEqual(refine.reason, "credentials")
        XCTAssertEqual(refine.requestID, "req-456")

        let status = records[0]
        XCTAssertNil(status.status)
        XCTAssertEqual(status.outcome, "unreachable.refused")
        XCTAssertEqual(log.lastFailure?.endpoint, "status")

        let target = BackendTarget(url: URL(string: "https://api.example.test")!, environment: .staging, source: .chosen)
        let report = log.report(target: target, state: .unreachable(.serverUnreachable(.refused)))
        XCTAssertFalse(report.contains(secret))
        XCTAssertFalse(report.contains("signed.transaction.token"))
        XCTAssertFalse(report.contains("3f2504e0"), "The install id is not part of a report")
        XCTAssertTrue(report.contains("req-456"))
        XCTAssertTrue(report.contains("Staging"))

        log.clear()
        XCTAssertTrue(log.records.isEmpty)
    }

    func testTheLogKeepsOnlyTheMostRecentRequests() {
        let log = DiagnosticsLog()
        for index in 0..<(DiagnosticsLog.capacity + 10) {
            log.add(RequestRecord(endpoint: "status", host: "h", status: 200, durationMs: index, outcome: "ok"))
        }
        XCTAssertEqual(log.records.count, DiagnosticsLog.capacity)
        XCTAssertEqual(log.records.first?.durationMs, DiagnosticsLog.capacity + 9)
    }

    func testTheProbeIsAPostThatSendsNothing() async throws {
        let transport = MockTransport([.response(status: 200, body: #"{"ok":true,"mode":"live","model":"claude-opus-5-5","latencyMs":1840,"reason":null}"#)])
        let result = try await makeClient(transport).probe()
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.mode, .live)
        XCTAssertEqual(result.latencyMs, 1840)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/diagnostics/probe")
        XCTAssertNil(request.httpBody)
    }

    // MARK: Retries

    func testADroppedConnectionIsRetriedOnce() async throws {
        let transport = MockTransport([
            .failure(.networkConnectionLost),
            .response(status: 200, body: repliesBody),
        ])
        let envelope = try await makeClient(transport).replies(RepliesRequest(conversation: "hi"))
        XCTAssertEqual(envelope.result.replies.count, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testOneRetryAfterATransientFailure() async throws {
        let transport = MockTransport([
            .response(status: 503, body: errorBody("ai_unavailable")),
            .response(status: 200, body: repliesBody),
        ])
        let envelope = try await makeClient(transport).replies(RepliesRequest(conversation: "hi"))
        XCTAssertEqual(envelope.result.replies.count, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testNoAutomaticRetryWhenTheServerSaysARepeatCouldCostAnotherAICall() async {
        let transport = MockTransport([
            .response(status: 502, body: errorBody("ai_bad_output", message: "Garbled."), headers: ["X-RR-Retry": "no"]),
            .response(status: 200, body: repliesBody),
        ])
        await assertThrows(.unavailable(message: "Garbled.")) {
            _ = try await self.makeClient(transport, maxRetries: 1).replies(RepliesRequest(conversation: "hi"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRetriesStopAtTheLimit() async {
        let transport = MockTransport([
            .response(status: 503, body: errorBody("ai_unavailable", message: "Busy.")),
            .response(status: 503, body: errorBody("ai_unavailable", message: "Busy.")),
            .response(status: 200, body: repliesBody),
        ])
        await assertThrows(.unavailable(message: "Busy.")) {
            _ = try await self.makeClient(transport, maxRetries: 1).replies(RepliesRequest(conversation: "hi"))
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testClientErrorsAreNotRetried() async {
        let transport = MockTransport([
            .response(status: 400, body: errorBody("invalid_request")),
            .response(status: 200, body: repliesBody),
        ])
        await assertThrows(.invalid(message: "Something happened.")) {
            _ = try await self.makeClient(transport).replies(RepliesRequest(conversation: "hi"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testEveryErrorHasSomethingToSay() {
        let errors: [APIError] = [
            .offline, .timedOut, .cancelled, .rateLimited(retryAfter: nil), .limitReached(message: "m", usage: nil),
            .upgradeRequired(message: "m", usage: nil), .declined(message: "m"), .invalid(message: "m"),
            .unavailable(message: "m"), .server(message: "m"), .unexpectedResponse,
            .serverUnreachable(.refused), .serverUnreachable(.hostNotFound), .serverUnreachable(.blockedInsecure),
            .serverUnreachable(.secureConnectionFailed), .serverUnreachable(.connectionLost), .serverUnreachable(.other),
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty)
            XCTAssertFalse(error.title.isEmpty)
            XCTAssertFalse(error.diagnosticCode.isEmpty)
            XCTAssertFalse(error.diagnosticCode.contains(" "), "Codes are single tokens")
        }
    }
}
