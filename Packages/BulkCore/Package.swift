// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BulkCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BulkCore", targets: ["BulkCore"]),
    ],
    targets: [
        .target(
            name: "BulkCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BulkCoreTests",
            dependencies: ["BulkCore"]
        ),
    ]
)
