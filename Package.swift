// swift-tools-version: 6.0
import PackageDescription

// Layers (each only depends on the ones above it):
//   StickyCore    – items, lossless capture, storage, clipboard output. No SwiftUI.
//   StickyDesign  – design tokens + reusable components. No app logic.
//   StickyThings  – the app: corner, panel, onboarding, settings.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "StickyThings",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StickyThings", targets: ["StickyThings"]),
    ],
    targets: [
        .target(name: "StickyCore", path: "Sources/StickyCore", swiftSettings: swift5,
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "StickyDesign", path: "Sources/StickyDesign", swiftSettings: swift5),
        .executableTarget(name: "StickyThings", dependencies: ["StickyCore", "StickyDesign"],
                          path: "Sources/StickyThings", swiftSettings: swift5),

        .testTarget(name: "StickyCoreTests", dependencies: ["StickyCore"],
                    path: "Tests/StickyCoreTests", swiftSettings: swift5),
        .testTarget(name: "StickyDesignTests", dependencies: ["StickyDesign"],
                    path: "Tests/StickyDesignTests", resources: [.copy("References")], swiftSettings: swift5),
        .testTarget(name: "StickyThingsTests", dependencies: ["StickyThings", "StickyCore", "StickyDesign"],
                    path: "Tests/StickyThingsTests", swiftSettings: swift5),
    ]
)
