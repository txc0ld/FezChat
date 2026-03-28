import Foundation
import CryptoKit

// MARK: - Verification Error

enum PhoneVerificationError: Error, Sendable {
    case invalidPhoneNumber
    case rateLimited(retryAfter: TimeInterval)
    case networkUnavailable
    case serverError(Int, String)
    case invalidOTPCode
    case otpExpired
    case maxAttemptsExceeded
    case verificationFailed(String)
    case alreadyVerified
    case requestInProgress
}

// MARK: - Verification State

enum VerificationState: Sendable, Equatable {
    /// No verification in progress.
    case idle
    /// OTP has been requested; waiting for user input.
    case codeSent(phoneNumber: String, expiresAt: Date)
    /// User submitted code; verifying with backend.
    case verifying
    /// Phone has been verified successfully.
    case verified
    /// Verification failed.
    case failed(String)
}

// MARK: - Phone Verification Service

/// Manages the SMS OTP verification flow.
///
/// Flow:
/// 1. User enters phone number (E.164 format)
/// 2. Service sends verification request to backend (Twilio Verify / Firebase Auth)
/// 3. User enters received OTP code
/// 4. Service verifies code with backend
/// 5. On success: store phone hash in SwiftData, raw number in Keychain
///
/// Security:
/// - Phone number stored in Keychain only (raw)
/// - SHA256(phone + per_user_salt) stored in SwiftData for friend matching
/// - Raw phone never transmitted, never displayed, never logged
final class PhoneVerificationService: @unchecked Sendable {

    // MARK: - Constants

    /// Backend API base URL.
    private static let apiBaseURL = "https://api.festichat.app/v1"

    /// OTP code length (6 digits).
    private static let otpLength = 6

    /// OTP expiration time (5 minutes).
    private static let otpExpiration: TimeInterval = 300

    /// Maximum verification attempts before lockout.
    private static let maxVerificationAttempts = 5

    /// Cooldown between OTP send requests (60 seconds).
    private static let sendCooldown: TimeInterval = 60

    /// Maximum OTP send requests per hour.
    private static let maxSendsPerHour = 5

    /// Keychain service tag for storing the raw phone number.
    private static let phoneKeychainTag = "com.festichat.phone.raw"

    /// Keychain service tag for the verification token.
    private static let verificationTokenTag = "com.festichat.phone.verificationToken"

    // MARK: - Properties

    /// Current verification state.
    private(set) var state: VerificationState = .idle

    /// Number of verification attempts remaining.
    private(set) var attemptsRemaining: Int = maxVerificationAttempts

    /// Time remaining until next send is allowed.
    private(set) var sendCooldownRemaining: TimeInterval = 0

    // MARK: - Private State

    private var lastSendTime: Date?
    private var sendCountThisHour = 0
    private var hourWindowStart: Date = Date()
    private var verificationID: String?
    private var currentPhoneNumber: String?
    private let urlSession: URLSession
    private let lock = NSLock()

    // MARK: - Init

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Send OTP

    /// Request an OTP code to be sent to the specified phone number.
    ///
    /// - Parameter phoneNumber: Phone number in E.164 format (e.g., "+14155552671").
    func sendVerificationCode(to phoneNumber: String) async throws {
        // Validate phone number format
        guard isValidE164(phoneNumber) else {
            throw PhoneVerificationError.invalidPhoneNumber
        }

        // Check rate limits
        try checkSendRateLimit()

        // Check if already in progress
        lock.lock()
        let currentState = state
        lock.unlock()

        if case .verifying = currentState {
            throw PhoneVerificationError.requestInProgress
        }

        // Send request to backend
        let request = buildSendRequest(phoneNumber: phoneNumber)
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhoneVerificationError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            // Parse response for verification ID
            let decoded = try JSONDecoder().decode(SendOTPResponse.self, from: data)

            lock.lock()
            verificationID = decoded.verificationID
            currentPhoneNumber = phoneNumber
            lastSendTime = Date()
            sendCountThisHour += 1
            attemptsRemaining = Self.maxVerificationAttempts
            state = .codeSent(
                phoneNumber: maskPhoneNumber(phoneNumber),
                expiresAt: Date().addingTimeInterval(Self.otpExpiration)
            )
            lock.unlock()

        case 429:
            let retryAfter = TimeInterval(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw PhoneVerificationError.rateLimited(retryAfter: retryAfter)

        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PhoneVerificationError.serverError(httpResponse.statusCode, body)
        }
    }

    // MARK: - Verify OTP

    /// Verify the OTP code entered by the user.
    ///
    /// - Parameter code: The 6-digit OTP code.
    /// - Returns: The phone hash (SHA256) to store in SwiftData.
    func verifyCode(_ code: String) async throws -> String {
        // Validate code format
        guard code.count == Self.otpLength, code.allSatisfy(\.isNumber) else {
            throw PhoneVerificationError.invalidOTPCode
        }

        lock.lock()
        guard let verificationID, let phoneNumber = currentPhoneNumber else {
            lock.unlock()
            throw PhoneVerificationError.verificationFailed("No active verification session")
        }

        guard attemptsRemaining > 0 else {
            lock.unlock()
            throw PhoneVerificationError.maxAttemptsExceeded
        }

        // Check expiration
        if case .codeSent(_, let expiresAt) = state, Date() > expiresAt {
            state = .failed("Code expired")
            lock.unlock()
            throw PhoneVerificationError.otpExpired
        }

        attemptsRemaining -= 1
        state = .verifying
        lock.unlock()

        // Verify with backend
        let request = buildVerifyRequest(verificationID: verificationID, code: code)
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            lock.lock()
            state = .failed("Network error")
            lock.unlock()
            throw PhoneVerificationError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            let decoded = try JSONDecoder().decode(VerifyOTPResponse.self, from: data)

            guard decoded.verified else {
                lock.lock()
                state = .failed("Verification rejected")
                lock.unlock()
                throw PhoneVerificationError.invalidOTPCode
            }

            // Store raw phone number in Keychain
            storePhoneInKeychain(phoneNumber)

            // Compute and return phone hash
            let hash = try computePhoneHash(phoneNumber)

            // Store verification token if provided
            if let token = decoded.token {
                storeVerificationToken(token)
            }

            lock.lock()
            state = .verified
            self.verificationID = nil
            self.currentPhoneNumber = nil
            lock.unlock()

            return hash

        case 400:
            lock.lock()
            state = .codeSent(
                phoneNumber: maskPhoneNumber(phoneNumber),
                expiresAt: Date().addingTimeInterval(Self.otpExpiration)
            )
            lock.unlock()
            throw PhoneVerificationError.invalidOTPCode

        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            lock.lock()
            state = .failed("Server error: \(httpResponse.statusCode)")
            lock.unlock()
            throw PhoneVerificationError.serverError(httpResponse.statusCode, body)
        }
    }

    // MARK: - Resend OTP

    /// Resend the OTP code to the same phone number.
    func resendCode() async throws {
        lock.lock()
        guard let phoneNumber = currentPhoneNumber else {
            lock.unlock()
            throw PhoneVerificationError.verificationFailed("No active verification session")
        }
        lock.unlock()

        try await sendVerificationCode(to: phoneNumber)
    }

    // MARK: - Cancel

    /// Cancel the current verification flow.
    func cancel() {
        lock.lock()
        state = .idle
        verificationID = nil
        currentPhoneNumber = nil
        lock.unlock()
    }

    // MARK: - Phone Hash

    /// Compute the phone hash using the user's salt.
    ///
    /// `SHA256(phone_e164 + per_user_salt)`
    func computePhoneHash(_ phoneNumber: String) throws -> String {
        let salt = try loadOrCreatePhoneSalt()
        let input = phoneNumber + salt.base64EncodedString()
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Stored Phone Access

    /// Check if a phone number is already verified and stored.
    var hasVerifiedPhone: Bool {
        loadPhoneFromKeychain() != nil
    }

    /// Load the stored phone hash from Keychain (for re-verification scenarios).
    func loadStoredPhoneHash() throws -> String? {
        guard let phone = loadPhoneFromKeychain() else { return nil }
        return try computePhoneHash(phone)
    }

    // MARK: - Private: Request Building

    private struct SendOTPResponse: Codable {
        let verificationID: String
        let expiresIn: Int?
    }

    private struct VerifyOTPResponse: Codable {
        let verified: Bool
        let token: String?
    }

    private func buildSendRequest(phoneNumber: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.apiBaseURL)/verify/send")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["phone": phoneNumber]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func buildVerifyRequest(verificationID: String, code: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.apiBaseURL)/verify/check")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "verificationID": verificationID,
            "code": code
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw PhoneVerificationError.networkUnavailable
        }
    }

    // MARK: - Private: Phone Number Validation

    private func isValidE164(_ phone: String) -> Bool {
        // E.164: starts with +, 7-15 digits total
        guard phone.hasPrefix("+") else { return false }
        let digits = phone.dropFirst()
        guard digits.count >= 7, digits.count <= 15 else { return false }
        return digits.allSatisfy(\.isNumber)
    }

    private func maskPhoneNumber(_ phone: String) -> String {
        guard phone.count > 4 else { return "****" }
        let lastFour = phone.suffix(4)
        let masked = String(repeating: "*", count: phone.count - 4) + lastFour
        return masked
    }

    // MARK: - Private: Rate Limiting

    private func checkSendRateLimit() throws {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()

        // Reset hourly counter if window expired
        if now.timeIntervalSince(hourWindowStart) > 3600 {
            hourWindowStart = now
            sendCountThisHour = 0
        }

        // Check hourly limit
        if sendCountThisHour >= Self.maxSendsPerHour {
            throw PhoneVerificationError.rateLimited(retryAfter: 3600 - now.timeIntervalSince(hourWindowStart))
        }

        // Check per-request cooldown
        if let lastSend = lastSendTime {
            let elapsed = now.timeIntervalSince(lastSend)
            if elapsed < Self.sendCooldown {
                throw PhoneVerificationError.rateLimited(retryAfter: Self.sendCooldown - elapsed)
            }
        }
    }

    // MARK: - Private: Keychain Storage

    private func storePhoneInKeychain(_ phone: String) {
        guard let data = phone.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.phoneKeychainTag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.phoneKeychainTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadPhoneFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.phoneKeychainTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func storeVerificationToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.verificationTokenTag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.verificationTokenTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadOrCreatePhoneSalt() throws -> Data {
        let tag = "com.festichat.phone.salt"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return data
        }

        // Generate new 32-byte salt
        var salt = Data(count: 32)
        salt.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr)
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecValueData as String: salt,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        return salt
    }
}
