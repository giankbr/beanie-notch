// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Beanie",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSensors", path: "Sources/CSensors", linkerSettings: [.linkedFramework("IOKit")]),
        // FoundationModels exists from macOS 26: weakly linked, so Beanie still starts on 14 and 15.
        .executableTarget(name: "Beanie", dependencies: ["CSensors"], path: "Sources/Beanie",
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])]),
    ]
)
