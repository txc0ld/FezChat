import Testing
import Foundation
@testable import BlipCrypto

/// Cross-language fixture for HEY1306 — pins the canonical bytes that the
/// CDN worker (`server/cdn/src/index.ts`) signs against the bytes Swift's
/// `JSONEncoder([.sortedKeys, .iso8601])` produces from an equivalent
/// `EventManifest.events` array. The matching assertion lives in
/// `server/cdn/test/manifest-signature.test.ts` — keep them in lockstep
/// when changing the canonical format.
@Suite("Manifest canonical encoding")
struct ManifestCanonicalEncodingTests {

    // Mirror of `EventsViewModel.ManifestEvent`. Re-declared here because the
    // app-level type is `private`; this test pins the *encoder behaviour*, which
    // is what determines the canonical bytes — not the struct's storage location.
    fileprivate struct ManifestEvent: Codable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
        let startDate: Date
        let endDate: Date
        let organizerSigningKey: String
        let stages: [String]?
        let location: String?
        let description: String?
        let imageURL: String?
        let attendeeCount: Int?
        let category: String?
    }

    private static let expectedCanonical =
        #"[{"attendeeCount":35000,"category":"festival","endDate":"2026-07-19T23:59:59Z","id":"550E8400-E29B-41D4-A716-446655440000","latitude":-28.7425,"location":"North Byron Parklands","longitude":153.561,"name":"Splendour in the Grass","organizerSigningKey":"","radiusMeters":2000,"startDate":"2026-07-17T00:00:00Z"}]"#

    private static let expectedPublicKeyB64 = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
    private static let expectedSignatureB64 =
        "Fmc5giGePXpcBhcUMLzQ3QLCPRmTQsjIK6vCyPFJt93gfVlUG0UUsL0FTA1zW1k1hw9v5zMDi31fCEpvUvWBBA=="

    private static func fixtureEvents() throws -> [ManifestEvent] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let start = iso.date(from: "2026-07-17T00:00:00Z"),
              let end = iso.date(from: "2026-07-19T23:59:59Z"),
              let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000") else {
            throw ManifestFixtureError.invalidFixture
        }
        return [
            ManifestEvent(
                id: id,
                name: "Splendour in the Grass",
                latitude: -28.7425,
                longitude: 153.561,
                radiusMeters: 2000,
                startDate: start,
                endDate: end,
                organizerSigningKey: "",
                stages: nil,
                location: "North Byron Parklands",
                description: nil,
                imageURL: nil,
                attendeeCount: 35000,
                category: "festival"
            )
        ]
    }

    private enum ManifestFixtureError: Error { case invalidFixture }

    @Test("Swift encoder produces the cross-language canonical bytes")
    func encoderMatchesFixture() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(try Self.fixtureEvents())
        let actual = String(data: data, encoding: .utf8)
        #expect(actual == Self.expectedCanonical)
    }

    @Test("Signer.verifyDetached accepts the CDN-produced fixture signature")
    func verifierAcceptsFixtureSignature() throws {
        let messageData = Data(Self.expectedCanonical.utf8)
        guard let publicKey = Data(base64Encoded: Self.expectedPublicKeyB64),
              let signature = Data(base64Encoded: Self.expectedSignatureB64) else {
            Issue.record("Failed to decode fixture key/signature")
            return
        }

        let isValid = try Signer.verifyDetached(
            message: messageData,
            signature: signature,
            publicKey: publicKey
        )
        #expect(isValid)
    }

    @Test("Tampered canonical bytes do not verify")
    func verifierRejectsTamper() throws {
        let tampered = Self.expectedCanonical.replacingOccurrences(
            of: "Splendour",
            with: "splendour"
        )
        let messageData = Data(tampered.utf8)
        guard let publicKey = Data(base64Encoded: Self.expectedPublicKeyB64),
              let signature = Data(base64Encoded: Self.expectedSignatureB64) else {
            Issue.record("Failed to decode fixture key/signature")
            return
        }

        let isValid = try Signer.verifyDetached(
            message: messageData,
            signature: signature,
            publicKey: publicKey
        )
        #expect(!isValid)
    }
}
