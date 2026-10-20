// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Usage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Usage", path: "Sources/Usage")
    ]
)
