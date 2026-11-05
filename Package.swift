// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FNB58Monitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FNBCore"),
        .executableTarget(name: "FNB58Monitor", dependencies: ["FNBCore"]),
        .executableTarget(name: "fnbcheck", dependencies: ["FNBCore"]),
    ]
)
