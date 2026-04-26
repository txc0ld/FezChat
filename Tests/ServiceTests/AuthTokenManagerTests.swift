import XCTest
@testable import Blip
@testable import BlipCrypto

// Tests for AuthTokenManager.refreshToken() grace-window fallback.
//
// The server rejects /auth/refresh with 401 when the token has been expired
// for more than refreshGraceSeconds (300s). Before this fix the client would
// send the doomed request anyway. After the fix it detects the over-grace
// condition locally and falls back to re-authentication.
@MainActor
final class AuthTokenManagerTests: XCTestCase {

    // MARK: - Grace window fallback

    func testRefreshToken_expiredBeyondGrace_takesReauthPath() async {
        let keyManager = KeyManager(keyStore: InMemoryKeyManagerStore())
        let manager = AuthTokenManager(keyManager: keyManager)
        // Token expired 400s ago — beyond the 300s server grace window.
        manager.setStoredTokenForTesting(
            token: "header.payload.signature",
            expiresAt: Date().addingTimeInterval(-400)
        )

        do {
            try await manager.refreshIfNeeded(force: true)
            XCTFail("Expected an error from the re-auth path")
        } catch let error as AuthTokenManager.AuthError {
            // No identity was seeded, so re-auth fails with missingIdentity,
            // proving the code took the re-auth branch rather than hitting
            // /auth/refresh (which would 401 from the server).
            guard case .missingIdentity = error else {
                XCTFail("Expected missingIdentity, got: \(error)")
                return
            }
        } catch {
            XCTFail("Expected AuthError.missingIdentity, got: \(error)")
        }
    }

    func testRefreshToken_expiredWithinGrace_attemptsRefresh() async {
        let keyManager = KeyManager(keyStore: InMemoryKeyManagerStore())
        let manager = AuthTokenManager(keyManager: keyManager)
        // Token expired 60s ago — still within the 300s grace window.
        manager.setStoredTokenForTesting(
            token: "header.payload.signature",
            expiresAt: Date().addingTimeInterval(-60)
        )

        do {
            try await manager.refreshIfNeeded(force: true)
            XCTFail("Expected a network/server error")
        } catch let error as AuthTokenManager.AuthError {
            // Should be a serverError or unauthorized from attempting the real
            // /auth/refresh endpoint — NOT missingIdentity (which would indicate
            // it wrongly fell back to re-auth when the token is still refreshable).
            if case .missingIdentity = error {
                XCTFail("Should not have taken re-auth path for token within grace window")
            }
        } catch {
            // URLError or similar from a failed network call is expected and acceptable here.
        }
    }

    func testRefreshIfNeeded_tokenFresh_skipsRefresh() async throws {
        let keyManager = KeyManager(keyStore: InMemoryKeyManagerStore())
        let manager = AuthTokenManager(keyManager: keyManager)
        // Token expires in 600s — well outside the refreshThreshold (300s).
        manager.setStoredTokenForTesting(
            token: "header.payload.signature",
            expiresAt: Date().addingTimeInterval(600)
        )

        // Should return without hitting the network or re-auth.
        try await manager.refreshIfNeeded()
    }

    // MARK: - Single-flight, back-off, cancel-on-pop

    private func makeMockedManager() -> AuthTokenManager {
        let keyManager = KeyManager(keyStore: InMemoryKeyManagerStore())
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return AuthTokenManager(keyManager: keyManager, urlSession: session, keychainEnabled: false)
    }

    func testValidToken_concurrentCallsDuringRefreshWindow_singleFlightCoalesces() async throws {
        await MockURLProtocol.reset()
        defer { Task { await MockURLProtocol.reset() } }

        let manager = makeMockedManager()
        // Token in refresh window (less than 300s left).
        manager.setStoredTokenForTesting(
            token: "header.payload.old",
            expiresAt: Date().addingTimeInterval(60)
        )

        let futureExpiry = ISO8601DateFormatter.blipFormatter
            .string(from: Date().addingTimeInterval(3600))
        await MockURLProtocol.setHandler { request in
            // Hold a moment so concurrent callers all enqueue while the first refresh is in flight.
            try? await Task.sleep(nanoseconds: 50_000_000)
            return MockURLProtocol.Response(
                statusCode: 200,
                body: """
                {"token":"header.payload.new","expiresAt":"\(futureExpiry)"}
                """.data(using: .utf8)!
            )
        }

        async let r1 = manager.validToken()
        async let r2 = manager.validToken()
        async let r3 = manager.validToken()
        async let r4 = manager.validToken()
        async let r5 = manager.validToken()

        let tokens = try await [r1, r2, r3, r4, r5]
        for token in tokens {
            XCTAssertEqual(token, "header.payload.new")
        }

        let count = await MockURLProtocol.requestCount(forPathSuffix: "/auth/refresh")
        XCTAssertEqual(count, 1, "expected single-flight to coalesce concurrent refreshes")
    }

    func testValidToken_after401_subsequentCallsBackOffWithoutNetwork() async throws {
        await MockURLProtocol.reset()
        defer { Task { await MockURLProtocol.reset() } }

        let manager = makeMockedManager()
        manager.setStoredTokenForTesting(
            token: "header.payload.old",
            expiresAt: Date().addingTimeInterval(60)
        )

        await MockURLProtocol.setHandler { _ in
            MockURLProtocol.Response(
                statusCode: 401,
                body: #"{"error":"invalid_token"}"#.data(using: .utf8)!
            )
        }

        // First call: should attempt /auth/refresh and surface 401 → back-off armed.
        do {
            _ = try await manager.validToken()
            XCTFail("Expected unauthorized error")
        } catch let error as AuthTokenManager.AuthError {
            guard case .unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected AuthError.unauthorized, got \(error)")
        }

        let countAfterFirst = await MockURLProtocol.requestCount(forPathSuffix: "/auth/refresh")
        XCTAssertEqual(countAfterFirst, 1, "first refresh should hit the network exactly once")

        // Second call (immediately): should fail fast with NO network round-trip.
        do {
            _ = try await manager.validToken()
            XCTFail("Expected back-off to throw")
        } catch let error as AuthTokenManager.AuthError {
            guard case .unauthorized(let detail) = error else {
                XCTFail("Expected unauthorized back-off, got \(error)")
                return
            }
            XCTAssertTrue(
                detail.contains("backing off"),
                "expected back-off message, got: \(detail)"
            )
        } catch {
            XCTFail("Expected AuthError.unauthorized, got \(error)")
        }

        let countAfterSecond = await MockURLProtocol.requestCount(forPathSuffix: "/auth/refresh")
        XCTAssertEqual(countAfterSecond, 1, "back-off should suppress second network call")
    }

    func testClear_midRefresh_cancelsInFlightAndDropsResponse() async throws {
        await MockURLProtocol.reset()
        defer { Task { await MockURLProtocol.reset() } }

        let manager = makeMockedManager()
        manager.setStoredTokenForTesting(
            token: "header.payload.old",
            expiresAt: Date().addingTimeInterval(60)
        )

        let futureExpiry = ISO8601DateFormatter.blipFormatter
            .string(from: Date().addingTimeInterval(3600))
        let gate = AsyncGate()

        await MockURLProtocol.setHandler { _ in
            // Block here until the test releases us — gives clear() a window to land mid-flight.
            await gate.wait()
            return MockURLProtocol.Response(
                statusCode: 200,
                body: """
                {"token":"header.payload.new","expiresAt":"\(futureExpiry)"}
                """.data(using: .utf8)!
            )
        }

        let refreshTask = Task<Void, Never> {
            do {
                try await manager.refreshIfNeeded()
                XCTFail("Expected refresh to be cancelled")
            } catch {
                // Cancellation or session error is fine — we just want the in-flight task to terminate.
            }
        }

        // Give the refresh a tick to be in-flight.
        try await Task.sleep(nanoseconds: 50_000_000)

        try manager.clear()

        // Release the mocked network response AFTER clear() so the response would
        // otherwise re-store a token if cancellation isn't honoured.
        await gate.release()

        _ = await refreshTask.value

        // Allow any trailing continuation to drain.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(manager.currentToken, "clear() must keep currentToken nil even after the in-flight response resolves")
        XCTAssertNil(manager.tokenExpiresAt)
    }
}

// MARK: - Test helpers

private extension ISO8601DateFormatter {
    static let blipFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor MockURLProtocolState {
    var handler: (@Sendable (URLRequest) async -> MockURLProtocol.Response)?
    var requests: [URLRequest] = []

    func setHandler(_ handler: @escaping @Sendable (URLRequest) async -> MockURLProtocol.Response) {
        self.handler = handler
    }

    func reset() {
        handler = nil
        requests = []
    }

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func currentHandler() -> (@Sendable (URLRequest) async -> MockURLProtocol.Response)? {
        handler
    }

    func requestCount(forPathSuffix suffix: String) -> Int {
        requests.filter { $0.url?.path.hasSuffix(suffix) ?? false }.count
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        let statusCode: Int
        let body: Data
    }

    private static let state = MockURLProtocolState()

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) async -> Response) async {
        await state.setHandler(handler)
    }

    static func reset() async {
        await state.reset()
    }

    static func requestCount(forPathSuffix suffix: String) async -> Int {
        await state.requestCount(forPathSuffix: suffix)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        Task {
            await MockURLProtocol.state.record(request)
            guard let handler = await MockURLProtocol.state.currentHandler() else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let response = await handler(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
