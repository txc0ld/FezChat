// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FestiChatMesh",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "FestiChatMesh",
            targets: ["FestiChatMesh"]
        ),
    ],
    dependencies: [
        .package(path: "../FestiChatProtocol"),
        .package(path: "../FestiChatCrypto"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "FestiChatMesh",
            dependencies: [
                "FestiChatProtocol",
                "FestiChatCrypto",
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "FestiChatMeshTests",
            dependencies: [
                "FestiChatMesh",
                "FestiChatProtocol",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
