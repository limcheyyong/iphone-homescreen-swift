// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Homescreen",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Homescreen", path: "Sources/Homescreen"),
    ]
)
