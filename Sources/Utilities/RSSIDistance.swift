import Foundation

enum RSSIDistance {
    static func meters(fromRSSI rssi: Int) -> Double {
        let txPower: Double = -59
        let pathLossExponent: Double = 2.5
        return pow(10.0, (txPower - Double(rssi)) / (10.0 * pathLossExponent))
    }

    static func displayString(fromRSSI rssi: Int) -> String {
        let distance = meters(fromRSSI: rssi)
        if distance < 2 { return "~1m" }
        if distance < 5 { return "~\(Int(distance))m" }
        if distance < 15 { return "~\(Int(round(distance / 5) * 5))m" }
        if distance < 50 { return "~\(Int(round(distance / 10) * 10))m" }
        return "50m+"
    }
}
