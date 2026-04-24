import XCTest
@testable import Blip

@MainActor
final class AppDelegatePushClassificationTests: XCTestCase {

    func testClassifyRemotePush_alertOnly() {
        let kind = AppDelegate.classifyRemotePush(userInfo: [
            "aps": [
                "alert": [
                    "title": "HeyBlip",
                    "body": "Message from Alice"
                ]
            ]
        ])

        XCTAssertEqual(kind, .alertOnly)
    }

    func testClassifyRemotePush_silentWithNSNumber() {
        let kind = AppDelegate.classifyRemotePush(userInfo: [
            "aps": [
                "content-available": NSNumber(value: 1)
            ]
        ])

        XCTAssertEqual(kind, .silent)
    }

    func testClassifyRemotePush_silentWithInt() {
        let kind = AppDelegate.classifyRemotePush(userInfo: [
            "aps": [
                "content-available": 1
            ]
        ])

        XCTAssertEqual(kind, .silent)
    }

    func testClassifyRemotePush_silentWithString() {
        let kind = AppDelegate.classifyRemotePush(userInfo: [
            "aps": [
                "content-available": "1"
            ]
        ])

        XCTAssertEqual(kind, .silent)
    }

    func testClassifyRemotePush_alertAndSilent() {
        let kind = AppDelegate.classifyRemotePush(userInfo: [
            "aps": [
                "alert": [
                    "title": "HeyBlip",
                    "body": "Message from Alice"
                ],
                "content-available": NSNumber(value: 1)
            ]
        ])

        XCTAssertEqual(kind, .alertAndSilent)
    }

    func testClassifyRemotePush_neitherDefaultsToAlertOnly() {
        let kind = AppDelegate.classifyRemotePush(userInfo: [:])

        XCTAssertEqual(kind, .alertOnly)
    }
}
