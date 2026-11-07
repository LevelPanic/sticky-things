// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickyThings",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StickyThings",
            path: "Sources/StickyThings",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StickyThingsTests",
            dependencies: ["StickyThings"],
            path: "Tests/StickyThingsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
