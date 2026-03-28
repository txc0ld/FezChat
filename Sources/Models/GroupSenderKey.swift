import Foundation
import SwiftData

/// GroupSenderKey tracks the symmetric sender key material for group encryption.
/// The actual keyMaterial (32-byte AES-256-GCM key) should be stored in the Keychain
/// for security. This model stores the metadata and a reference for key lookup.
@Model
final class GroupSenderKey {
    @Attribute(.unique)
    var id: UUID

    var channel: Channel?
    var memberPeerID: Data
    var keyMaterial: Data
    var messageCounter: UInt64
    var rotationEpoch: Int
    var createdAt: Date

    // MARK: - Computed Properties

    /// Whether this key needs rotation based on message count (every 100 messages).
    var needsRotation: Bool {
        messageCounter >= 100
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        channel: Channel? = nil,
        memberPeerID: Data,
        keyMaterial: Data,
        messageCounter: UInt64 = 0,
        rotationEpoch: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.channel = channel
        self.memberPeerID = memberPeerID
        self.keyMaterial = keyMaterial
        self.messageCounter = messageCounter
        self.rotationEpoch = rotationEpoch
        self.createdAt = createdAt
    }
}
