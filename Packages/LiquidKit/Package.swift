// swift-tools-version: 6.2
// LiquidKit: everything behind the LiquidX app. `XKit` is the platform-neutral
// model, X API v2 client, OAuth 2.0 (PKCE) and demo data; `LiquidUI` is the shared
// SwiftUI interface for iOS, iPadOS and macOS. Zero external dependencies.
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
    ],
    targets: [
        .target(name: "XKit", swiftSettings: strict),
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
    ],
    swiftLanguageModes: [.v6]
)
