// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Beanotch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSensors", path: "Sources/CSensors", linkerSettings: [.linkedFramework("IOKit")]),
        // FoundationModels exists from macOS 26: weakly linked, so Beanotch still starts on 14 and 15.
        .executableTarget(name: "Beanotch", dependencies: ["CSensors"], path: "Sources/Beanotch",
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])]),
    ]
)
