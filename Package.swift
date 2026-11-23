// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NirvanaWheel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NirvanaWheel",
            path: "Sources/NirvanaWheel"
        ),
        .testTarget(
            name: "NirvanaWheelTests",
            dependencies: ["NirvanaWheel"],
            path: "Tests/NirvanaWheelTests"
        ),
    ]
)
