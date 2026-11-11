// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Berth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Berth", targets: ["BerthApp"]),
        .executable(name: "BerthServiceTool", targets: ["BerthServiceTool"]),
        .executable(name: "BerthReadTool", targets: ["BerthReadTool"]),
        .executable(name: "berth-probe", targets: ["BerthProbe"])
    ],
    targets: [
        .target(name: "BerthCore"),
        .executableTarget(name: "BerthApp", dependencies: ["BerthCore"]),
        .executableTarget(name: "BerthServiceTool", dependencies: ["BerthCore"]),
        .executableTarget(name: "BerthReadTool", dependencies: ["BerthCore"]),
        .executableTarget(name: "BerthProbe", dependencies: ["BerthCore"]),
        .testTarget(name: "BerthCoreTests", dependencies: ["BerthCore"])
    ]
)
