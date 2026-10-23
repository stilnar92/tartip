// swift-tools-version: 6.0
// `swift build` / `swift test` for development; scripts/build.sh wraps the release
// binary into /Applications/Focus Modes.app.
import PackageDescription

let package = Package(
    name: "FocusModes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FocusModes",
            path: "Sources/FocusModes",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FocusModesTests",
            dependencies: ["FocusModes"],
            path: "Tests/FocusModesTests"
        ),
    ]
)
