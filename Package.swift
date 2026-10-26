// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Brow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSensors", path: "Sources/CSensors", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "Brow", dependencies: ["CSensors"], path: "Sources/Brow"),
    ]
)
