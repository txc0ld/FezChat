import Foundation
import SwiftData

/// NoiseSessionModel stores the persistable metadata for Noise protocol sessions.
///
/// Per the spec, this is a hybrid model:
/// - Metadata (peerID, handshake state, static key, timestamps) persisted to SwiftData and Keychain
/// - Cipher states (sendCipher, receiveCipher) are memory-only and transient
/// - messageCounter and rekeyAt are memory-only, lost on termination
///
/// On app termination/restoration:
/// - If peerStaticKeyKnown == true and session not expired: fast IK handshake (2 messages)
/// - If unknown or expired: full XX handshake (3 messages)
@Model
final class NoiseSessionModel {
    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var peerID: Data

    var handshakeComplete: Bool
    var peerStaticKeyKnown: Bool
    var peerStaticKey: Data?
    var establishedAt: Date
    var expiresAt: Date

    // MARK: - Transient (memory-only) properties
    // These are NOT persisted by SwiftData.
    // They must be rebuilt after app restoration.

    @Transient
    var messageCounter: UInt64 = 0

    @Transient
    var rekeyAt: UInt64 = 0

    @Transient
    var sendCipherState: (any Sendable)? = nil

    @Transient
    var receiveCipherState: (any Sendable)? = nil

    // MARK: - Computed Properties

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isValid: Bool {
        handshakeComplete && !isExpired
    }

    /// Determines whether a fast IK handshake can be used on reconnect
    /// instead of a full XX handshake.
    var canUseIKHandshake: Bool {
        peerStaticKeyKnown && !isExpired
    }

    var needsRekey: Bool {
        messageCounter >= rekeyAt && rekeyAt > 0
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        peerID: Data,
        handshakeComplete: Bool = false,
        peerStaticKeyKnown: Bool = false,
        peerStaticKey: Data? = nil,
        establishedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.peerID = peerID
        self.handshakeComplete = handshakeComplete
        self.peerStaticKeyKnown = peerStaticKeyKnown
        self.peerStaticKey = peerStaticKey
        self.establishedAt = establishedAt
        self.expiresAt = expiresAt ?? establishedAt.addingTimeInterval(14_400) // 4 hours
    }
}
