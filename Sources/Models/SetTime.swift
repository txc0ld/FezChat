import Foundation
import SwiftData

@Model
final class SetTime {
    @Attribute(.unique)
    var id: UUID

    var artistName: String
    var stage: Stage?
    var startTime: Date
    var endTime: Date
    var savedByUser: Bool
    var reminderSet: Bool

    // MARK: - Computed Properties

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var isLive: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }

    var isUpcoming: Bool {
        Date() < startTime
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        artistName: String,
        stage: Stage? = nil,
        startTime: Date,
        endTime: Date,
        savedByUser: Bool = false,
        reminderSet: Bool = false
    ) {
        self.id = id
        self.artistName = artistName
        self.stage = stage
        self.startTime = startTime
        self.endTime = endTime
        self.savedByUser = savedByUser
        self.reminderSet = reminderSet
    }
}
