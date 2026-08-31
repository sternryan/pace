// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CodexPace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .executable(name: "CodexPace", targets: ["CodexPace"])
    ],
    targets: [
        .target(name: "PaceCore"),
        .executableTarget(
            name: "CodexPace",
            dependencies: ["PaceCore"],
            path: "Sources/Pace",
            exclude: ["ApiUsageSource.swift", "KeychainCredentialStore.swift", "ScrapeUsageSource.swift", "UsageFetcher.swift", "Info.plist"]
        ),
        .testTarget(name: "PaceCoreTests", dependencies: ["PaceCore"])
    ]
)
