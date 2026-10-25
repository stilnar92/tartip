// swift-tools-version: 6.0
// `swift build` / `swift test` for development; scripts/build.sh wraps the release
// binary into /Applications/Tartip.app.
import PackageDescription

let package = Package(
    name: "Tartip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tartip",
            path: "Sources/Tartip",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TartipTests",
            dependencies: ["Tartip"],
            path: "Tests/TartipTests"
        ),
    ]
)
