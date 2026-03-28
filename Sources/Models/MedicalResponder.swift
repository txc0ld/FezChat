import Foundation
import SwiftData

@Model
final class MedicalResponder {
    @Attribute(.unique)
    var id: UUID

    var user: User?
    var festival: Festival?
    var accessCodeHash: String
    var callsign: String
    var isOnDuty: Bool

    @Relationship
    var activeAlert: SOSAlert?

    var responseCount: Int
    var avgResponseTime: TimeInterval

    // MARK: - Computed Properties

    var hasActiveAlert: Bool {
        activeAlert != nil
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        user: User? = nil,
        festival: Festival? = nil,
        accessCodeHash: String,
        callsign: String,
        isOnDuty: Bool = false,
        activeAlert: SOSAlert? = nil,
        responseCount: Int = 0,
        avgResponseTime: TimeInterval = 0
    ) {
        self.id = id
        self.user = user
        self.festival = festival
        self.accessCodeHash = accessCodeHash
        self.callsign = callsign
        self.isOnDuty = isOnDuty
        self.activeAlert = activeAlert
        self.responseCount = responseCount
        self.avgResponseTime = avgResponseTime
    }
}
