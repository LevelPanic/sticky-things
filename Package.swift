// swift-tools-version: 6.0
import PackageDescription

// Monorepo:
//   packages/StickyCore    shared item model, storage, capture model. macOS + iOS.
//   packages/StickyDesign  macOS design tokens and components.
//   apps/macos             the macOS app.
//   apps/ios               the iOS app project (generated with XcodeGen).
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "StickyThings",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .executable(name: "StickyThings", targets: ["StickyThings"]),
        .library(name: "StickyCore", targets: ["StickyCore"]),
        .library(name: "StickyDesign", targets: ["StickyDesign"]),
    ],
    targets: [
        .target(name: "StickyCore", path: "packages/StickyCore/Sources/StickyCore", swiftSettings: swift5,
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "StickyDesign", path: "packages/StickyDesign/Sources/StickyDesign", swiftSettings: swift5),
        .executableTarget(name: "StickyThings", dependencies: ["StickyCore", "StickyDesign"],
                          path: "apps/macos/Sources/StickyThings", swiftSettings: swift5),

        .testTarget(name: "StickyCoreTests", dependencies: ["StickyCore"],
                    path: "packages/StickyCore/Tests/StickyCoreTests", swiftSettings: swift5),
        .testTarget(name: "StickyDesignTests", dependencies: ["StickyDesign"],
                    path: "packages/StickyDesign/Tests/StickyDesignTests", resources: [.copy("References")], swiftSettings: swift5),
        .testTarget(name: "StickyThingsTests", dependencies: ["StickyThings", "StickyCore", "StickyDesign"],
                    path: "apps/macos/Tests/StickyThingsTests", swiftSettings: swift5),
    ]
)
