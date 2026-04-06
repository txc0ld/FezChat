import Foundation

enum ServerConfig {
    private static func infoPlistValue(for key: String) -> String? {
        Bundle.main.infoDictionary?[key] as? String
    }

    static let authBaseURL: String = {
        infoPlistValue(for: "BLIP_AUTH_BASE_URL") ?? "https://blip-auth.john-mckean.workers.dev/v1"
    }()

    static let relayBaseURL: String = {
        infoPlistValue(for: "BLIP_RELAY_BASE_URL") ?? "https://blip-relay.john-mckean.workers.dev"
    }()

    static let cdnBaseURL: String = {
        infoPlistValue(for: "BLIP_CDN_BASE_URL") ?? "https://blip-cdn.john-mckean.workers.dev"
    }()

    static let relayWebSocketURL: URL = {
        let base = infoPlistValue(for: "BLIP_RELAY_BASE_URL") ?? "https://blip-relay.john-mckean.workers.dev"
        let wsBase = base.replacingOccurrences(of: "https://", with: "wss://")

        guard let url = URL(string: "\(wsBase)/ws") else {
            fatalError("Invalid relay WebSocket URL")
        }

        return url
    }()

    static let eventsManifestURL: String = {
        "\(cdnBaseURL)/manifests/events.json"
    }()
}
