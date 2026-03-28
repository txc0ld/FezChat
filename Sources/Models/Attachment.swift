import Foundation
import SwiftData

// MARK: - Enums

enum AttachmentType: String, Codable, CaseIterable {
    case image
    case voiceNote
    case pttRecording
    case profilePhoto
}

// MARK: - Model

@Model
final class Attachment {
    @Attribute(.unique)
    var id: UUID

    var message: Message?
    var typeRaw: String
    var thumbnail: Data?
    var fullData: Data?
    var sizeBytes: Int
    var mimeType: String
    var duration: TimeInterval?

    // MARK: - Computed Properties

    var type: AttachmentType {
        get { AttachmentType(rawValue: typeRaw) ?? .image }
        set { typeRaw = newValue.rawValue }
    }

    var isAudio: Bool {
        type == .voiceNote || type == .pttRecording
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        message: Message? = nil,
        type: AttachmentType = .image,
        thumbnail: Data? = nil,
        fullData: Data? = nil,
        sizeBytes: Int = 0,
        mimeType: String = "application/octet-stream",
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.message = message
        self.typeRaw = type.rawValue
        self.thumbnail = thumbnail
        self.fullData = fullData
        self.sizeBytes = sizeBytes
        self.mimeType = mimeType
        self.duration = duration
    }
}
