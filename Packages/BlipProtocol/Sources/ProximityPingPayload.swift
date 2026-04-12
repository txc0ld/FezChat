import Foundation

public struct ProximityPingPayload: Sendable, Equatable {
    public static let serializedSize = 2
    public static let unavailableRSSI: Int8 = 0x7F

    public let rssiHint: Int8

    public init(rssiHint: Int8 = unavailableRSSI) {
        self.rssiHint = rssiHint
    }

    public func serialize() -> Data {
        Data([UInt8(bitPattern: rssiHint), 0x00])
    }

    public static func deserialize(from data: Data) -> ProximityPingPayload? {
        guard data.count >= serializedSize else { return nil }
        return ProximityPingPayload(rssiHint: Int8(bitPattern: data[0]))
    }
}
