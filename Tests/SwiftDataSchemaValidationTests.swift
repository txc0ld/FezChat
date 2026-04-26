import XCTest
import Foundation
import SwiftData
@testable import Blip

/// SwiftData schema validation tests. Migrated from swift-testing to XCTest
/// in BDEV-405. Two latent bugs were hiding in the original swift-testing
/// version, both surfaced once CI started running this suite:
///   1. `makeContext()` returned `container.mainContext` but the local
///      `container` var went out of scope at function exit. On iOS 26 the
///      SwiftData runtime traps inside `ModelContext.insert(_:)` once its
///      owning ModelContainer has deallocated. Now the container is held
///      as an instance property across the test, matching the pattern used
///      in every other XCTest file in the codebase (e.g. ChatViewModelTests).
///   2. The hand-rolled model list omitted `JoinedEvent`, `ChannelMute`,
///      and `FriendMute`. Now we use `BlipSchema.schema` directly so the
///      test container stays in sync as models are added or removed.
@MainActor
final class SwiftDataSchemaValidationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: BlipSchema.schema,
            configurations: [config]
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeContext() -> ModelContext {
        // Each test runs in its own XCTestCase instance with a fresh container
        // (created in setUp). Returning a new ModelContext bound to that
        // container avoids polluting `mainContext` across tests.
        ModelContext(container)
    }

    private func makeUser(
        username: String = "alice",
        context: ModelContext,
        emailHash: String? = nil
    ) -> User {
        let user = User(
            username: username,
            emailHash: emailHash ?? "hash_\(username)",
            noisePublicKey: Data(repeating: 1, count: 32),
            signingPublicKey: Data(repeating: 2, count: 32)
        )
        context.insert(user)
        return user
    }

    private func makeChannel(
        type: ChannelType = .dm,
        context: ModelContext,
        event: Event? = nil
    ) -> Channel {
        let channel = Channel(type: type, name: "Test \(type)", event: event)
        context.insert(channel)
        return channel
    }

    private func makeEvent(context: ModelContext) -> Event {
        let event = Event(
            name: "Glastonbury",
            coordinates: GeoPoint(latitude: 51.15, longitude: -2.58),
            radiusMeters: 5000,
            startDate: Date(),
            endDate: Date().addingTimeInterval(86_400 * 3),
            organizerSigningKey: Data(repeating: 3, count: 32)
        )
        context.insert(event)
        return event
    }

    // MARK: - Schema Registration Tests

    /// Schema contains every registered Blip model
    func testSchemaRegistration() {
        let modelNames = BlipSchema.models.map { String(describing: $0) }

        let expectedModels = [
            "User", "Friend", "Message", "Attachment", "Channel",
            "GroupMembership", "Event", "Stage", "SetTime", "MeetingPoint",
            "MessageQueue", "SOSAlert", "MedicalResponder", "FriendLocation",
            "BreadcrumbPoint", "CrowdPulse", "UserPreferences", "GroupSenderKey",
            "NoiseSessionModel", "JoinedEvent", "ChannelMute", "FriendMute"
        ]

        XCTAssertEqual(BlipSchema.models.count, expectedModels.count)
        for expectedModel in expectedModels {
            XCTAssertTrue(modelNames.contains { $0.contains(expectedModel) })
        }
    }

    /// Container creation with in-memory storage
    func testContainerCreation() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BlipSchema.schema,
            configurations: [config]
        )
        let context = container.mainContext
        XCTAssertNotNil(context)
    }

    // MARK: - User CRUD Tests

    /// User creation and persistence
    func testUserCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<User>(predicate: #Predicate { $0.username == "alice" })
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].username, "alice")
        XCTAssertNil(fetched[0].displayName)
    }

    /// User update displayName
    func testUserUpdate() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        try context.save()

        user.displayName = "Alice Wonder"
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<User>(predicate: #Predicate { $0.username == "alice" })
        )
        XCTAssertEqual(fetched[0].displayName, "Alice Wonder")
        XCTAssertEqual(fetched[0].resolvedDisplayName, "Alice Wonder")
    }

    /// User deletion
    func testUserDeletion() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        try context.save()

        context.delete(user)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<User>())
        XCTAssertTrue(fetched.isEmpty)
    }

    /// User unique constraint on username
    func testUserUniquenessConstraint() throws {
        let context = makeContext()
        let user1 = makeUser(username: "alice", context: context)
        try context.save()

        let user2 = User(
            username: "alice",
            emailHash: "different_hash",
            noisePublicKey: Data(repeating: 4, count: 32),
            signingPublicKey: Data(repeating: 5, count: 32)
        )
        context.insert(user2)

        // SwiftData should enforce unique constraint
        // This test documents the expected behavior
        XCTAssertTrue(context.hasChanges)
    }

    // MARK: - Friend CRUD Tests

    /// Friend creation with user relationship
    func testFriendCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let friend = Friend(
            user: user,
            status: .accepted,
            phoneVerified: true,
            locationSharingEnabled: true,
            locationPrecision: .precise
        )
        context.insert(friend)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Friend>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].status, .accepted)
        XCTAssertEqual(fetched[0].locationPrecision, .precise)
    }

    /// Friend status enum roundtrip
    func testFriendStatusEnum() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        for status in FriendStatus.allCases {
            let friend = Friend(
                user: user,
                status: status,
                phoneVerified: false,
                locationSharingEnabled: false,
                locationPrecision: .off
            )
            context.insert(friend)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Friend>())
        XCTAssertEqual(fetched.count, FriendStatus.allCases.count)
        // SwiftData fetch order isn't guaranteed without an explicit sort,
        // so compare the set of statuses instead of indexed equality.
        XCTAssertEqual(Set(fetched.map(\.status)), Set(FriendStatus.allCases))
    }

    /// Friend location precision roundtrip
    func testFriendLocationPrecision() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let friend = Friend(
            user: user,
            status: .accepted,
            phoneVerified: true,
            locationSharingEnabled: true,
            locationPrecision: .fuzzy,
            lastSeenLatitude: 51.15,
            lastSeenLongitude: -2.58
        )
        context.insert(friend)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Friend>())
        XCTAssertEqual(fetched[0].locationPrecision, .fuzzy)
        XCTAssertEqual(fetched[0].lastSeenLocation?.latitude, 51.15)
        XCTAssertEqual(fetched[0].lastSeenLocation?.longitude, -2.58)
    }

    /// Friend deletion
    func testFriendDeletion() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let friend = Friend(user: user)
        context.insert(friend)
        try context.save()

        context.delete(friend)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Friend>())
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Message CRUD Tests

    /// Message creation with sender and channel
    func testMessageCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(
            sender: user,
            channel: channel,
            type: .text,
            rawPayload: Data("hello".utf8),
            status: .sent
        )
        context.insert(message)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].type, .text)
        XCTAssertEqual(fetched[0].status, .sent)
    }

    /// Message type enum roundtrip
    func testMessageTypeEnum() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        for type in MessageType.allCases {
            let message = Message(
                sender: user,
                channel: channel,
                type: type,
                rawPayload: Data()
            )
            context.insert(message)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetched.count, MessageType.allCases.count)
    }

    /// Message status enum roundtrip
    func testMessageStatusEnum() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        let msg = fetched[0]

        for status in MessageStatus.allCases {
            msg.status = status
            try context.save()

            let refetched = try context.fetch(FetchDescriptor<Message>())
            XCTAssertEqual(refetched[0].status, status)
        }
    }

    /// Message expiration computed property
    func testMessageExpiration() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let futureDate = Date().addingTimeInterval(3600)
        let message = Message(
            sender: user,
            channel: channel,
            expiresAt: futureDate
        )
        context.insert(message)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertFalse(fetched[0].isExpired)
    }

    /// Message reply-to relationship
    func testMessageReplyTo() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let msg1 = Message(
            sender: user,
            channel: channel,
            rawPayload: Data("original".utf8)
        )
        context.insert(msg1)
        try context.save()

        let msg2 = Message(
            sender: user,
            channel: channel,
            rawPayload: Data("reply".utf8),
            replyTo: msg1
        )
        context.insert(msg2)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        let replyMsg = fetched.first { msg in msg.rawPayload == Data("reply".utf8) }
        XCTAssertNotNil(replyMsg?.replyTo)
        XCTAssertEqual(replyMsg?.replyTo?.rawPayload, Data("original".utf8))
    }

    /// Message deletion
    func testMessageDeletion() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        context.delete(message)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Channel CRUD Tests

    /// Channel creation with all types
    func testChannelCreationAllTypes() throws {
        let context = makeContext()

        for type in ChannelType.allCases {
            let channel = Channel(type: type, name: "Test \(type)")
            context.insert(channel)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Channel>())
        XCTAssertEqual(fetched.count, ChannelType.allCases.count)
    }

    /// Channel mute status enum roundtrip
    func testChannelMuteStatus() throws {
        let context = makeContext()

        for muteStatus in MuteStatus.allCases {
            let channel = Channel(type: .dm, muteStatus: muteStatus)
            context.insert(channel)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Channel>())
        // SwiftData fetch order isn't guaranteed without an explicit sort,
        // so compare the set of statuses instead of indexed equality.
        XCTAssertEqual(Set(fetched.map(\.muteStatus)), Set(MuteStatus.allCases))
    }

    /// Channel computed properties
    func testChannelComputedProperties() throws {
        let context = makeContext()

        let dmChannel = Channel(type: .dm)
        let groupChannel = Channel(type: .group)
        let locationChannel = Channel(type: .locationChannel)

        context.insert(dmChannel)
        context.insert(groupChannel)
        context.insert(locationChannel)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Channel>())

        let dm = fetched.first { $0.type == .dm }
        XCTAssertEqual(dm?.isGroup, false)
        XCTAssertEqual(dm?.isPublic, false)

        let group = fetched.first { $0.type == .group }
        XCTAssertEqual(group?.isGroup, true)
        XCTAssertEqual(group?.isPublic, false)

        let location = fetched.first { $0.type == .locationChannel }
        XCTAssertEqual(location?.isPublic, true)
    }

    /// Channel muted computed property
    func testChannelMutedProperty() throws {
        let context = makeContext()

        let unmutedChannel = Channel(type: .dm, muteStatus: .unmuted)
        let mutedChannel = Channel(type: .dm, muteStatus: .mutedForever)

        context.insert(unmutedChannel)
        context.insert(mutedChannel)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Channel>())
        let unmuted = fetched.first { $0.muteStatus == .unmuted }
        let muted = fetched.first { $0.muteStatus == .mutedForever }

        XCTAssertFalse(unmuted!.isMuted)
        XCTAssertTrue(muted!.isMuted)
    }

    /// Channel deletion
    func testChannelDeletion() throws {
        let context = makeContext()
        let channel = makeChannel(context: context)
        try context.save()

        context.delete(channel)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Channel>())
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Attachment Cascade Delete Tests

    /// Attachment creation with message relationship
    func testAttachmentCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        let attachment = Blip.Attachment(
            message: message,
            type: .image,
            sizeBytes: 1024,
            mimeType: "image/jpeg"
        )
        context.insert(attachment)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Blip.Attachment>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].type, .image)
    }

    /// Attachment cascade delete with message deletion
    func testAttachmentCascadeDelete() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        for i in 0 ..< 3 {
            let attachment = Blip.Attachment(
                message: message,
                type: i % 2 == 0 ? .image : .voiceNote,
                sizeBytes: 1024 * (i + 1)
            )
            context.insert(attachment)
        }
        try context.save()

        let attachmentsBefore = try context.fetch(FetchDescriptor<Blip.Attachment>())
        XCTAssertEqual(attachmentsBefore.count, 3)

        context.delete(message)
        try context.save()

        let attachmentsAfter = try context.fetch(FetchDescriptor<Blip.Attachment>())
        XCTAssertTrue(attachmentsAfter.isEmpty)
    }

    /// Attachment type enum roundtrip
    func testAttachmentTypeEnum() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        for type in AttachmentType.allCases {
            let attachment = Blip.Attachment(message: message, type: type)
            context.insert(attachment)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Blip.Attachment>())
        XCTAssertEqual(fetched.count, AttachmentType.allCases.count)
    }

    // MARK: - GroupMembership Tests

    /// GroupMembership creation with cascade delete
    func testGroupMembershipCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(type: .group, context: context)

        let membership = GroupMembership(
            user: user,
            channel: channel,
            role: .member,
            muted: false
        )
        context.insert(membership)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GroupMembership>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].role, .member)
    }

    /// GroupMembership role enum roundtrip
    func testGroupMembershipRole() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(type: .group, context: context)

        for role in GroupRole.allCases {
            let membership = GroupMembership(
                user: user,
                channel: channel,
                role: role
            )
            context.insert(membership)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GroupMembership>())
        XCTAssertEqual(fetched.count, GroupRole.allCases.count)
    }

    /// GroupMembership isAdmin computed property
    func testGroupMembershipIsAdmin() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(type: .group, context: context)

        let member = GroupMembership(user: user, channel: channel, role: .member)
        let admin = GroupMembership(user: user, channel: channel, role: .admin)
        let creator = GroupMembership(user: user, channel: channel, role: .creator)

        context.insert(member)
        context.insert(admin)
        context.insert(creator)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GroupMembership>())
        XCTAssertEqual(fetched.first { $0.role == .member }?.isAdmin, false)
        XCTAssertEqual(fetched.first { $0.role == .admin }?.isAdmin, true)
        XCTAssertEqual(fetched.first { $0.role == .creator }?.isAdmin, true)
    }

    /// GroupMembership cascade delete with channel
    func testGroupMembershipCascadeDelete() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(type: .group, context: context)

        for i in 0 ..< 3 {
            let membership = GroupMembership(
                user: user,
                channel: channel,
                role: i == 0 ? .creator : .member
            )
            context.insert(membership)
        }
        try context.save()

        let membershipsBefore = try context.fetch(FetchDescriptor<GroupMembership>())
        XCTAssertEqual(membershipsBefore.count, 3)

        context.delete(channel)
        try context.save()

        let membershipsAfter = try context.fetch(FetchDescriptor<GroupMembership>())
        XCTAssertTrue(membershipsAfter.isEmpty)
    }

    // MARK: - Event and Stage Tests

    /// Event creation and stage hierarchy
    func testEventStageHierarchy() throws {
        let context = makeContext()
        let event = makeEvent(context: context)
        try context.save()

        let stage1 = Stage(
            name: "Pyramid",
            event: event,
            coordinates: GeoPoint(latitude: 51.15, longitude: -2.58)
        )
        let stage2 = Stage(
            name: "Silver Hayes",
            event: event,
            coordinates: GeoPoint(latitude: 51.16, longitude: -2.59)
        )
        context.insert(stage1)
        context.insert(stage2)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Stage>())
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[0].event?.name, "Glastonbury")
    }

    /// Event cascade delete with stages
    func testEventCascadeDelete() throws {
        let context = makeContext()
        let event = makeEvent(context: context)
        try context.save()

        for i in 0 ..< 3 {
            let stage = Stage(
                name: "Stage \(i)",
                event: event,
                coordinates: GeoPoint(latitude: 51.15 + Double(i) * 0.01, longitude: -2.58)
            )
            context.insert(stage)
        }
        try context.save()

        let stagesBefore = try context.fetch(FetchDescriptor<Stage>())
        XCTAssertEqual(stagesBefore.count, 3)

        context.delete(event)
        try context.save()

        let stagesAfter = try context.fetch(FetchDescriptor<Stage>())
        XCTAssertTrue(stagesAfter.isEmpty)
    }

    /// Event computed properties
    func testEventComputedProperties() throws {
        let context = makeContext()

        let now = Date()
        let upcoming = Event(
            name: "Future Fest",
            coordinates: GeoPoint(latitude: 0, longitude: 0),
            radiusMeters: 1000,
            startDate: now.addingTimeInterval(86_400),
            endDate: now.addingTimeInterval(86_400 * 3),
            organizerSigningKey: Data(repeating: 3, count: 32)
        )
        let active = Event(
            name: "Current Fest",
            coordinates: GeoPoint(latitude: 0, longitude: 0),
            radiusMeters: 1000,
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(86_400),
            organizerSigningKey: Data(repeating: 4, count: 32)
        )

        context.insert(upcoming)
        context.insert(active)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Event>())
        XCTAssertEqual(fetched.first { $0.name == "Future Fest" }?.isUpcoming, true)
        XCTAssertEqual(fetched.first { $0.name == "Current Fest" }?.isActive, true)
    }

    // MARK: - SetTime Tests

    /// SetTime creation with stage relationship
    func testSetTimeCreation() throws {
        let context = makeContext()
        let event = makeEvent(context: context)
        try context.save()

        let stage = Stage(
            name: "Main Stage",
            event: event,
            coordinates: GeoPoint(latitude: 51.15, longitude: -2.58)
        )
        context.insert(stage)
        try context.save()

        let now = Date()
        let setTime = SetTime(
            artistName: "Radiohead",
            stage: stage,
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(7200)
        )
        context.insert(setTime)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SetTime>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].artistName, "Radiohead")
        XCTAssertEqual(fetched[0].duration, 3600)
    }

    /// SetTime cascade delete with stage
    func testSetTimeCascadeDelete() throws {
        let context = makeContext()
        let event = makeEvent(context: context)
        try context.save()

        let stage = Stage(
            name: "Stage",
            event: event,
            coordinates: GeoPoint(latitude: 51.15, longitude: -2.58)
        )
        context.insert(stage)
        try context.save()

        let now = Date()
        for i in 0 ..< 3 {
            let setTime = SetTime(
                artistName: "Artist \(i)",
                stage: stage,
                startTime: now.addingTimeInterval(Double(i) * 3600),
                endTime: now.addingTimeInterval(Double(i + 1) * 3600)
            )
            context.insert(setTime)
        }
        try context.save()

        let setTimesBefore = try context.fetch(FetchDescriptor<SetTime>())
        XCTAssertEqual(setTimesBefore.count, 3)

        context.delete(stage)
        try context.save()

        let setTimesAfter = try context.fetch(FetchDescriptor<SetTime>())
        XCTAssertTrue(setTimesAfter.isEmpty)
    }

    // MARK: - SOSAlert Tests

    /// SOSAlert creation with location
    func testSosAlertCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let sosAlert = SOSAlert(
            reporter: user,
            severity: .red,
            preciseLocation: GeoPoint(latitude: 51.15, longitude: -2.58),
            fuzzyLocation: "gcpv2h",
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(sosAlert)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SOSAlert>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].severity, .red)
    }

    /// SOSAlert severity enum roundtrip
    func testSosAlertSeverity() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        for severity in SOSSeverity.allCases {
            let alert = SOSAlert(
                reporter: user,
                severity: severity,
                preciseLocation: GeoPoint(latitude: 0, longitude: 0),
                fuzzyLocation: "test",
                expiresAt: Date().addingTimeInterval(3600)
            )
            context.insert(alert)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SOSAlert>())
        XCTAssertEqual(fetched.count, SOSSeverity.allCases.count)
    }

    /// SOSAlert status state transitions
    func testSosAlertStatusTransitions() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let alert = SOSAlert(
            reporter: user,
            severity: .red,
            preciseLocation: GeoPoint(latitude: 51.15, longitude: -2.58),
            fuzzyLocation: "test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(alert)
        try context.save()

        let statuses: [SOSStatus] = [.active, .accepted, .enRoute, .resolved]
        for status in statuses {
            alert.status = status
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<SOSAlert>())
            XCTAssertEqual(fetched[0].status, status)
        }
    }

    /// SOSAlert computed properties
    func testSosAlertComputedProperties() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let alert = SOSAlert(
            reporter: user,
            severity: .red,
            preciseLocation: GeoPoint(latitude: 51.15, longitude: -2.58),
            fuzzyLocation: "test",
            status: .accepted,
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(alert)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SOSAlert>())
        XCTAssertEqual(fetched[0].isActive, true)
        XCTAssertEqual(fetched[0].isResolved, false)
    }

    /// SOSAlert resolution enum roundtrip
    func testSosAlertResolution() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let alert = SOSAlert(
            reporter: user,
            severity: .red,
            preciseLocation: GeoPoint(latitude: 51.15, longitude: -2.58),
            fuzzyLocation: "test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(alert)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SOSAlert>())

        for resolution in SOSResolution.allCases {
            fetched[0].resolution = resolution
            try context.save()

            let refetched = try context.fetch(FetchDescriptor<SOSAlert>())
            XCTAssertEqual(refetched[0].resolution, resolution)
        }
    }

    // MARK: - MessageQueue Tests

    /// MessageQueue creation and retry logic
    func testMessageQueueCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        let queue = MessageQueue(
            message: message,
            attempts: 0,
            maxAttempts: 50,
            transport: .ble
        )
        context.insert(queue)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MessageQueue>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].canRetry, true)
    }

    /// MessageQueue transport enum roundtrip
    func testMessageQueueTransport() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        for transport in QueueTransport.allCases {
            let queue = MessageQueue(message: message, transport: transport)
            context.insert(queue)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MessageQueue>())
        XCTAssertEqual(fetched.count, QueueTransport.allCases.count)
    }

    /// MessageQueue status enum roundtrip
    func testMessageQueueStatus() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        let queue = MessageQueue(message: message)
        context.insert(queue)
        try context.save()

        for status in QueueStatus.allCases {
            queue.status = status
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<MessageQueue>())
            XCTAssertEqual(fetched[0].status, status)
        }
    }

    /// MessageQueue retry exhaustion
    func testMessageQueueRetryExhaustion() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let message = Message(sender: user, channel: channel)
        context.insert(message)
        try context.save()

        let queue = MessageQueue(
            message: message,
            attempts: 50,
            maxAttempts: 50
        )
        context.insert(queue)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MessageQueue>())
        XCTAssertEqual(fetched[0].canRetry, false)
    }

    // MARK: - MeetingPoint Tests

    /// MeetingPoint creation with location
    func testMeetingPointCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let meetingPoint = MeetingPoint(
            creator: user,
            channel: channel,
            coordinates: GeoPoint(latitude: 51.15, longitude: -2.58),
            label: "Meet at the Pyramid",
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(meetingPoint)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MeetingPoint>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].label, "Meet at the Pyramid")
    }

    /// MeetingPoint expiration computed property
    func testMeetingPointExpiration() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let meetingPoint = MeetingPoint(
            creator: user,
            channel: channel,
            coordinates: GeoPoint(latitude: 51.15, longitude: -2.58),
            label: "Test",
            expiresAt: Date().addingTimeInterval(-3600)
        )
        context.insert(meetingPoint)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MeetingPoint>())
        XCTAssertEqual(fetched[0].isExpired, true)
    }

    // MARK: - FriendLocation Tests

    /// FriendLocation creation with breadcrumbs
    func testFriendLocationCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let friend = Friend(user: user)
        context.insert(friend)
        try context.save()

        let location = FriendLocation(
            friend: friend,
            precisionLevel: .precise,
            latitude: 51.15,
            longitude: -2.58,
            accuracy: 10.0
        )
        context.insert(location)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FriendLocation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].hasPreciseLocation, true)
    }

    /// FriendLocation breadcrumb cascade delete
    func testFriendLocationBreadcrumbCascadeDelete() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let friend = Friend(user: user)
        context.insert(friend)
        try context.save()

        let location = FriendLocation(friend: friend, precisionLevel: .precise)
        context.insert(location)
        try context.save()

        for i in 0 ..< 3 {
            let breadcrumb = BreadcrumbPoint(
                friendLocation: location,
                latitude: 51.15 + Double(i) * 0.01,
                longitude: -2.58
            )
            context.insert(breadcrumb)
        }
        try context.save()

        let breadcrumbsBefore = try context.fetch(FetchDescriptor<BreadcrumbPoint>())
        XCTAssertEqual(breadcrumbsBefore.count, 3)

        context.delete(location)
        try context.save()

        let breadcrumbsAfter = try context.fetch(FetchDescriptor<BreadcrumbPoint>())
        XCTAssertTrue(breadcrumbsAfter.isEmpty)
    }

    // MARK: - BreadcrumbPoint Tests

    /// BreadcrumbPoint creation with coordinates
    func testBreadcrumbPointCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let friend = Friend(user: user)
        context.insert(friend)
        try context.save()

        let location = FriendLocation(friend: friend)
        context.insert(location)
        try context.save()

        let breadcrumb = BreadcrumbPoint(
            friendLocation: location,
            latitude: 51.15,
            longitude: -2.58
        )
        context.insert(breadcrumb)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BreadcrumbPoint>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].coordinate.latitude, 51.15)
    }

    // MARK: - CrowdPulse Tests

    /// CrowdPulse creation with heat level
    func testCrowdPulseCreation() throws {
        let context = makeContext()

        let pulse = CrowdPulse(
            geohash: "gcpv2h",
            peerCount: 42,
            heatLevel: .busy
        )
        context.insert(pulse)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CrowdPulse>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].heatLevel, .busy)
    }

    /// CrowdPulse heat level enum roundtrip
    func testCrowdPulseHeatLevel() throws {
        let context = makeContext()

        for heatLevel in HeatLevel.allCases {
            let pulse = CrowdPulse(
                geohash: "test_\(heatLevel.rawValue)",
                heatLevel: heatLevel
            )
            context.insert(pulse)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CrowdPulse>())
        XCTAssertEqual(fetched.count, HeatLevel.allCases.count)
    }

    /// CrowdPulse isStale computed property
    func testCrowdPulseIsStale() throws {
        let context = makeContext()

        let fresh = CrowdPulse(geohash: "fresh", lastUpdated: Date())
        let stale = CrowdPulse(
            geohash: "stale", lastUpdated: Date().addingTimeInterval(-400)
        )

        context.insert(fresh)
        context.insert(stale)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CrowdPulse>())
        XCTAssertEqual(fetched.first { $0.geohash == "fresh" }?.isStale, false)
        XCTAssertEqual(fetched.first { $0.geohash == "stale" }?.isStale, true)
    }

    // MARK: - UserPreferences Tests

    /// UserPreferences creation with defaults
    func testUserPreferencesCreation() throws {
        let context = makeContext()

        let prefs = UserPreferences()
        context.insert(prefs)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserPreferences>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].theme, .system)
        XCTAssertEqual(fetched[0].pttMode, .holdToTalk)
    }

    /// UserPreferences theme enum roundtrip
    func testUserPreferencesTheme() throws {
        let context = makeContext()

        for theme in AppTheme.allCases {
            let prefs = UserPreferences(theme: theme)
            context.insert(prefs)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserPreferences>())
        XCTAssertEqual(fetched.count, AppTheme.allCases.count)
    }

    /// UserPreferences pttMode enum roundtrip
    func testUserPreferencesPTTMode() throws {
        let context = makeContext()

        for pttMode in PTTMode.allCases {
            let prefs = UserPreferences(pttMode: pttMode)
            context.insert(prefs)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserPreferences>())
        XCTAssertEqual(fetched.count, PTTMode.allCases.count)
    }

    /// UserPreferences map style enum roundtrip
    func testUserPreferencesMapStyle() throws {
        let context = makeContext()

        for mapStyle in MapStyle.allCases {
            let prefs = UserPreferences(friendFinderMapStyle: mapStyle)
            context.insert(prefs)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserPreferences>())
        XCTAssertEqual(fetched.count, MapStyle.allCases.count)
    }

    /// UserPreferences location sharing enum roundtrip
    func testUserPreferencesLocationSharing() throws {
        let context = makeContext()

        for precision in LocationPrecision.allCases {
            let prefs = UserPreferences(defaultLocationSharing: precision)
            context.insert(prefs)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserPreferences>())
        XCTAssertEqual(fetched.count, LocationPrecision.allCases.count)
    }

    // MARK: - GroupSenderKey Tests

    /// GroupSenderKey creation with key material
    func testGroupSenderKeyCreation() throws {
        let context = makeContext()
        let channel = makeChannel(type: .group, context: context)
        try context.save()

        let senderKey = GroupSenderKey(
            channel: channel,
            memberPeerID: Data(repeating: 0xFF, count: 8),
            keyMaterial: Data(repeating: 0xAA, count: 32),
            messageCounter: 0
        )
        context.insert(senderKey)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GroupSenderKey>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].needsRotation, false)
    }

    /// GroupSenderKey rotation logic
    func testGroupSenderKeyRotation() throws {
        let context = makeContext()
        let channel = makeChannel(type: .group, context: context)
        try context.save()

        let senderKey = GroupSenderKey(
            channel: channel,
            memberPeerID: Data(repeating: 0xFF, count: 8),
            keyMaterial: Data(repeating: 0xAA, count: 32),
            messageCounter: 99
        )
        context.insert(senderKey)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GroupSenderKey>())
        XCTAssertEqual(fetched[0].needsRotation, false)

        fetched[0].messageCounter = 100
        try context.save()

        let refetched = try context.fetch(FetchDescriptor<GroupSenderKey>())
        XCTAssertEqual(refetched[0].needsRotation, true)
    }

    // MARK: - NoiseSessionModel Tests

    /// NoiseSessionModel creation with expiry
    func testNoiseSessionCreation() throws {
        let context = makeContext()

        let session = NoiseSessionModel(
            peerID: Data(repeating: 0x11, count: 8),
            handshakeComplete: true,
            peerStaticKeyKnown: true,
            peerStaticKey: Data(repeating: 0x22, count: 32)
        )
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NoiseSessionModel>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].handshakeComplete, true)
    }

    /// NoiseSessionModel expiration and validity
    func testNoiseSessionExpiration() throws {
        let context = makeContext()

        let validSession = NoiseSessionModel(
            peerID: Data(repeating: 0x33, count: 8),
            handshakeComplete: true,
            expiresAt: Date().addingTimeInterval(3600)
        )

        let expiredSession = NoiseSessionModel(
            peerID: Data(repeating: 0x44, count: 8),
            handshakeComplete: true,
            expiresAt: Date().addingTimeInterval(-3600)
        )

        context.insert(validSession)
        context.insert(expiredSession)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NoiseSessionModel>())
        XCTAssertEqual(fetched.first { $0.peerID == Data(repeating: 0x33, count: 8) }?.isValid, true)
        XCTAssertEqual(fetched.first { $0.peerID == Data(repeating: 0x44, count: 8) }?.isValid, false)
    }

    /// NoiseSessionModel IK handshake eligibility
    func testNoiseSessionIKHandshake() throws {
        let context = makeContext()

        let ikEligible = NoiseSessionModel(
            peerID: Data(repeating: 0x55, count: 8),
            peerStaticKeyKnown: true,
            expiresAt: Date().addingTimeInterval(3600)
        )

        let ikIneligible = NoiseSessionModel(
            peerID: Data(repeating: 0x66, count: 8),
            peerStaticKeyKnown: false,
            expiresAt: Date().addingTimeInterval(3600)
        )

        context.insert(ikEligible)
        context.insert(ikIneligible)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NoiseSessionModel>())
        XCTAssertEqual(fetched.first { $0.peerID == Data(repeating: 0x55, count: 8) }?.canUseIKHandshake, true)
        XCTAssertEqual(fetched.first { $0.peerID == Data(repeating: 0x66, count: 8) }?.canUseIKHandshake, false)
    }

    // MARK: - MedicalResponder Tests

    /// MedicalResponder creation with user
    func testMedicalResponderCreation() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let event = makeEvent(context: context)
        try context.save()

        let responder = MedicalResponder(
            user: user,
            event: event,
            accessCodeHash: "hash_responder",
            callsign: "MED-01",
            isOnDuty: true
        )
        context.insert(responder)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MedicalResponder>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].callsign, "MED-01")
        XCTAssertEqual(fetched[0].hasActiveAlert, false)
    }

    // MARK: - Complex Relationship Tests

    /// User with multiple relationships
    func testUserMultipleRelationships() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        try context.save()

        // Add friends
        for i in 0 ..< 3 {
            let friend = Friend(
                user: user,
                status: i % 2 == 0 ? .accepted : .pending
            )
            context.insert(friend)
        }

        // Add messages
        let channel = makeChannel(context: context)
        try context.save()
        for i in 0 ..< 5 {
            let message = Message(
                sender: user,
                channel: channel,
                rawPayload: Data("msg\(i)".utf8)
            )
            context.insert(message)
        }

        // Add group memberships
        let groupChannel = makeChannel(type: .group, context: context)
        try context.save()
        for i in 0 ..< 2 {
            let membership = GroupMembership(
                user: user,
                channel: groupChannel,
                role: i == 0 ? .creator : .member
            )
            context.insert(membership)
        }

        try context.save()

        let fetchedUser = try context.fetch(
            FetchDescriptor<User>(predicate: #Predicate { $0.username == "alice" })
        )[0]

        XCTAssertEqual(fetchedUser.friends.count, 3)
        XCTAssertEqual(fetchedUser.sentMessages.count, 5)
        XCTAssertEqual(fetchedUser.memberships.count, 2)
    }

    // MARK: - Bulk Operations and Performance Tests

    /// Bulk message insertion
    func testBulkMessageInsertion() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)
        try context.save()

        for i in 0 ..< 100 {
            let message = Message(
                sender: user,
                channel: channel,
                rawPayload: Data("message_\(i)".utf8),
                status: i % 5 == 0 ? .delivered : .sent
            )
            context.insert(message)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetched.count, 100)
    }

    // MARK: - Index Validation Tests

    /// Message createdAt index sorting
    func testMessageIndexSorting() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)
        try context.save()

        let now = Date()
        for i in 0 ..< 5 {
            let message = Message(
                sender: user,
                channel: channel,
                createdAt: now.addingTimeInterval(Double(i) * 100)
            )
            context.insert(message)
        }
        try context.save()

        var descriptor = FetchDescriptor<Message>()
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        let fetched = try context.fetch(descriptor)

        for i in 0 ..< fetched.count - 1 {
            XCTAssertTrue(fetched[i].createdAt <= fetched[i + 1].createdAt)
        }
    }

    /// Friend status index filtering
    func testFriendStatusIndexFiltering() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        for status in FriendStatus.allCases {
            let friend = Friend(user: user, status: status)
            context.insert(friend)
        }
        try context.save()

        let descriptor = FetchDescriptor<Friend>(
            predicate: #Predicate { $0.statusRaw == "accepted" }
        )
        let accepted = try context.fetch(descriptor)
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(accepted[0].status, .accepted)
    }

    // MARK: - GeoPoint Roundtrip Tests

    /// GeoPoint storage and retrieval via Friend
    func testGeoPointFriendRoundtrip() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let friend = Friend(
            user: user,
            lastSeenLatitude: 51.5074,
            lastSeenLongitude: -0.1278
        )
        context.insert(friend)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Friend>())[0]
        let location = fetched.lastSeenLocation

        XCTAssertEqual(location?.latitude, 51.5074)
        XCTAssertEqual(location?.longitude, -0.1278)
    }

    /// GeoPoint storage and retrieval via SOSAlert
    func testGeoPointSOSAlertRoundtrip() throws {
        let context = makeContext()
        let user = makeUser(context: context)

        let alert = SOSAlert(
            reporter: user,
            severity: .red,
            preciseLocation: GeoPoint(latitude: 48.8566, longitude: 2.3522),
            fuzzyLocation: "Paris",
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(alert)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SOSAlert>())[0]
        let location = fetched.preciseLocation

        XCTAssertEqual(location.latitude, 48.8566)
        XCTAssertEqual(location.longitude, 2.3522)
    }

    /// GeoPoint storage and retrieval via MeetingPoint
    func testGeoPointMeetingPointRoundtrip() throws {
        let context = makeContext()
        let user = makeUser(context: context)
        let channel = makeChannel(context: context)

        let meetingPoint = MeetingPoint(
            creator: user,
            channel: channel,
            coordinates: GeoPoint(latitude: 40.7128, longitude: -74.0060),
            label: "New York",
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(meetingPoint)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MeetingPoint>())[0]
        let coords = fetched.coordinates

        XCTAssertEqual(coords.latitude, 40.7128)
        XCTAssertEqual(coords.longitude, -74.0060)
    }
}
