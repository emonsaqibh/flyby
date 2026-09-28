// swift-tools-version: 6.4
import PackageDescription

// macOS 27 and Apple silicon only: Liquid Glass and the on-device Apple
// Intelligence model (FoundationModels) are the product, not options, and
// macOS 27 doesn't run on Intel Macs.
let package = Package(
    name: "Flyby",
    platforms: [.macOS(.v27)],
    targets: [
        // Everything that can be reasoned about without a window: the answer
        // model, markdown parsing, browser cookie import, AI Mode page logic.
        // Foundation only, strict Swift 6 concurrency, and unit-tested.
        .target(
            name: "FlybyCore",
            path: "Sources/FlybyCore"
        ),
        .executableTarget(
            name: "Flyby",
            dependencies: ["FlybyCore"],
            path: "Sources/Flyby",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FlybyCoreTests",
            dependencies: ["FlybyCore"],
            path: "Tests/FlybyCoreTests"
        ),
    ]
)
