// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentHuddle",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AgentHuddle", path: "Sources/AgentHuddle")
    ]
)
