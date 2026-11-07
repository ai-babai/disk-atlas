// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskAtlas", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskAtlas", targets: ["DiskAtlas"]), .executable(name: "disk-atlas", targets: ["AtlasCLI"]),
    ], dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2")],
    targets: [
        .target(name: "AtlasCore"), .executableTarget(name: "DiskAtlas", dependencies: ["AtlasCore"]),
        .executableTarget(
            name: "AtlasCLI",
            dependencies: ["AtlasCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"]),
    ], swiftLanguageModes: [.v5])
