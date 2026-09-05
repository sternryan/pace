// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .executable(name: "Pace", targets: ["Pace"])
    ],
    targets: [
        .target(name: "PaceCore"),
        .executableTarget(name: "Pace", dependencies: ["PaceCore"]),
        .testTarget(name: "PaceCoreTests", dependencies: ["PaceCore"])
    ]
)
