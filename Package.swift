// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftHTF",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "SwiftHTF", targets: ["SwiftHTF"]),
        .executable(name: "SwiftHTFDemo", targets: ["SwiftHTFDemo"])
    ],
    targets: [
        .target(
            name: "SwiftHTF",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SwiftHTFDemo",
            dependencies: ["SwiftHTF"]
        ),
        .testTarget(
            name: "SwiftHTFTests",
            dependencies: ["SwiftHTF"]
        )
    ]
)
