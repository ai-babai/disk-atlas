// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskAtlas", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskAtlas", targets: ["DiskAtlas"]), .executable(name: "disk-atlas", targets: ["AtlasCLI"]),
    ],
    targets: [
        .target(name: "AtlasCore"), .executableTarget(name: "DiskAtlas", dependencies: ["AtlasCore"]),
        .executableTarget(name: "AtlasCLI", dependencies: ["AtlasCore"]),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"]),
    ], swiftLanguageModes: [.v5])
