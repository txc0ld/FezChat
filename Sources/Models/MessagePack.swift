import Foundation
import SwiftData

// MARK: - Enums

enum PackType: String, Codable, CaseIterable {
    case starter10
    case social25
    case festival50
    case squad100
    case season1000
    case unlimited

    var messageCount: Int {
        switch self {
        case .starter10: return 10
        case .social25: return 25
        case .festival50: return 50
        case .squad100: return 100
        case .season1000: return 1000
        case .unlimited: return Int.max
        }
    }

    var displayName: String {
        switch self {
        case .starter10: return "Starter"
        case .social25: return "Social"
        case .festival50: return "Festival"
        case .squad100: return "Squad"
        case .season1000: return "Season Pass"
        case .unlimited: return "Unlimited"
        }
    }
}

// MARK: - Model

@Model
final class MessagePack {
    @Attribute(.unique)
    var id: UUID

    var packTypeRaw: String
    var messagesRemaining: Int
    var purchaseDate: Date
    var transactionID: String

    // MARK: - Computed Properties

    var packType: PackType {
        get { PackType(rawValue: packTypeRaw) ?? .starter10 }
        set { packTypeRaw = newValue.rawValue }
    }

    var isExhausted: Bool {
        messagesRemaining <= 0 && packType != .unlimited
    }

    var isUnlimited: Bool {
        packType == .unlimited
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        packType: PackType,
        messagesRemaining: Int? = nil,
        purchaseDate: Date = Date(),
        transactionID: String
    ) {
        self.id = id
        self.packTypeRaw = packType.rawValue
        self.messagesRemaining = messagesRemaining ?? packType.messageCount
        self.purchaseDate = purchaseDate
        self.transactionID = transactionID
    }
}
