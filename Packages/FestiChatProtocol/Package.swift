// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FestiChatProtocol",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "FestiChatProtocol",
            targets: ["FestiChatProtocol"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "FestiChatProtocol",
            path: "Sources"
        ),
        .testTarget(
            name: "FestiChatProtocolTests",
            dependencies: [
                "FestiChatProtocol",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
