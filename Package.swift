// swift-tools-version: 6.4
import PackageDescription

// macOS 15 and Apple silicon. Built with the macOS 27 SDK: Liquid Glass
// arrives on macOS 26 (a frosted look stands in before that) and Apple
// Intelligence on macOS 27, where the FoundationModels APIs Flyby uses exist.
// The linker weak-links FoundationModels by itself, since every use of it is
// behind an availability check; CI checks that it stays that way.
let package = Package(
    name: "Flyby",
    platforms: [.macOS(.v15)],
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
