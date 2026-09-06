// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FocusBreakAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "focus-break-probe", targets: ["FocusBreakProbe"]),
        .library(name: "FocusBreakProbeCore", targets: ["FocusBreakProbeCore"])
    ],
    targets: [
        .target(name: "FocusBreakProbeCore"),
        .executableTarget(
            name: "FocusBreakProbe",
            dependencies: ["FocusBreakProbeCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FocusBreakProbeCoreTests",
            dependencies: ["FocusBreakProbeCore"]
        )
    ]
)
