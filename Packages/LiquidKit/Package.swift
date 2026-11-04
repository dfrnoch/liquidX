// swift-tools-version: 6.2
// LiquidKit: everything behind the LiquidX app. `XKit` is the platform-neutral
// model, X API v2 client, OAuth 2.0 (PKCE) and demo data; `LiquidUI` is the shared
// SwiftUI interface for iOS, iPadOS and macOS. `LiquidUpdateSupport` holds the Mac
// update checks shared with the embedded installer XPC service (docs/updates.md).
// Zero external dependencies.
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "LiquidKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "XKit", targets: ["XKit"]),
        .library(name: "LiquidUI", targets: ["LiquidUI"]),
        // Linked by the Mac app's embedded update installer as well.
        .library(name: "LiquidUpdateSupport", targets: ["LiquidUpdateSupport"]),
    ],
    targets: [
        // Update validation and installation: Foundation, CryptoKit and Security only.
        .target(name: "LiquidUpdateSupport", swiftSettings: strict),
        .target(name: "XKit", dependencies: ["LiquidUpdateSupport"], swiftSettings: strict),
        .target(
            name: "LiquidUI",
            dependencies: ["XKit"],
            swiftSettings: strict + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "XKitTests",
            dependencies: ["XKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "LiquidUITests",
            dependencies: ["LiquidUI", "XKit", "LiquidUpdateSupport"],
            swiftSettings: strict
        ),
    ],
    swiftLanguageModes: [.v6]
)
