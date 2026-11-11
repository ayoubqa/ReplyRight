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

    private func makeClient(_ transport: MockTransport, maxRetries: Int = 1) -> APIClient {
        APIClient(
            configuration: APIClient.Configuration(
                baseURL: { URL(string: "https://api.example.test")! },
                clientName: "ios-test/1.0.0",
                installID: { "3f2504e0-4f89-41d3-9a0c-0305e82c3301" },
                entitlementToken: { "signed.transaction.token" },
                maxRetries: maxRetries,
                retryDelay: 0
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

    // MARK: Retries

    func testOneRetryAfterATransientFailure() async throws {
        let transport = MockTransport([
            .response(status: 503, body: errorBody("ai_unavailable")),
            .response(status: 200, body: repliesBody),
        ])
        let envelope = try await makeClient(transport).replies(RepliesRequest(conversation: "hi"))
        XCTAssertEqual(envelope.result.replies.count, 1)
        XCTAssertEqual(transport.requests.count, 2)
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
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty)
        }
    }
}
